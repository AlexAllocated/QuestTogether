local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether

-- A small group questing around the same coastal town. These are fictional
-- quests; ownership and progress are explicit so the sample feels like a real
-- shared quest log rather than a catalogue of UI error states.
local QUESTS = {
	{ title = "A Shipment Gone Missing", shareable = true, progress = { "Have", "Have", false } },
	{ title = "Bandits on the Coast Road", shareable = true, progress = { "Have", "Have", "Have" } },
	{ title = "Supplies for the Watch", shareable = true, progress = { "Ready", "Ready", "Ready" } },
	{ title = "The Miller's Lost Ledger", shareable = true, progress = { "Have", "Ready", "Have" } },
	{ title = "Trouble at the Old Quarry", shareable = true, progress = { "Have", "Have", "Have" } },
	{ title = "A Letter for the Harbormaster", shareable = false, progress = { "Ready", "Ready", "Ready" } },
	{ title = "Wolves at the Orchard", shareable = true, progress = { "Have", "Have", "Have" } },
	{ title = "The Lighthouse Keeper", shareable = true, progress = { "Ready", "Have", "Have" } },
	{ title = "A Debt to the Innkeeper", shareable = false, progress = { "Have", "Have", "Have" } },
	{ title = "Mending the Fishermen's Nets", shareable = true, progress = { "Have", "Ready", "Have" } },
	{ title = "A Long Way from Home", shareable = true, progress = { "Have", "Have", "Have" } },
	{ title = "Signs of the Smugglers", shareable = true, progress = { "Have", "Have", "Have" } },
	{ title = "A Favor for the Herbalist", shareable = true, progress = { "Have", false, "Have" } },
	{ title = "The Missing Courier", shareable = true, progress = { false, "Have", "Have" } },
	{ title = "Beneath the Breakwater", shareable = true, progress = { false, false, "Have" } },
	{ title = "An Old Family Heirloom", shareable = false, progress = { "Have", false, false } },
}

local OBJECTIVES = {
	{ "Recover shipment crates", "Search the wrecked wagon" },
	{ "Coastal bandits defeated", "Find the bandit camp" },
	{ "Gather watch supplies", "Deliver supplies to the watch" },
	{ "Collect scattered ledger pages", "Return to the miller" },
	{ "Quarry prowlers defeated", "Inspect the abandoned tools" },
	{ "Letters delivered", "Speak to the harbormaster" },
	{ "Orchard wolves defeated", "Check the damaged fence" },
	{ "Collect lamp oil", "Relight the beacon" },
	{ "Collect overdue payments", "Return to the innkeeper" },
	{ "Gather lengths of twine", "Mend the fishing nets" },
	{ "Recover lost belongings", "Find the traveler's family" },
	{ "Collect smuggler markings", "Inspect the hidden landing" },
	{ "Gather coastal herbs", "Return to the herbalist" },
	{ "Collect courier satchels", "Find the courier's last camp" },
	{ "Defeat creatures beneath the breakwater", "Inspect the flooded tunnel" },
	{ "Recover heirloom fragments", "Speak to the family elder" },
}

local function Populate(preview)
	local members = {
		{ name = "Rowan-AeriePeak", state = "ready", isLocal = true, classFile = "PALADIN" },
		{ name = "Aria-AeriePeak", state = "ready", supportsShareRequests = true, classFile = "MAGE" },
		{ name = "Borin-AeriePeak", state = "ready", supportsShareRequests = true, classFile = "WARRIOR" },
	}
	local session = {
		playerName = members[1].name,
		members = members,
		byName = {},
		offset = 0,
		search = preview.partyQuestCompareSession and preview.partyQuestCompareSession.search or "",
	}
	for _, member in ipairs(members) do
		member.entries = {}
		session.byName[member.name] = member
	end
	for id, quest in ipairs(QUESTS) do
		for i, progress in ipairs(quest.progress) do
			if progress then
				members[i].entries[id] = {
					questId = id,
					questTitle = quest.title,
					isPushable = quest.shareable,
					isComplete = progress == "Ready",
				}
			end
		end
	end
	preview.partyQuestCompareSession = session
	preview.incompleteData = false
	preview.statuses = {}
	preview.previewFollowing, preview.previewFocus, preview.previewFollowStatus = nil, nil, nil
