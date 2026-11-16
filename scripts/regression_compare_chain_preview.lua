-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
-- All preview fixtures are private. Never replace a provider global in /qt test.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Entry(id, complete)
	return { questId = id, questTitle = "Actual quest " .. id, isPushable = true, isComplete = complete == true }
end
local function Snapshot(generation, status)
	local value = { kind = "questiedb", state = status, generation = generation, revision = 1,
		nodes = {}, edges = {}, adjacency = {}, relations = {}, keyByQuest = {}, components = {}, metadata = {} }
	if status ~= "ready" then value.reason = "index_loading"; return value end
	for _, id in ipairs({ 10, 20, 25, 30, 35, 40, 50 }) do
		local key = id == 50 and "related:50" or "related:10"
		value.nodes[id], value.keyByQuest[id] = { questID = id }, key
		value.components[key] = value.components[key] or {}; table.insert(value.components[key], id)
		value.metadata[id] = { title = "Provider quest " .. id, locations = {} }
	end
	for _, pair in ipairs({ { 10, 20 }, { 20, 30 }, { 30, 40 }, { 10, 25 }, { 25, 35 } }) do
		local from, to = pair[1], pair[2]
		local edge = { from = from, to = to, questID = to, relatedQuestID = from, signedID = from,
			kind = "prerequisite_all", field = "preQuestGroup", connects = true }
		value.edges[#value.edges + 1] = edge
		value.relations[to] = { edge }
		value.adjacency[from] = value.adjacency[from] or {}; table.insert(value.adjacency[from], edge)
		value.adjacency[to] = value.adjacency[to] or {}; table.insert(value.adjacency[to], edge)
	end
	value.metadata[20].locations = { { id = 1, name = "Provider giver", mapID = 12, x = 0.2, y = 0.3 } }
	return value
end
local function Fixture()
	local a = QT:CreateTestPartyQuestCompareFixture({ Entry(20), Entry(50, true) })
	a.db = { profile = { characterQuestHistory = { sentinel = true } } }
	a.nativePartyFocusOwner = { sentinel = true }
	a.partyNavigationState = { followTarget = "Actual friend", waypoint = { x = 0.8 } }
	a.questChainProviderState, a.questChainProviderSnapshot = { sentinel = true }, { sentinel = true }
	a.API.GetCharacterQuestHistoryStatus = function(id) return id == 10 and "completed" or "incomplete" end
	a.API.GetQuestChainUnitInfo = function() return { classFile = "MAGE", level = 60 } end
	a.API.GetActiveTrackedQuestID = function() return 20 end
	local function Reject() error("chain preview crossed a live mutation boundary") end
	for _, method in ipairs({ "AcquirePartyFocusController", "ReleasePartyFocusController", "SetOption",
		"SetPartyQuestCompletionInterest", "SharePartyDiffQuest", "RequestPartyQuestShare", "OpenPingWaypoint",
		"SendPartyQuestShareMessage", "SendPartyNavigation", "ShowQuestChainGiver" }) do a[method] = Reject end
	a.API.SetPartyNavigationQuest, a.API.PushQuestToParty = Reject, Reject
	a.API.SetUserWaypoint, a.API.SetSuperTrackedQuestID = Reject, Reject
	function a:ReadQuestCompareObjectives()
		return { { text = "Actual objective", kind = "item", current = 2, required = 5 } }
	end
	-- Model asynchronous index publication through the same public provider
	-- boundary. The real graph, requirement, row, and window code remains in use.
	function a:RevalidateQuestChainProvider(workOwner, onChange)
		assert(self ~= a, "preview must not revalidate the ordinary PQL provider")
		self:CancelQuestChainProvider()
		self.questChainProviderGeneration = (self.questChainProviderGeneration or 0) + 1
		local generation = self.questChainProviderGeneration
		self.questChainProviderSnapshot = Snapshot(generation, "loading")
		local state = { owner = workOwner, workOwner = { active = true }, active = true,
			kind = "questiedb", metadataQueue = {}, metadataQueued = {}, metadataRequests = {}, requested = {},
			questDataRequests = {}, nativeDataUpdated = {} }
		self.questChainProviderState = state
		self:ScheduleRuntimeWork("quest_chain_provider", "index", function()
			if self.questChainProviderState ~= state then return end
			self.questChainProviderSnapshot = Snapshot(generation, "ready")
			onChange()
		end, { owner = state.workOwner })
		return self:GetQuestChainProviderCapability()
	end
	function a:FlushPreview()
		for _ = 1, 30 do
			local pending = self.delayed; self.delayed = {}
			if #pending == 0 then return end
			for _, work in ipairs(pending) do work.callback() end
		end
		error("chain preview work failed to settle")
	end
	return a
end
local function Rows(preview)
	return preview:BuildPartyQuestCompareDisplayRows(preview:BuildPartyQuestDiffRows())
end
local function Step(rows, id)
	for _, row in ipairs(rows) do if row.kind == "chainStep" and row.questId == id then return row end end
end

QT:RegisterTest("chain preview prepares native levels and colors before cache-only painting", function()
	local a, reads = Fixture(), 0
	a.API.GetQuestDifficultyLevel = function(id) reads = reads + 1; return id == 20 and 18 or nil end
	a.API.GetQuestDifficultyColor = function(level) Equal(level, 18); return { r = 1, g = 0.5, b = 0 } end
	a.API.GetQuestGroupRecommended = function(id) return id == 20 end
	assert(a:OpenPartyQuestComparePreview("chains")); a:FlushPreview()
	local p = a.partyQuestComparePreview
	local rows = Rows(p)
	Equal(Step(rows, 20).questLevel, 18); Equal(Step(rows, 20).questDifficultyColor.g, 0.5)
	Equal(Step(rows, 20).questGroupRecommended, true); Equal(Step(rows, 10).questGroupRecommended, false)
	Equal(Step(rows, 10).questLevel, nil)
	local before = reads
	p.API.GetQuestDifficultyLevel = function() error("paint read native quest level") end
	p.API.GetQuestDifficultyColor = function() error("paint read native color") end
	p.API.GetQuestGroupRecommended = function() error("paint read native group recommendation") end
	Rows(p); p:RenderPartyQuestCompare(); Rows(p)
	Equal(reads, before)
end)

QT:RegisterTest("chain preview augments copied real quests with earlier ready later branch and history evidence", function()
	local a = Fixture()
	assert(a:HandleSlashCommand("pqlpreview chains"))
	local p = a.partyQuestComparePreview
	Equal(p:GetQuestChainProviderCapability().state, "loading")
	local session, own = p.partyQuestCompareSession, p.partyQuestCompareSession.members[1]
	Equal(#session.members, 5); Equal(own.entries[20].questTitle, "Actual quest 20")
	assert(own.entries[20] ~= a.entries[1]); Equal(own.entries[50].isComplete, true)
	Equal(p.partyQuestCompareWindow.title.text, "Party Quest Log — Chain Preview")
	a:FlushPreview()
	local rows = Rows(p)
	Equal(session.chains.rootQuestID, 20)
	Equal(own.entries[10], nil); Equal(own.entries[25], nil); Equal(own.entries[30], nil)
	Equal(own.questHistory[10].status, "completed")
	Equal(p:GetPartyQuestFocusID(session.playerName), 20)
	Equal(Step(rows, 10).cells[1], "Completed")
	Equal(Step(rows, 10).cells[2], "Have") -- Earlier step.
	Equal(Step(rows, 20).cells[3], "Ready") -- Current step, ready to turn in.
	Equal(Step(rows, 30).cells[4], "Have") -- Later step.
	Equal(Step(rows, 20).cells[4], "Completed")
	Equal(Step(rows, 30).cells[3], "Absent") -- Explicit simulated incompletion.
	Equal(Step(rows, 25).cells[5], "Have") -- A real alternate branch.
	Equal(Step(rows, 20).cells[5], "Unknown") -- Incomplete simulated snapshot.
	for index = 2, 5 do assert(session.members[index].name:find("Simulated", 1, true)) end
	assert(p.partyQuestCompareWindow.summary.text:find("All actions are simulated", 1, true))
	-- Rendering consumes the already prepared snapshot, never provider/database reads.
	local graph = p.GetQuestChainGraph
	local history = p.API.GetCharacterQuestHistoryStatus
	p.GetQuestChainGraph = function() error("render read the quest provider") end
	p.API.GetCharacterQuestHistoryStatus = function() error("render read native completion history") end
	Rows(p); p:RenderPartyQuestCompare(); Rows(p)
	p.GetQuestChainGraph = graph
	p.API.GetCharacterQuestHistoryStatus = history
	Equal(a.entries[1].questTitle, "Actual quest 20")
end)

QT:RegisterTest("chain preview quest tooltips retain their own IDs and spoiler-safe titles", function()
	local a = Fixture()
	function a:ShowSettingsTooltip(_, title, text) self.tooltip = { title, text } end
	function a:HideSettingsTooltip() self.tooltip = nil end
	assert(a:OpenPartyQuestComparePreview("chains")); a:FlushPreview()
	local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
	local function Find(rowID)
		p:ScrollPartyQuestCompareToRow(frame, rowID)
		for _, row in ipairs(frame.rows) do if row.data and row.data.rowId == rowID then return row end end
		error("preview quest row is not visible")
	end
	local root = Find("quest:20")
	root:RunScript("OnEnter")
	Equal(a.tooltip[1], "[?] Actual quest 20")
	assert(a.tooltip[2]:find("Quest ID: 20|r", 1, true))
	root.chain:RunScript("OnEnter")
	assert(a.tooltip[2]:find("Quest ID: 20|r", 1, true))
	local future = assert(Step(Rows(p), 40))
	local row = Find(future.rowId)
	row:RunScript("OnEnter")
	Equal(a.tooltip[1], "[?] Future quest")
	assert(a.tooltip[2]:find("Quest ID: 40|r", 1, true))
	Equal(#a.wire, 0); Equal(a.pushes, 0)
end)

QT:RegisterTest("chain preview focus follow giver waypoint and sharing cannot mutate live state", function()
	local a = Fixture()
	local liveSession = { sentinel = true }
	a.partyQuestCompareSession = liveSession
	local liveProvider, liveSnapshot = a.questChainProviderState, a.questChainProviderSnapshot
	local liveFocus, liveNavigation, profile = a.nativePartyFocusOwner, a.partyNavigationState, a.db.profile
	assert(a:HandleSlashCommand("preview compare chains")); a:FlushPreview()
	local p, session = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareSession
	assert(not a:IsPartyQuestCompareNavigationPreviewActive())
	assert(p:FollowPartyQuestFocus(session.members[3].name))
	assert(p:RequestPartyQuestFocus(session.playerName, 20)); assert(p:StopPartyQuestFollow())
	assert(p:OpenPingWaypoint(12, 20, 30)); assert(p:ShowQuestChainGiver({}, function() return true end))
	assert(p:OpenPartyQuestJournal(20))
	local row = Step(Rows(p), 20)
	for _, action in ipairs(p:GetPartyQuestChainActions(row)) do if not action.disabled then action.action() end end
	for _, candidate in ipairs(p:BuildPartyQuestDiffRows()) do
		if candidate.action == "share" then p:SharePartyDiffQuest(candidate.questId)
		elseif candidate.action == "request" then p:RequestPartyQuestShare(candidate.questId, candidate.owner) end
	end
	p:SetOption("compareGroupByChain", true); p:QueuePartyQuestCompareRender(); a:FlushPreview()
	Equal(a.partyQuestCompareSession, liveSession); Equal(a.questChainProviderState, liveProvider)
	Equal(a.questChainProviderSnapshot, liveSnapshot); Equal(a.nativePartyFocusOwner, liveFocus)
	Equal(a.partyNavigationState, liveNavigation); Equal(a.db.profile, profile)
	Equal(profile.characterQuestHistory.sentinel, true); Equal(a.options.compareGroupByChain, nil)
	Equal(#a.wire, 0); Equal(a.pushes, 0)
	a:ClosePartyQuestComparePreview(); a:FlushPreview()
	Equal(a.nativePartyFocusOwner, liveFocus); Equal(a.partyNavigationState, liveNavigation)
end)

QT:RegisterTest("chain preview refresh rebuilds actual log and retires pending provider and action callbacks", function()
	local a = Fixture()
	assert(a:OpenPartyQuestComparePreview("chains"))
	local p, old = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareSession
	a:FlushPreview()
	local follow
	p:PopulatePartyFocusMenu({ CreateTitle = function() end, CreateButton = function(_, _, callback) follow = callback end }, old.members[3].name)
	assert(follow)
	p:QueuePartyQuestCompareRender()
	local pending = a.delayed; a.delayed = {}
	a.entries = { Entry(30, true) }
	p:RefreshPartyQuestCompare()
	local replacement = p.partyQuestCompareSession
	Equal(follow(), false); Equal(p.previewFollowing, nil)
	for _, work in ipairs(pending) do work.callback() end
	assert(old.chains.retired); assert(p.partyQuestCompareSession == replacement)
	a:FlushPreview()
	Equal(replacement.members[1].entries[20], nil); Equal(replacement.members[1].entries[30].isComplete, true)
	local actions = p:GetPartyQuestChainActions(Step(Rows(p), 30))
	p:TogglePartyQuestChain(30, "quest:30"); a:FlushPreview()
	Equal(replacement.chains.rootQuestID, nil)
	p:TogglePartyQuestChain(30, "quest:30"); a:FlushPreview()
	Equal(replacement.chains.rootQuestID, 30)
	a:ClosePartyQuestComparePreview()
	for _, action in ipairs(actions) do Equal(action.action(), false) end
	a:FlushPreview()
	Equal(p.partyQuestCompareSession, nil); Equal(p.questChainProviderState, nil)
	Equal(next(p.chainPreviewJobs), nil)
	assert(a:OpenPartyQuestComparePreview("chains")); a:FlushPreview()
	Equal(a.partyQuestComparePreview, p)
	assert(p.partyQuestCompareSession ~= replacement)
end)

QT:RegisterTest("chain preview handles an empty real log and close during provider indexing", function()
	local a = Fixture(); a.entries = {}
	assert(a:OpenPartyQuestComparePreview("chains"))
	local p = a.partyQuestComparePreview
	a:FlushPreview()
	Equal(#p:BuildPartyQuestDiffRows(), 0)
	assert(p.partyQuestCompareWindow.summary.text:find("Your quest log is empty", 1, true))
	a.entries = { Entry(20) }; p:RefreshPartyQuestCompare()
	local state = p.questChainProviderState
	a:ClosePartyQuestComparePreview(); a:FlushPreview()
	Equal(state.active, false); Equal(state.workOwner.active, false)
	Equal(p.partyQuestCompareSession, nil); Equal(p.questChainProviderState, nil)
	Equal(#a.wire, 0)
end)

QT:RegisterTest("chain preview resumes suspended indexing and history work after restrictions clear", function()
	local a = Fixture()
	assert(a:OpenPartyQuestComparePreview("chains"))
	local p = a.partyQuestComparePreview
	a.blocked = true
	local pending = a.delayed; a.delayed = {}
	for _, work in ipairs(pending) do work.callback() end
	Equal(p:GetQuestChainProviderCapability().state, "loading")
	assert(#a.delayed > 0)
	a.blocked = false; a:FlushPreview()
	Equal(p:GetQuestChainProviderCapability().state, "ready")
	assert(Step(Rows(p), 30))
	Equal(p.partyQuestCompareSession.members[1].questHistory[10].status, "completed")
	Equal(p.partyQuestCompareSession.chains.pending, nil)
end)

QT:RegisterTest("chain preview preserves the last sample when local log reads are unavailable", function()
	local a = Fixture()
	assert(a:OpenPartyQuestComparePreview("chains")); a:FlushPreview()
	local p, session = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareSession
	local read = a.BuildQuestCompareEntries
	function a:BuildQuestCompareEntries() return nil, "limit" end
	Equal(p:RefreshPartyQuestCompare(), false); a:FlushPreview()
	Equal(p.partyQuestCompareSession, session); assert(session.members[1].entries[20])
	assert(p.partyQuestCompareWindow.summary.text:find("Snapshot unavailable", 1, true))
	assert(not p.partyQuestCompareWindow.summary.text:find("Your quest log is empty", 1, true))
	a:ClosePartyQuestComparePreview()
	assert(a:OpenPartyQuestComparePreview("chains")); a:FlushPreview()
	Equal(p.partyQuestCompareSession.members[1].state, "unavailable")
	assert(p.partyQuestCompareWindow.summary.text:find("Snapshot unavailable", 1, true))
	assert(not p.partyQuestCompareWindow.summary.text:find("Your quest log is empty", 1, true))
	a.BuildQuestCompareEntries = read
	assert(p:RefreshPartyQuestCompare()); a:FlushPreview()
	Equal(p.partyQuestCompareSession.members[1].state, "ready")
	assert(p.partyQuestCompareSession.members[1].entries[20])
end)

QT:RegisterTest("chain preview waits for native provider membership before augmenting real quests", function()
	local a = Fixture()
	a.RevalidateQuestChainProvider = QT.RevalidateQuestChainProvider
	a.API.GetQuestChainClient = function() return "retail" end
	a.API.GetBestMapForUnit = function() return 12 end
	a.API.CanReadNativeQuestChains = function() return true end
	a.API.GetQuestLineInfo = function(id)
		if id < 50 then return { questLineID = 100, questLineName = "Actual quest line" } end
	end
	a.API.GetQuestLineQuests = function() return { 10, 20, 30, 40 } end
	a.API.GetQuestChainQuestTitle = function(id) return "Actual native title " .. id end
	a.API.RequestQuestLinesForMap = function() end
	assert(a:OpenPartyQuestComparePreview("chains")); a:FlushPreview()
	local p = a.partyQuestComparePreview
	Equal(p:GetQuestChainProviderCapability().kind, "retail")
	local rows = Rows(p)
	Equal(Step(rows, 10).cells[2], "Have"); Equal(Step(rows, 20).cells[3], "Ready")
	Equal(Step(rows, 30).cells[4], "Have")
	assert(p.partyQuestCompareSession.chains.graphs[20].membershipOnly)
	Equal(p.partyQuestCompareSession.members[1].entries[10], nil)
	Equal(p.partyQuestCompareSession.members[1].entries[30], nil)
	Equal(a.questChainProviderSnapshot.sentinel, true)
end)

QT:RegisterTest("chain preview provider publication preserves explicit close and selected chain", function()
	local a = Fixture()
	assert(a:OpenPartyQuestComparePreview("chains"))
	local p = a.partyQuestComparePreview
	assert(p:TogglePartyQuestChain(20, "quest:20"))
	Equal(p.partyQuestCompareSession.chains.rootQuestID, nil)
	a:FlushPreview()
	Equal(p.partyQuestCompareSession.chains.rootQuestID, nil)
	p:RefreshPartyQuestCompare()
	assert(p:TogglePartyQuestChain(50, "quest:50"))
	a:FlushPreview()
	Equal(p.partyQuestCompareSession.chains.rootQuestID, 50)
end)

_G.QuestTogether:RecordTestModule("scripts/regression_compare_chain_preview.lua")
