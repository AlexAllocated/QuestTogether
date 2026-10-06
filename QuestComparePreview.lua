local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether

-- A small group questing around the same coastal town. These are fictional
-- quests; ownership and progress are explicit so the sample feels like a real
-- shared quest log rather than a catalogue of UI error states.
local QUESTS = {
	{ title = "A Shipment Gone Missing", shareable = true, progress = { "Have", "Have", false, "Have", "Ready" } },
	{ title = "Bandits on the Coast Road", shareable = true, progress = { "Have", "Have", "Have", "Have", "Have" } },
	{ title = "Supplies for the Watch", shareable = true, progress = { "Ready", "Ready", "Ready", "Ready", "Ready" } },
	{ title = "The Miller's Lost Ledger", shareable = true, progress = { "Have", "Ready", "Have", "Have", "Ready" } },
	{ title = "Trouble at the Old Quarry", shareable = true, progress = { "Have", "Have", "Have", "Ready", "Have" } },
	{ title = "A Letter for the Harbormaster", shareable = false, progress = { "Ready", "Ready", "Ready", "Ready", "Ready" } },
	{ title = "Wolves at the Orchard", shareable = true, progress = { "Have", "Have", "Have", "Have", "Have" } },
	{ title = "The Lighthouse Keeper", shareable = true, progress = { "Ready", "Have", "Have", "Have", "Have" } },
	{ title = "A Debt to the Innkeeper", shareable = false, progress = { "Have", "Have", "Have", "Have", "Have" } },
	{ title = "Mending the Fishermen's Nets", shareable = true, progress = { "Have", "Ready", "Have", "Ready", "Have" } },
	{ title = "A Long Way from Home", shareable = true, progress = { "Have", "Have", "Have", "Have", "Have" } },
	{ title = "Signs of the Smugglers", shareable = true, progress = { "Have", "Have", "Have", "Have", "Have" } },
	{ title = "A Favor for the Herbalist", shareable = true, progress = { "Have", false, "Have", "Have", false } },
	{ title = "The Missing Courier", shareable = true, progress = { false, "Have", "Have", false, "Have" } },
	{ title = "Beneath the Breakwater", shareable = true, progress = { false, false, "Have", "Have", false } },
	{ title = "An Old Family Heirloom", shareable = false, progress = { "Have", false, false, false, "Have" } },
}