end

function QuestTogether:CreatePartyQuestComparePreview()
	local owner = self
	local render = self.RenderPartyQuestCompare
	-- Deliberately no inheritance from the live addon: only the model and view
	-- methods below are shared. This controller has no API or comms adapters.
	local preview = {
		options = { compareHideOtherQuests = false },
		GetScrollWindowTheme = self.GetScrollWindowTheme,
		BuildPartyQuestDiffRows = self.BuildPartyQuestDiffRows,
		BuildPartyQuestCompareDisplayRows = self.BuildPartyQuestCompareDisplayRows,
		GetPartyQuestReadiness = self.GetPartyQuestReadiness,
		CreatePartyQuestCompareWindow = self.CreatePartyQuestCompareWindow,
	}
	for _, method in ipairs({
		"GetPartyQuestCompareFilters",
		"SetPartyQuestCompareFilter",
		"ResetPartyQuestCompareFilters",
		"GetPartyQuestCompareFilterLabel",
		"ShowPartyQuestCompareFilters",
		"FilterPartyQuestCompareRows",
	}) do
		preview[method] = self[method]
	end
	function preview:CreatePartyQuestFilterMenu(frame, generator)
		local session = self.partyQuestCompareSession
		return owner:CreatePartyQuestFilterMenu(frame, function(menuOwner, root)
			generator(menuOwner, root)
			root:CreateDivider()
			root:CreateCheckbox(L("Preview incomplete data"), function()
				return self.incompleteData
			end, function()
				if self.partyQuestCompareSession ~= session then
					return
				end
				self.incompleteData = not self.incompleteData
				session.members[3].state = self.incompleteData and "timeout" or "ready"
				self:QueuePartyQuestCompareRender()
			end)
		end)
	end
	function preview:GetPartyQuestUIParent()
		return owner:GetPartyQuestUIParent()
	end
	function preview:GetClassColorCode(classFile)
		return owner:GetClassColorCode(classFile)
	end
	function preview:CreatePartyQuestUIFrame(...)
		return owner:CreatePartyQuestUIFrame(...)
	end
	function preview:ShowSettingsTooltip(...)
		return owner:ShowSettingsTooltip(...)
	end
	function preview:HideSettingsTooltip(...)
		return owner:HideSettingsTooltip(...)
	end
	function preview:CanAccessForeignFrame(...)
		return owner:CanAccessForeignFrame(...)
	end
	function preview:IsWorkBlocked(kind)
		return owner:IsWorkBlocked(kind)
	end
	function preview:GetOption(key)
		if key == "lightMode" then
			return owner:GetOption(key)
		end
		return self.options[key]
	end
	function preview:SetOption(key, value)
		self.options[key] = value
	end
	function preview:GetLocalizedQuestTitle()
		return nil
	end
	function preview:QueuePartyQuestTitleRefresh() end
	function preview:RefreshPartyRoster() end
	function preview:TogglePartyQuestObjectives(id)
		local session = self.partyQuestCompareSession
		if not session or self:IsWorkBlocked("foreign_frame_mutation") then
			return
		end
		session.expandedQuestIds = session.expandedQuestIds or {}
		session.expandedQuestIds[id] = not session.expandedQuestIds[id] or nil
		for i, member in ipairs(session.members) do
			local quest = member.entries[id]
			local complete = quest and quest.isComplete
			member.supportsObjectives = true
			member.objectiveDetails = member.objectiveDetails or {}
			member.objectiveDetails[id] = {
				questId = id,
				state = "ready",
				objectives = {
					{
						text = OBJECTIVES[id][1],
						kind = "item",
						current = complete and 8 or (i * 2),
						required = 8,
						finished = complete,
					},
					{ text = OBJECTIVES[id][2], kind = "event", finished = complete or i == 2 },
				},
			}
		end
		self:QueuePartyQuestCompareRender()
	end
	function preview:CancelPartyQuestCompare()
		self.partyQuestCompareSession = nil
	end
	function preview:RenderPartyQuestCompare()
		if self.partyQuestCompareSession and not self:IsWorkBlocked("foreign_frame_mutation") then
			render(self)
			self.partyQuestCompareWindow.summary:SetText(
				self.partyQuestCompareWindow.statusMessage
					or string.format(
						L(
							"DEBUG PREVIEW · %d mock players · %d quests shown · Actions are simulated · Refresh resets mock data"
						),
						#self.partyQuestCompareSession.members,
						#self:BuildPartyQuestDiffRows()
					)
			)
		end
	end
	function preview:QueuePartyQuestCompareRender()
		self:RenderPartyQuestCompare()
	end
	function preview:RefreshPartyQuestCompare()
		Populate(self)
		self.partyQuestCompareWindow.horizontal:SetValue(0)
		self:QueuePartyQuestCompareRender()
	end
	function preview:GetPartyQuestShareStatus(id)
		return self.statuses[id], self.statuses[id] ~= nil
	end
	local function Simulate(self, id, action, target)
		local session = self.partyQuestCompareSession
		if not session or self:IsWorkBlocked("quest_share") then
			return false
		end
		for _, row in ipairs(self:BuildPartyQuestDiffRows()) do
			if row.questId == id and row.action == action and (action ~= "request" or row.owner == target) then
				self.statuses[id] = action == "share" and "Share attempted" or "Awaiting confirmation"
				session.message = L("Preview only: ") .. L(self.statuses[id]) .. L(". No quest or message was sent.")
				self:QueuePartyQuestCompareRender()
				return true
			end
		end
		return false
	end
	function preview:SharePartyDiffQuest(id)
		return Simulate(self, id, "share")
	end
	function preview:RequestPartyQuestShare(id, target)
		return Simulate(self, id, "request", target)
	end
	function preview:GetPartyFocusLabel(name)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member then
			return L("Focus unavailable")
		end
		local id = member.isLocal and (self.previewFocus or 1) or (member.name == "Aria-AeriePeak" and 2 or 15)
		return QUESTS[id].title
	end
	function preview:GetPartyFollowingText()
		return self.previewFollowing
				and (string.format(L("Following: %s"), self.previewFollowing) .. (self.previewFollowStatus and ("\n" .. self.previewFollowStatus) or ""))
			or ""
	end
	function preview:StopPartyQuestFollow()
		self.previewFollowing, self.previewFollowStatus = nil, nil
		self:QueuePartyQuestCompareRender()
	end
	function preview:PopulatePartyFocusMenu(root, name)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member or member.isLocal then
			return
		end
		root:CreateTitle(self:GetPartyFocusLabel(name))
		root:CreateButton(self.previewFollowing == name and L("Stop following") or L("Follow quest focus"), function()
			if self.previewFollowing == name then
				self:StopPartyQuestFollow()
			else
				self.previewFollowing = name
				local id = name == "Aria-AeriePeak" and 2 or 15
				if session.byName[session.playerName].entries[id] then
					self.previewFocus, self.previewFollowStatus = id, nil
				else
					self.previewFollowStatus = L("You don't have this quest")
				end
				self:QueuePartyQuestCompareRender()
			end
		end)
	end

	return preview
end

function QuestTogether:OpenPartyQuestComparePreview()
	if self:IsWorkBlocked("foreign_frame_mutation") then
		self:Print(L("Quest comparison preview is unavailable while restricted. Try again when restrictions end."))
		return false
	end
	local preview = rawget(self, "partyQuestComparePreview")
	if not preview then
		preview = self:CreatePartyQuestComparePreview()
		self.partyQuestComparePreview = preview
	end
	local frame = preview:CreatePartyQuestCompareWindow()
	if not frame then
		return false
	end
	frame.title:SetText(L("Party Quest Log — Debug Preview"))
	preview:RefreshPartyQuestCompare()
	frame:Show()
	return true
end

function QuestTogether:ClosePartyQuestComparePreview()
	local preview = rawget(self, "partyQuestComparePreview")
	if preview and preview.partyQuestCompareWindow then
		preview.partyQuestCompareWindow:Hide()
		preview:CancelPartyQuestCompare()
	end
end
