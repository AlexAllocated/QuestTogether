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
	preview.questCatalog, preview.questOrder, preview.liveQuestData = {}, {}, false
	for id, quest in ipairs(QUESTS) do
		preview.questCatalog[id] = { title = quest.title, mockIndex = id }
		preview.questOrder[#preview.questOrder + 1] = id
	end
	preview:PopulateLocalQuests(session)
	preview.partyNavigationState = { peers = {} }
	preview.partyQuestCompareSession = session
	preview.incompleteData = false
	preview.statuses = {}
	preview.previewFollowing, preview.previewFocus, preview.previewFollowStatus = nil, nil, nil
end

function QuestTogether:CreatePartyQuestComparePreview()
	local owner = self
	local render = self.RenderPartyQuestCompare
	-- No inheritance from live state. Only explicit read adapters and the native
	-- quest setter cross the preview boundary; party traffic and saves stay private.
	local preview = {
		regionalNames = self:UsesRegionalPlayerNames(),
		options = { compareHideOtherQuests = false },
		GetScrollWindowTheme = self.GetScrollWindowTheme,
		RequestPartyQuestFocus = self.RequestPartyQuestFocus,
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
	function preview:PopulateLocalQuests(session)
		if not owner.API or type(owner.API.GetActiveTrackedQuestID) ~= "function"
			or type(owner.API.GetPartyNavigationNativeState) ~= "function"
			or type(owner.API.SetPartyNavigationQuest) ~= "function" then return end
		local entries = owner:BuildQuestCompareEntries()
		if not entries then return end -- Keep the standalone fixture when data is unavailable.
		self.liveQuestData, self.questCatalog, self.questOrder = true, {}, {}
		local own = session.members[1]
		own.name, own.classFile = owner:GetPlayerFullName(), owner:GetPlayerClassFile()
		session.playerName, session.byName = own.name, {}
		for _, member in ipairs(session.members) do
			if not member.isLocal and member.name == own.name then member.name = member.name .. " (QT)" end
			member.entries, member.focusQuestId = {}, 0
			session.byName[member.name] = member
		end
		for index, entry in ipairs(entries) do
			local id = owner:NormalizeQuestID(entry.questId)
			if id then
				self.questCatalog[id] = { title = entry.questTitle }
				self.questOrder[#self.questOrder + 1] = id
				local pattern = QUESTS[(index - 1) % #QUESTS + 1]
				for i, member in ipairs(session.members) do
					if i == 1 or pattern.progress[i] then
						member.entries[id] = { questId = id, questTitle = entry.questTitle, isPushable = entry.isPushable,
							isComplete = i == 1 and entry.isComplete or (i ~= 1 and pattern.progress[i] == "Ready") }
						if member.focusQuestId == 0 then member.focusQuestId = id end
					end
				end
			end
		end
		-- Synthetic IDs are private, cannot collide with this quest log, and are
		-- never passed to native navigation or sent to any peer.
		local id = 900000000
		for _, mockIndex in ipairs({ 14, 15 }) do
			while self.questCatalog[id] do id = id + 1 end
			local quest = QUESTS[mockIndex]
			self.questCatalog[id] = { title = quest.title, mockIndex = mockIndex }
			self.questOrder[#self.questOrder + 1] = id
			for i = 2, #session.members do
				local member = session.members[i]
				if quest.progress[i] then
					member.entries[id] = { questId = id, questTitle = quest.title, isPushable = true, isComplete = false }
					if member.focusQuestId == 0 then member.focusQuestId = id end
				end
			end
			id = id + 1
		end
		for i = 2, #session.members do
			local available = {}
			for _, questId in ipairs(self.questOrder) do
				if session.members[i].entries[questId] then available[#available + 1] = questId end
			end
			if #available > 0 then session.members[i].focusQuestId = available[(i - 2) % #available + 1] end
		end
	end
	-- Use the production follow state machine against a private party model.
	-- Its transport and persistence adapters intentionally do nothing.
	preview.API = {
		GetActiveTrackedQuestID = function() return owner.API.GetActiveTrackedQuestID() end,
		GetPartyNavigationNativeState = function() return owner.API.GetPartyNavigationNativeState() end,
		IsOnQuest = function(id)
			local session = preview.partyQuestCompareSession
			if not session or not session.byName[session.playerName].entries[id] then return false end
			return owner.API.IsOnQuest(id)
		end,
		SetPartyNavigationQuest = function(id)
			if not preview.partyQuestCompareSession or preview:IsRuntimeRestricted()
				or (id ~= 0 and not preview.API.IsOnQuest(id)) then return false end
			return owner.API.SetPartyNavigationQuest(id)
		end,
	}
	for _, method in ipairs({ "ApplyPartyQuestFocus", "SamplePartyNavigation", "OnPartyNavigationTrackingChanged",
		"FollowPartyQuestFocus", "ReconcilePartyQuestFollow", "SelectPartyQuestFocus" }) do
		preview["Native" .. method] = owner[method]
	end
	function preview:IsRuntimeRestricted() return owner:IsRuntimeRestricted() end
	function preview:CanAccessValue(value) return owner:CanAccessValue(value) end
	function preview:CanAccessTable(value) return owner:CanAccessTable(value) end
	function preview:SafeToNumber(value) return owner:SafeToNumber(value) end
	function preview:NormalizeMemberName(value) return value end
	function preview:GetPlayerFullName() return self.partyQuestCompareSession and self.partyQuestCompareSession.playerName end
	function preview:IsSelfSender(name) return name == self:GetPlayerFullName() end
	function preview:IsGroupedSender(name) return self.partyQuestCompareSession and self.partyQuestCompareSession.byName[name] ~= nil end
	function preview:IsIgnoredPlayerName() return false end
	function preview:WouldPartyQuestFollowCycle() return false end
	function preview:SavePartyQuestFollow() end
	function preview:ClearPartyFocusMissingNotice() end
	function preview:QueuePartyNavigationUpdate() end
	function preview:GetPartyNavigationState() return self.partyNavigationState end
	function preview:GetPartyNavigationPeer(name)
		local member = self.partyQuestCompareSession and self.partyQuestCompareSession.byName[name]
		return member and { questID = member.focusQuestId, title = self:GetPartyFocusLabel(name) } or nil
	end
	function preview:QueuePartyFocusMissingNotice(name, id, title)
		owner:ShowPartyFocusMissingDialog({ name = name, questID = id, title = title }, true)
	end
	function preview:OnPartyNavigationTrackingChanged() return self:NativeOnPartyNavigationTrackingChanged() end
	function preview:FollowPartyQuestFocus(name) return self:NativeFollowPartyQuestFocus(name) end
	function preview:ApplyPartyQuestFocus() return self:NativeApplyPartyQuestFocus() end
	function preview:SamplePartyNavigation() return self:NativeSamplePartyNavigation() end
	function preview:ReconcilePartyQuestFollow() return self:NativeReconcilePartyQuestFollow() end
	function preview:StartNavigationObserver()
		if not self.liveQuestData then return end
		local observer = self.navigationObserver
		if not observer then
			observer = self:CreatePartyQuestUIFrame("Frame", nil, self.partyQuestCompareWindow)
			self.navigationObserver = observer
			observer:SetScript("OnEvent", function()
				if self.liveQuestData and self.partyQuestCompareSession then self:NativeOnPartyNavigationTrackingChanged() end
			end)
			observer:SetScript("OnUpdate", function(_, elapsed)
				if not self.liveQuestData or not self.partyQuestCompareSession then return end
				self.navigationElapsed = (self.navigationElapsed or 0) + elapsed
				if self.navigationElapsed < 0.25 then return end
				self.navigationElapsed = 0
				if self.partyNavigationState.checkExternal then self:SamplePartyNavigation() end
				self:ApplyPartyQuestFocus()
			end)
		end
		if observer.RegisterEvent then observer:RegisterEvent("SUPER_TRACKING_CHANGED") end
		observer:Show()
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
	-- Window movement stays owned by QT; no Blizzard frame state is patched.
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
		local catalog = self.questCatalog[id]
		if not catalog then return end
		local nativeObjectives = self.liveQuestData and not catalog.mockIndex and owner:ReadQuestCompareObjectives(id) or nil
		for i, member in ipairs(session.members) do
			local quest = member.entries[id]
			local complete = quest and quest.isComplete
			member.supportsObjectives = true
			member.objectiveDetails = member.objectiveDetails or {}
			local objectives
			if catalog.mockIndex then
				objectives = {
					{ text = OBJECTIVES[catalog.mockIndex][1], kind = "item", current = complete and 8 or OBJECTIVE_COUNTS[i], required = 8, finished = complete },
					{ text = OBJECTIVES[catalog.mockIndex][2], kind = "event", finished = complete or i == 2 },
				}
			elseif nativeObjectives then
				objectives = {}
				for index, objective in ipairs(nativeObjectives) do
					local copy = {}
					for key, value in pairs(objective) do copy[key] = value end
					if not member.isLocal then
						copy.finished = complete == true
						if copy.required then
							copy.current = complete and copy.required or math.floor(copy.required * OBJECTIVE_COUNTS[i] / 9)
						end
					end
					objectives[index] = copy
				end
			end
			member.objectiveDetails[id] = {
				questId = id,
				state = "ready",
				objectives = objectives,
			}
		end
		self:QueuePartyQuestCompareRender()
	end
	function preview:CancelPartyQuestCompare()
		local wasNative = self.liveQuestData and self.partyQuestCompareSession ~= nil
		self.partyQuestCompareSession, self.partyNavigationState = nil, nil
		if self.navigationObserver then
			if self.navigationObserver.UnregisterAllEvents then self.navigationObserver:UnregisterAllEvents() end
			self.navigationObserver:Hide()
		end
		if wasNative then
			local state = rawget(owner, "partyNavigationState")
			if state and state.following then
				-- The preview can have changed native focus after the live model's
				-- last successful attempt. Establish a new baseline before resuming.
				state.attempt, state.checkExternal, state.resuming = nil, nil, true
			end
			owner:QueuePartyNavigationUpdate()
		end
	end
	function preview:RenderPartyQuestCompare()
		if self.partyQuestCompareSession and not self:IsWorkBlocked("foreign_frame_mutation") then
			render(self)
			self.partyQuestCompareWindow.summary:SetText(
				self.partyQuestCompareWindow.statusMessage
					or (self.liveQuestData and L("PREVIEW · Your quest log + 4 simulated teammates · Focus changes affect your real navigation"))
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
		self:StartNavigationObserver()
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
	function preview:GetPartyQuestFollowTarget()
		if self.liveQuestData then return QuestTogether.GetPartyQuestFollowTarget(self) end
		return self.previewFollowing, self.previewFollowToken
	end
	function preview:ShowPartyFocusChangeDialog(name, callback)
		return owner:ShowPartyFocusChangeDialog(name, callback, true, self.liveQuestData)
	end
	function preview:GetPartyQuestFocusID(name)
		local member = self.partyQuestCompareSession and self.partyQuestCompareSession.byName[name]
		if member and member.isLocal and self.liveQuestData then
			if self:IsRuntimeRestricted() then return nil end
			return self.API.GetActiveTrackedQuestID() or 0
		end
		return member and (member.isLocal and (self.previewFocus or member.focusQuestId) or member.focusQuestId)
	end
	function preview:GetPartyFocusLabel(name)
		local id = self:GetPartyQuestFocusID(name)
		return self.questCatalog[id] and self.questCatalog[id].title or L("No focused quest")
	end
	function preview:SelectPartyQuestFocus(name, id)
		if self.liveQuestData then return self:NativeSelectPartyQuestFocus(name, id) end
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member or not member.entries[id] then return false end
		if member.isLocal then
			self.previewFollowing, self.previewFocus = nil, id
		elseif member.focusQuestId == id then
			if session.byName[session.playerName].entries[id] then
				if self.previewFollowing ~= name then self.previewFollowToken = {} end
				self.previewFollowing, self.previewFocus = name, id
			else
				self.previewFollowing = nil
				owner:ShowPartyFocusMissingDialog({ name = name, questID = id, title = self.questCatalog[id].title }, true)
			end
		else return false end
		self:QueuePartyQuestCompareRender()
		return true
	end
	function preview:AdvancePartyQuestFocus(name)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member or member.isLocal then return end
		local start = 0
		for index, id in ipairs(self.questOrder) do if id == member.focusQuestId then start = index; break end end
		for offset = 1, #self.questOrder do
			local id = self.questOrder[(start + offset - 1) % #self.questOrder + 1]
			if member.entries[id] then
				member.focusQuestId = id
				if self:GetPartyQuestFollowTarget() == name then
					if self.liveQuestData then self:ApplyPartyQuestFocus() else self:SelectPartyQuestFocus(name, id) end
				end
				break
			end
		end
		self:QueuePartyQuestCompareRender()
	end

	function preview:GetPartyFollowingText()
		if self.liveQuestData then return QuestTogether.GetPartyFollowingText(self) end
		return self.previewFollowing
				and (string.format(L("Following: %s"), self.previewFollowing) .. (self.previewFollowStatus and ("\n" .. self.previewFollowStatus) or ""))
			or ""
	end
	function preview:StopPartyQuestFollow()
		if self.liveQuestData then return QuestTogether.StopPartyQuestFollow(self) end
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
		root:CreateButton(self:GetPartyQuestFollowTarget() == name and L("Stop following") or L("Follow quest focus"), function()
			if self:GetPartyQuestFollowTarget() == name then
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

-- Keep the live follow intent intact, but never run two native focus controllers.
function QuestTogether:IsPartyQuestCompareNavigationPreviewActive()
	local preview = rawget(self, "partyQuestComparePreview")
	return preview and preview.liveQuestData and preview.partyQuestCompareSession ~= nil
end