local OBJECTIVE_COUNTS = { 2, 4, 6, 1, 5 }
local REGIONAL_NAMES = { "Rowan Lightward", "Aria Frostwind", "Borin Ironvale", "Celia Wildwood", "Dara Nightfall" }

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
		{ name = "Rowan-AeriePeak", state = "ready", isLocal = true, classFile = "PALADIN", focusQuestId = 1 },
		{ name = "Aria-AeriePeak", state = "ready", supportsShareRequests = true, classFile = "MAGE", focusQuestId = 2 },
		{ name = "Borin-AeriePeak", state = "ready", supportsShareRequests = true, classFile = "WARRIOR", focusQuestId = 15 },
		{ name = "Celia-AeriePeak", state = "ready", supportsShareRequests = true, classFile = "HUNTER", focusQuestId = 5 },
		{ name = "Dara-AeriePeak", state = "ready", supportsShareRequests = true, classFile = "ROGUE", focusQuestId = 14 },
	}
	if preview.regionalNames then
		for i, member in ipairs(members) do
			member.name = REGIONAL_NAMES[i]
		end
	end
	local session = {
		playerName = members[1].name,
		members = members,
		byName = {},
		offset = 0,
		search = preview.partyQuestCompareSession and preview.partyQuestCompareSession.search or "",
	}
	for _, member in ipairs(members) do
		member.entries = {}
		member.sampledAt = preview:GetPartyQuestCompareTime() - (member.isLocal and 0 or 30)
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
		regionalNames = self:UsesRegionalPlayerNames(),
		options = { compareHideOtherQuests = false },
		GetScrollWindowTheme = self.GetScrollWindowTheme,
		GetPartyQuestSnapshotLabel = self.GetPartyQuestSnapshotLabel,
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
			if frame.navName then
				root:CreateButton(L("Preview next focused quest"), function()
					if self.partyQuestCompareSession == session then self:AdvancePartyQuestFocus(frame.navName) end
				end)
			end
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
	function preview:RegisterManagedWindow(frame, _, minWidth, minHeight) return owner:RegisterManagedWindow(frame, nil, minWidth, minHeight) end
	function preview:SaveWindowLayout(frame) return owner:SaveWindowLayout(frame) end
	function preview:ApplyWindowLayout(frame) return owner:ApplyWindowLayout(frame) end
	function preview:GetPartyQuestCompareTime() return owner:GetPartyQuestCompareTime() end
	function preview:RefreshPartyQuestCompareMember(name)
		local member = self.partyQuestCompareSession.byName[name]
		if member then member.state, member.sampledAt = "ready", self:GetPartyQuestCompareTime() end
		self:QueuePartyQuestCompareRender()
	end
	function preview:GetPartyQuestUIParent()
		return owner:GetPartyQuestUIParent()
	end
	function preview:GetPartyQuestLeaderName()
		return self.partyQuestCompareSession and self.partyQuestCompareSession.playerName
	end
	function preview:GetClassColorCode(classFile)
		return owner:GetClassColorCode(classFile)
	end
	function preview:CreatePartyQuestUIFrame(...)
		return owner:CreatePartyQuestUIFrame(...)
	end
	-- Delegate only window movement; the isolated controller still has no
	-- live quest state or communications adapters.
	function preview:StartWindowDrag(frame)
		return owner:StartWindowDrag(frame)
	end
	function preview:StopWindowDrag(frame)
		return owner:StopWindowDrag(frame)
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
		if key == "lightMode" or key == "reduceMotion" or key == "windowScale" then
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
						current = complete and 8 or OBJECTIVE_COUNTS[i],
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
	function preview:OpenPartyQuestJournal(id)
		local session = self.partyQuestCompareSession
		local quest = session and session.byName[session.playerName].entries[id]
		if not quest or self:IsWorkBlocked("foreign_frame_mutation") then return false end
		session.message = L("Preview only: ") .. L("Open in Quest Log") .. ": " .. quest.questTitle
		self:QueuePartyQuestCompareRender()
		return true
	end
	function preview:GetPartyQuestFocusID(name)
		local member = self.partyQuestCompareSession and self.partyQuestCompareSession.byName[name]
		return member and (member.isLocal and (self.previewFocus or member.focusQuestId) or member.focusQuestId)
	end
	function preview:GetPartyFocusLabel(name)
		local id = self:GetPartyQuestFocusID(name)
		return QUESTS[id] and QUESTS[id].title or L("No focused quest")
	end
	function preview:SelectPartyQuestFocus(name, id)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member or not member.entries[id] then return false end
		if member.isLocal then
			self.previewFollowing, self.previewFocus = nil, id
		elseif member.focusQuestId == id then
			if session.byName[session.playerName].entries[id] then
				self.previewFollowing, self.previewFocus = name, id
			else
				self.previewFollowing = nil
				owner:ShowPartyFocusMissingDialog({ name = name, questID = id, title = QUESTS[id].title }, true)
			end
		else return false end
		self:QueuePartyQuestCompareRender()
		return true
	end
	function preview:AdvancePartyQuestFocus(name)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member or member.isLocal then return end
		for offset = 1, #QUESTS do
			local id = (member.focusQuestId + offset - 1) % #QUESTS + 1
			if member.entries[id] then
				member.focusQuestId = id
				if self.previewFollowing == name then self:SelectPartyQuestFocus(name, id) end
				break
			end
		end
		self:QueuePartyQuestCompareRender()
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
				self:SelectPartyQuestFocus(name, member.focusQuestId)
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
