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

local function Populate(preview)
	local members = {
		{ name = "Rowan-AeriePeak", state = "ready", isLocal = true },
		{ name = "Aria-AeriePeak", state = "ready", supportsShareRequests = true },
		{ name = "Borin-AeriePeak", state = "ready", supportsShareRequests = true },
	}
	local session = { playerName = members[1].name, members = members, byName = {}, offset = 0 }
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
	preview.statuses = {}
end

function QuestTogether:CreatePartyQuestComparePreview()
	local owner = self
	local render = self.RenderPartyQuestCompare
	-- Deliberately no inheritance from the live addon: only the model and view
	-- methods below are shared. This controller has no API or comms adapters.
	local preview = {
		options = { compareHideOtherQuests = false },
		BuildPartyQuestDiffRows = self.BuildPartyQuestDiffRows,
		CreatePartyQuestCompareWindow = self.CreatePartyQuestCompareWindow,
	}
	function preview:GetPartyQuestUIParent()
		return owner:GetPartyQuestUIParent()
	end
	function preview:CreatePartyQuestUIFrame(...)
		return owner:CreatePartyQuestUIFrame(...)
	end
	function preview:CanAccessForeignFrame(...)
		return owner:CanAccessForeignFrame(...)
	end
	function preview:IsWorkBlocked(kind)
		return owner:IsWorkBlocked(kind)
	end
	function preview:GetOption(key)
		return self.options[key]
	end
	function preview:SetOption(key, value)
		self.options[key] = value
	end
	function preview:RefreshPartyRoster() end
	function preview:CancelPartyQuestCompare()
		self.partyQuestCompareSession = nil
	end
	function preview:RenderPartyQuestCompare()
		if self.partyQuestCompareSession and not self:IsWorkBlocked("foreign_frame_mutation") then
			render(self)
			self.partyQuestCompareWindow.summary:SetText(
				string.format(
					"DEBUG PREVIEW · %d mock players · %d quests shown · Actions are simulated · Refresh resets mock data",
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
				session.message = "Preview only: " .. self.statuses[id] .. ". No quest or message was sent."
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
	return preview
end

function QuestTogether:OpenPartyQuestComparePreview()
	if self:IsWorkBlocked("foreign_frame_mutation") then
		self:Print("Quest comparison preview is unavailable while restricted. Try again when restrictions end.")
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
	frame.title:SetText("Party Quest Compare — Debug Preview")
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
