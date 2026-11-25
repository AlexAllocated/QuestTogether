-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Entry(id) return { questId = id, questTitle = "Active " .. id, isPushable = true } end
local function Graph(ids, key)
	local graph = { key = key or "related:1", nodes = {}, order = ids, edges = {}, depths = {},
		providerKind = "questiedb", frontier = { earlier = {}, later = {} }, total = #ids, generation = 1 }
	for index, id in ipairs(ids) do graph.nodes[id], graph.depths[id] = { questID = id }, index - 1 end
	for index = 2, #ids do
		graph.edges[#graph.edges + 1] = { from = ids[index - 1], to = ids[index], kind = "prerequisite_all",
			questID = ids[index], relatedQuestID = ids[index - 1] }
	end
	return graph
end
local function Fixture()
	local a = QT:CreateTestPartyQuestCompareFixture({ Entry(2), Entry(4) })
	a.db = { profile = {} }
	a.jobs, a.graphs, a.metadata, a.metadataRequests, a.providerCallbacks = {}, {}, {}, {}, {}
	a.API.GetServerTime = function() return 1800000000 + math.floor(a.now) end
	a.API.GetCharacterQuestHistoryStatus = function() return "incomplete" end
	a.API.GetPlayerMapID = function() return 12 end
	a.options.compareHideFutureQuestNames = true
	a.options.compareGroupByChain = false
	local own = { name = a.name, isLocal = true, state = "ready", entries = { [2] = Entry(2), [4] = Entry(4) }, questHistory = {} }
	local friend = { name = "Friend-Realm", state = "ready", entries = { [2] = Entry(2) }, questHistory = {}, supportsQuestHistory = true }
	own.sampledAt, friend.sampledAt = a.now, a.now
	local session = { playerName = a.name, members = { own, friend }, byName = { [a.name] = own, [friend.name] = friend },
		mode = "party", expandedQuestIds = {}, search = "", objectiveOwner = {} }
	a.partyQuestCompareSession = session
	a.partyQuestCompareWindow = { IsVisible = function() return true end }
	function a:CanMutateOwnedUI() return true end
	function a:RenderPartyQuestCompare() self.paints = (self.paints or 0) + 1 end
	function a:ScheduleDeferredWork(_, key, callback) self.jobs[key] = callback end
	function a:QueuePartyQuestCompareRender() self.renders = self.renders + 1; self:QueuePartyQuestChainRefresh() end
	function a:GetLocalizedQuestTitle(id) return self.metadata[id] and self.metadata[id].title end
	function a:RevalidateQuestChainProvider(_, callback)
		self.providerCallbacks[#self.providerCallbacks + 1] = callback
		self.questChainProviderSnapshot = { generation = (self.questChainProviderSnapshot and self.questChainProviderSnapshot.generation or 0) + 1 }
	end
	function a:CancelQuestChainProvider() self.providerCancels = (self.providerCancels or 0) + 1 end
	function a:GetQuestChainProviderCapability()
		return { state = self.providerState or "ready", kind = self.providerKind or "questiedb", reason = self.providerReason,
			generation = self.questChainProviderSnapshot.generation }
	end
	function a:GetQuestChainGraph(id, options)
		self.graphReads = (self.graphReads or 0) + 1
		self.lastGraphOptions = options
		return self.graphs[id] or Graph({ id }, "single:" .. id)
	end
	function a:GetQuestChainQuestInfo(id) return self.metadata[id] end
	function a:SetQuestChainMetadataInterest(ids)
		self.metadataInterested = {}
		for _, id in ipairs(ids) do self.metadataInterested[id] = true end
	end
	function a:RequestQuestChainMetadata(ids, _, callback)
		self.metadataRequests[#self.metadataRequests + 1] = { ids = ids, callback = callback }
	end
	function a:GetQuestChainStarterLocations(id)
		return self.metadata[id] and self.metadata[id].locations or {}, self.metadata[id] and self.metadata[id].locationReason
	end
	function a:EvaluateQuestChainRequirements(id, evidence)
		self.lastEvidence = evidence
		self.evidenceByQuest = self.evidenceByQuest or {}
		self.evidenceByQuest[id] = evidence
		local prior = evidence[id - 1]
		local status = prior and prior.completed == false and "blocked" or prior and prior.completed == true and "met" or "unknown"
		return { state = status, requirements = {}, groups = {}, blockers = prior and prior.completed == false
			and { { questID = id - 1, kind = "prerequisite_all" } } or {} }
	end
	function a:Flush()
		for _ = 1, 12 do
			local pending = self.jobs; self.jobs = {}
			if not next(pending) then return end
			for _, callback in pairs(pending) do callback() end
		end
		error("chain work did not quiesce")
	end
	a:AttachPartyQuestChains(session)
	a:Flush()
	return a, session, own, friend
end
local function Rows(a)
	return a:BuildPartyQuestCompareDisplayRows(a:BuildPartyQuestDiffRows())
end
local function Find(rows, kind, id)
	for _, row in ipairs(rows) do if row.kind == kind and (not id or row.questId == id) then return row end end
end
local function Open(a, session, graph)
	a.graphs[2], a.graphs[4] = graph, graph
	for id in pairs(graph.nodes) do a.metadata[id] = a.metadata[id] or { title = "Secret " .. id } end
	assert(a:OpenPartyQuestChain(2, "quest:2"))
	a:Flush()
	return Rows(a)
end
local function UseProviderSnapshot(a, kind)
	local snapshot = {
		kind = kind, state = "ready", generation = a.questChainProviderSnapshot.generation, revision = 1,
		nodes = { [2] = { questID = 2 }, [4] = { questID = 4 } },
		metadata = { [2] = { loading = false }, [4] = { loading = false } },
		keyByQuest = {}, components = {}, relations = {}, adjacency = {}, membership = {}, lines = {},
	}
	a.providerKind, a.questChainProviderSnapshot = kind, snapshot
	a.GetQuestChainGraph = QT.GetQuestChainGraph
	return snapshot
end

local function MaximumLevelFixture()
	local a, session, own, friend = Fixture()
	local snapshot = a.questChainProviderSnapshot
	snapshot.kind, snapshot.state, snapshot.revision = "questiedb", "ready", 1
	snapshot.nodes, snapshot.metadata, snapshot.relations = {}, {}, {}
	for _, id in ipairs({ 1, 2, 3, 4 }) do
		snapshot.nodes[id], snapshot.metadata[id] = { questID = id }, { requiredMaxLevel = 10 }
	end
	a.EvaluateQuestChainRequirements = QT.EvaluateQuestChainRequirements
	a.API.GetQuestChainUnitInfo = function() return { level = 20 } end
	a.partyMembers[friend.name] = { unit = "party1" }
	function a:GetUnitFullName(unit) return unit == "party1" and friend.name or self.name end
	friend.entries = {}
	friend.questHistory[2] = { status = "incomplete", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	return a, session, own, friend
end

QT:RegisterTest("chain permanent eligibility marks ordinary and contextual absence without changing history or counts", function()
	local a, session, own, friend = MaximumLevelFixture()
	local row = assert(Find(Rows(a), nil, 2))
	Equal(row.cells[1], "Have"); Equal(row.cells[2], "Unavailable"); Equal(row.missing, 1)
	Equal(row.action, "share"); Equal(row.shareReadiness.disabled, true)
	Equal(row.shareReadiness.byName[friend.name].state, "blocked")
	Equal(a:GetPartyQuestAbsenceState(friend, 2), "Missing")
	local rows = Open(a, session, Graph({ 1, 2, 3, 4 }))
	Equal(Find(rows, nil, 2).cells[2], "Unavailable")
	local future = assert(Find(rows, "chainStep", 3))
	Equal(future.cells[1], "Unavailable"); Equal(future.cells[2], "Unavailable")
	Equal(future.title, "Quest name hidden"); Equal(future.spoilerHidden, true)
	Equal(session.totalQuests, 2); Equal(#session.unfilteredQuests, 2)
	Equal(friend.entries[2], nil); Equal(friend.questHistory[2].status, "incomplete")
	Equal(own.entries[3], nil); Equal(friend.entries[3], nil)
	assert(not own.questHistory[3] or own.questHistory[3].status ~= "unavailable")
	assert(not friend.questHistory[3] or friend.questHistory[3].status ~= "unavailable")
end)

QT:RegisterTest("chain permanent eligibility preserves active completed and unknown status precedence", function()
	local a, session, _, friend = MaximumLevelFixture()
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	for _, status in ipairs({ "Have", "Ready", "Completed", "Loading", "Unknown" }) do
		Equal(a:GetPartyQuestEligibilityStatus(friend, 2, status), status)
	end
	Equal(a:GetPartyQuestEligibilityStatus(friend, 2, "Missing"), "Unavailable")
	Equal(a:GetPartyQuestEligibilityStatus(friend, 2, "Absent"), "Unavailable")
	for _, case in ipairs({
		{ entry = Entry(2), expected = "Have" },
		{ entry = { questId = 2, questTitle = "Ready quest", isComplete = true }, expected = "Ready" },
		{ history = "completed", expected = "Completed" },
		{ history = "active", expected = "Unknown" },
		{ state = "loading", expected = "Loading" }, { state = "error", expected = "Unknown" },
		{ history = "incomplete", expected = "Unavailable" }, { expected = "Unavailable" },
	}) do
		friend.entries = case.entry and { [2] = case.entry } or {}
		friend.state = case.state or "ready"
		friend.questHistory[2] = case.history and { status = case.history, sampledAt = a.now } or nil
		a:RefreshPartyQuestShareRequirements(friend, 2)
		local row = assert(Find(Rows(a), nil, 2))
		Equal(row.cells[2], case.expected)
		Equal(a:GetPartyQuestChainStatus(friend, 2), case.expected)
		if case.history == "active" then Equal(row.memberPrerequisiteText[2], "") end
	end
end)

QT:RegisterTest("chain permanent eligibility expires with its evidence certificate", function()
	for _, change in ipairs({ "ttl", "revision", "snapshot", "entries", "history", "retire", "session" }) do
		local a, session, _, friend = MaximumLevelFixture()
		Open(a, session, Graph({ 1, 2, 3, 4 }))
		Equal(a:GetPartyQuestEligibilityStatus(friend, 2, "Missing"), "Unavailable")
		if change == "ttl" then a.now = a.now + 60
		elseif change == "revision" then a.questChainProviderSnapshot.revision = 2
		elseif change == "snapshot" then a.questChainProviderSnapshot = { generation = 1, revision = 1 }
		elseif change == "entries" then friend.entries = {}
		elseif change == "history" then friend.historyGeneration = (friend.historyGeneration or 0) + 1
		elseif change == "retire" then a:RetirePartyQuestChains()
		else
			a.partyQuestCompareSession = { playerName = session.playerName, members = session.members,
				byName = session.byName, mode = "party", expandedQuestIds = {}, search = "", objectiveOwner = {} }
			a:AttachPartyQuestChains(a.partyQuestCompareSession, session)
		end
		Equal(a:GetPartyQuestCachedShareRequirements(friend, 2), nil)
		Equal(a:GetPartyQuestEligibilityStatus(friend, 2, "Missing"), "Missing")
		Equal(a:GetPartyQuestEligibilityStatus(friend, 2, "Absent"), "Absent")
		local row = assert(Find(Rows(a), nil, 2))
		assert(row.cells[2] ~= "Unavailable")
		local tooltip = row.memberPrerequisiteText and row.memberPrerequisiteText[2] or ""
		assert(not tooltip:find("No longer obtainable", 1, true))
		assert(not tooltip:find("Level exceeds the maximum", 1, true))
	end
end)

QT:RegisterTest("chain unavailable cells remain known missing for filters and preserve partywide share readiness", function()
	local a, session, _, friend = MaximumLevelFixture()
	local rows = a:BuildPartyQuestDiffRows()
	Equal(#rows, 2); Equal(rows[1].missing, 1); Equal(rows[2].missing, 1)
	a.options.compareQuestOwnership = "someoneMissing"
	Equal(#a:BuildPartyQuestDiffRows(), 2)
	a.options.compareQuestProgress = "unknown"
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	a.options.compareQuestProgress, a.options.compareQuestOwnership = "all", "shared"
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	a.options.compareQuestOwnership, a.options.compareQuestAction = "all", "share"
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	local blocked = a:GetPartyQuestMemberShareReadiness(friend, 2)
	Equal(blocked.state, "blocked"); Equal(blocked.canAttempt, false)
	Equal(blocked.requirements.state, "blocked"); Equal(blocked.requirements.permanentlyBlocked, true)
	Equal(a:GetPartyQuestShareReadiness(2, "share").disabled, true)
	a.partyMembers["Other-Realm"] = {}
	a.partyMemberOrder = { friend.name, "Other-Realm" }
	local readiness = a:GetPartyQuestShareReadiness(2, "share")
	Equal(readiness.disabled, false); Equal(readiness.counts.blocked, 1); Equal(readiness.counts.unknown, 1)
	Equal(readiness.byName["Other-Realm"].canAttempt, true)
	Equal(#a:BuildPartyQuestDiffRows(), 2); Equal(session.totalQuests, 2)
end)

QT:RegisterTest("chain controls hide singleton Forever and Retail graphs including one-quest lines", function()
	for _, kind in ipairs({ "questiedb", "retail" }) do
		local a, session = Fixture()
		local snapshot = UseProviderSnapshot(a, kind)
		a.options.compareGroupByChain = true
		if kind == "retail" then
			snapshot.membership[2], snapshot.lines[7] = 7, { order = { 2 }, title = "Single quest line" }
		end
		a:QueuePartyQuestCompareRender(); a:Flush()
		local rows = Rows(a)
		Equal(Find(rows, nil, 2).chainAvailable, false); Equal(Find(rows, nil, 4).chainAvailable, false)
		Equal(Find(rows, nil, 2).chainLoading, false); Equal(Find(rows, nil, 4).chainLoading, false)
		Equal(Find(rows, "chainGroup"), nil); Equal(Find(rows, "chainStep"), nil)
		Equal(session.totalQuests, 2)
		if kind == "retail" then Equal(session.chains.graphs[2].lineID, 7)
		else
			-- A malformed self-loop is partial data, not a second quest.
			local edge = { from = 2, to = 2, kind = "prerequisite_all", connects = true, questID = 2, relatedQuestID = 2 }
			snapshot.adjacency[2], snapshot.relations[2] = { edge }, { edge }
			a:QueuePartyQuestCompareRender(); a:Flush()
			assert(session.chains.graphs[2].partial and session.chains.graphs[2].cycle)
			Equal(Find(Rows(a), nil, 2).chainAvailable, false); Equal(Find(Rows(a), "chainGroup"), nil)
			Equal(Find(Rows(a), nil, 2).chainLoading, false)
		end
	end
end)

QT:RegisterTest("chain controls appear after async discovery and keep retired expanded roots closable", function()
	for _, kind in ipairs({ "questiedb", "retail" }) do
		local a, session = Fixture()
		local snapshot = UseProviderSnapshot(a, kind)
		a.options.compareGroupByChain = true
		if kind == "questiedb" then snapshot.state, a.providerState = "loading", "loading"
		else snapshot.metadata[2].loading = true end
		a:QueuePartyQuestCompareRender(); a:Flush()
		Equal(Find(Rows(a), nil, 2).chainAvailable, false); Equal(Find(Rows(a), "chainGroup"), nil)
		Equal(Find(Rows(a), nil, 2).chainLoading, true)
		assert(session.chains.graphs[2].loading)
		local callback = a.providerCallbacks[1]
		if kind == "retail" then
			assert(a.metadataInterested[2] and a.metadataInterested[4])
			callback = a.metadataRequests[#a.metadataRequests].callback
			snapshot.membership[1], snapshot.membership[2] = 7, 7
			snapshot.lines[7] = { order = { 1, 2 }, partial = true, loading = true }
		else
			local edge = { from = 1, to = 2, kind = "prerequisite_all", connects = true, questID = 2, relatedQuestID = 1 }
			snapshot.adjacency[1], snapshot.adjacency[2], snapshot.relations[2] = { edge }, { edge }, { edge }
			snapshot.keyByQuest[2], snapshot.components["related:1"] = "related:1", { 1, 2 }
		end
		snapshot.nodes[1], snapshot.revision = { questID = 1 }, snapshot.revision + 1
		callback(); a:Flush()
		local rows = Rows(a)
		assert(Find(rows, nil, 2).chainAvailable and Find(rows, "chainGroup"))
		Equal(Find(rows, nil, 2).chainLoading, false)
		Equal(Find(rows, nil, 4).chainAvailable, false)
		assert(session.chains.graphs[2].loading and session.chains.graphs[2].partial)
		assert(a:TogglePartyQuestChain(2, "quest:2")); a:Flush()
		assert(Find(Rows(a), "chainStep", 1)); assert(Find(Rows(a), "chainNotice"))
		-- A later singleton snapshot removes the extra context but keeps Close chain.
		UseProviderSnapshot(a, kind); a.providerState = "ready"
		a:QueuePartyQuestCompareRender(); a:Flush()
		rows = Rows(a)
		assert(Find(rows, nil, 2).chainAvailable and Find(rows, nil, 2).chainExpanded)
		Equal(Find(rows, nil, 2).chainLoading, false)
		Equal(Find(rows, "chainGroup"), nil); Equal(Find(rows, "chainStep", 1), nil)
		assert(a:TogglePartyQuestChain(2, "quest:2")); a:Flush()
		Equal(Find(Rows(a), nil, 2).chainAvailable, false)
		Equal(Find(Rows(a), nil, 2).chainLoading, false)
	end
end)

QT:RegisterTest("chain loading indicators retire after failed or unavailable discovery", function()
	local a, session = Fixture()
	a:AttachPartyQuestChains(session)
	Equal(Find(Rows(a), nil, 2).chainLoading, true)
	a:Flush()
	Equal(Find(Rows(a), nil, 2).chainLoading, false)
	for _, providerState in ipairs({ "loading", "failed", "unavailable" }) do
		a.providerState = providerState
		a:QueuePartyQuestCompareRender(); a:Flush()
		Equal(Find(Rows(a), nil, 2).chainLoading, providerState == "loading")
		Equal(Find(Rows(a), nil, 2).chainAvailable, false)
	end
	a.providerState = "loading"
	a:QueuePartyQuestCompareRender(); a:Flush()
	local loadingRow = Find(Rows(a), nil, 2)
	Equal(loadingRow.chainLoading, true)
	a:CancelPartyQuestChains(session)
	Equal(Find(Rows(a), nil, 2).chainLoading, false)
	session.chains = nil
	a:DecoratePartyQuestChainRows({ loadingRow }, function(rows, row) rows[#rows + 1] = row end)
	Equal(loadingRow.chainLoading, false)
end)

local function BranchGraph(ids, edges)
	local graph = Graph(ids)
	graph.edges = {}
	for _, edge in ipairs(edges) do
		graph.edges[#graph.edges + 1] = {
			from = edge[1], to = edge[2], kind = edge[3] or "prerequisite_all", negative = edge.negative,
			questID = edge[2], relatedQuestID = edge[1],
		}
	end
	return graph
end
local function CheckBranchDepths(rows, graph, expected)
	local step = 0
	for _, row in ipairs(rows) do
		if row.kind == "chainStep" or row.chainAnchor then
			step = step + 1
			Equal(row.questId, graph.order[step])
			Equal(row.depth, expected[row.questId] or 0)
		end
	end
	Equal(step, #graph.order)
end

QT:RegisterTest("chain expansion replaces its origin step with the ordinary quest and objective rows", function()
	for _, grouped in ipairs({ false, true }) do
		local a, session, own, friend = Fixture()
		a.options.compareGroupByChain = grouped
		own.entries[8], friend.entries[8] = Entry(8), Entry(8)
		own.objectiveDetails = { [2] = { questId = 2, state = "ready", objectives = {
			{ text = "Collect things", kind = "item", current = 1, required = 3, finished = false },
		} } }
		session.expandedQuestIds[2] = true
		local objectiveID = assert(Find(Rows(a), "objective", 2)).rowId
		local graph = BranchGraph({ 1, 2, 3, 4 }, { { 1, 2 }, { 1, 3 }, { 2, 4 }, { 3, 4 } })
		Open(a, session, graph)
		local roots = a:BuildPartyQuestDiffRows()
		local origin = assert(Find(roots, nil, 2))
		local title, cells, action, owner = origin.title, origin.cells, origin.action, origin.owner
		local rows = a:BuildPartyQuestCompareDisplayRows(roots)
		Equal(Find(rows, nil, 2), origin); Equal(origin.rowId, "quest:2")
		Equal(origin.title, title); Equal(origin.cells, cells); Equal(origin.action, action); Equal(origin.owner, owner)
		assert(origin.chainAnchor and origin.chainExpanded); Equal(origin.depth, 1)
		Equal(Find(rows, "chainStep", 2), nil)
		Equal(session.totalQuests, 3); Equal(#session.unfilteredQuests, 3)
		local order, originIndex, objectiveIndex, laterIndex, ended = {}, nil, nil, nil, false
		local instance = origin.chainInstanceId
		for index, row in ipairs(rows) do
			if row.kind == "chainStep" or row.chainAnchor then order[#order + 1] = row.questId end
			if row == origin then originIndex = index end
			if row.kind == "objective" and row.questId == 2 then objectiveIndex = index end
			if row.kind == "chainStep" and row.questId == 3 then laterIndex = index end
			if row.chainInstanceId then
				assert(not ended, "expanded section must remain contiguous")
				Equal(row.chainInstanceId, instance)
			elseif originIndex then ended = true end
		end
		Equal(table.concat(order, ","), "1,2,3,4")
		assert(originIndex < objectiveIndex and objectiveIndex < laterIndex)
		for index = originIndex + 1, laterIndex - 1 do
			Equal(rows[index].parentRowId, "quest:2"); Equal(rows[index].chainInstanceId, instance)
		end
		Equal(Find(rows, "objective", 2).rowId, objectiveID)
		Equal(Find(rows, nil, 4).chainInstanceId, nil); Equal(Find(rows, nil, 8).chainInstanceId, nil)
		assert(a:SetPartyQuestChainSelection(Find(rows, "chainStep", 3)))
		Equal(session.chains.selectedQuestID, 3)
		assert(a:SetPartyQuestChainSelection(origin)); Equal(session.chains.selectedQuestID, 2)
		Equal(a:SetPartyQuestChainSelection(Find(rows, nil, 4)), false)
		local closed, back = a:ClosePartyQuestChain(); assert(closed); Equal(back, "quest:2")
		Equal(a:SetPartyQuestChainSelection(origin), false)
		rows = a:BuildPartyQuestCompareDisplayRows(roots)
		Equal(Find(rows, nil, 2), origin); Equal(origin.chainAnchor, nil); Equal(origin.depth, nil)
		Equal(origin.memberPrerequisiteText, nil); Equal(origin.relationshipText, nil)
		Equal(Find(rows, "objective", 2).rowId, objectiveID)
		for _, row in ipairs(rows) do Equal(row.chainInstanceId, nil) end
	end
end)

QT:RegisterTest("chain paging surrounds the retained origin and preserves its identity as context grows", function()
	local a, session = Fixture()
	local graph = Graph({ 1, 2, 3, 4 })
	graph.partial, graph.frontier.earlier, graph.frontier.later = true, { 10 }, { 5 }
	local rows = Open(a, session, graph)
	local instance, earlierID, laterID = Find(rows, nil, 2).chainInstanceId
	local function CheckPage(currentRows, expected)
		local order, first, last, earlier, later = {}, nil, nil, nil, nil
		for index, row in ipairs(currentRows) do
			if row.kind == "chainStep" or row.chainAnchor then
				order[#order + 1] = row.questId; first, last = first or index, index
				Equal(row.chainInstanceId, instance)
			elseif row.kind == "chainMore" then
				if row.direction == "earlier" then earlier, earlierID = index, row.rowId
				else later, laterID = index, row.rowId end
			end
		end
		Equal(table.concat(order, ","), expected); assert(earlier < first and later > last)
		Equal(Find(currentRows, nil, 2).rowId, "quest:2"); Equal(Find(currentRows, "chainStep", 2), nil)
	end
	CheckPage(rows, "1,2,3,4")
	local oldEarlier, oldLater = earlierID, laterID
	graph.order, graph.nodes[10] = { 10, 1, 2, 3, 4 }, { questID = 10 }
	assert(a:ExpandPartyQuestChain("earlier")); a:Flush()
	CheckPage(Rows(a), "10,1,2,3,4")
	graph.order, graph.nodes[5] = { 10, 1, 2, 3, 4, 5 }, { questID = 5 }
	assert(a:ExpandPartyQuestChain("later")); a:Flush()
	CheckPage(Rows(a), "10,1,2,3,4,5")
	Equal(earlierID, oldEarlier); Equal(laterID, oldLater)
	Equal(session.chains.earlier, 119); Equal(session.chains.later, 120)
	Equal(session.totalQuests, 2)
end)

QT:RegisterTest("chain missing origin snapshots retain the ordinary row without inventing its graph position", function()
	local a, session = Fixture()
	local graph = Graph({ 1, 3, 4 })
	graph.partial = true
	local rows = Open(a, session, graph)
	local function FirstSectionRow(currentRows)
		for index, row in ipairs(currentRows) do if row.chainInstanceId then return row, index end end
	end
	local origin = FirstSectionRow(rows)
	Equal(origin.rowId, "quest:2"); assert(origin.chainAnchor)
	Equal(Find(rows, "chainStep", 2), nil)
	local order = {}
	for _, row in ipairs(rows) do if row.kind == "chainStep" then order[#order + 1] = row.questId end end
	Equal(table.concat(order, ","), "1,3,4")
	-- A replacement session can paint before its deferred graph preparation.
	session.chains.graphs, session.chains.depths = {}, nil
	rows = Rows(a)
	local index
	origin, index = FirstSectionRow(rows)
	Equal(origin.rowId, "quest:2"); Equal(origin.depth, 0)
	Equal(rows[index + 1].kind, "chainNotice"); Equal(rows[index + 1].chainInstanceId, origin.chainInstanceId)
	assert(a:TogglePartyQuestChain(2, "quest:2")); Equal(session.chains.rootQuestID, nil)
end)

QT:RegisterTest("chain branch layout keeps straight paths flat despite duplicate and ancestor shortcuts", function()
	local a, session = Fixture()
	local graph = Graph({ 1, 2, 3, 4, 5 })
	CheckBranchDepths(Open(a, session, graph), graph, {})
	graph.edges[#graph.edges + 1] = { from = 1, to = 2, kind = "unlock" }
	graph.edges[#graph.edges + 1] = { from = 1, to = 4, kind = "prerequisite_all" }
	graph.edges[#graph.edges + 1] = { from = 1, to = 5, kind = "exclusive" }
	graph.edges[#graph.edges + 1] = { from = 1, to = 5, kind = "prerequisite_any", negative = true }
	a:QueuePartyQuestCompareRender(); a:Flush()
	CheckBranchDepths(Rows(a), graph, {})
	Equal(#graph.edges, 8); Equal(graph.depths[5], 4) -- Presentation does not rewrite graph facts.
	local reads = a.graphReads
	CheckBranchDepths(Rows(a), graph, {}); Equal(a.graphReads, reads)
end)

QT:RegisterTest("chain branch layout indents fork arms once and rejoins their common nesting", function()
	local a, session = Fixture()
	local graph = BranchGraph({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, {
		{ 1, 2 }, { 1, 3 }, { 2, 4 }, { 3, 5 }, { 4, 6 }, { 4, 7 },
		{ 6, 8 }, { 7, 8 }, { 8, 9 }, { 5, 9 }, { 9, 10 },
	})
	CheckBranchDepths(Open(a, session, graph), graph, {
		[2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 2, [7] = 2, [8] = 1,
	})
	Equal(graph.completeLinearPath, nil); Equal(graph.depths[10], 9)
	-- Separate prerequisite roots converging do not manufacture a branch level.
	graph = BranchGraph({ 1, 2, 3, 4 }, { { 1, 3 }, { 2, 3 }, { 3, 4 } })
	CheckBranchDepths(Open(a, session, graph), graph, {})
end)

QT:RegisterTest("chain branch layout uses only materialized positive relationships and stays flat on cycles", function()
	local a, session = Fixture()
	local graph = BranchGraph({ 2, 3, 4, 5 }, { { 1, 2 }, { 2, 3 }, { 2, 4 }, { 3, 5 }, { 4, 5 } })
	graph.partial, graph.frontier.earlier = true, { 1 }
	CheckBranchDepths(Open(a, session, graph), graph, { [3] = 1, [4] = 1 })
	assert(Find(Rows(a), "chainMore")); Equal(graph.partial, true)
	graph.edges[3].negative = true
	a:QueuePartyQuestCompareRender(); a:Flush()
	CheckBranchDepths(Rows(a), graph, {})
	for _, marked in ipairs({ false, true }) do
		graph = BranchGraph({ 2, 3, 4, 5 }, { { 2, 3 }, { 3, 2 }, { 2, 4 }, { 4, 5 } })
		graph.cycle, graph.partial = marked, true
		CheckBranchDepths(Open(a, session, graph), graph, {})
		Equal(graph.cycle, marked); Equal(graph.completeLinearPath, nil)
	end
end)

QT:RegisterTest("chain branch layout keeps native Retail line membership flat", function()
	local a = Fixture()
	local snapshot = UseProviderSnapshot(a, "retail")
	snapshot.membership[2], snapshot.membership[4] = 7, 7
	snapshot.lines[7] = { order = { 1, 2, 3, 4 }, title = "Native line" }
	snapshot.nodes[1], snapshot.nodes[3] = { questID = 1 }, { questID = 3 }
	assert(a:OpenPartyQuestChain(2, "quest:2")); a:Flush()
	local graph = a.partyQuestCompareSession.chains.graphs[2]
	assert(graph.membershipOnly); Equal(#graph.edges, 0)
	CheckBranchDepths(Rows(a), graph, {})
	Equal(graph.completeLinearPath, false)
end)

QT:RegisterTest("chain session preserves active counts and independent objectives with cache-only spoiler-safe rows", function()
	local a, session, own = Fixture()
	local graph = Graph({ 1, 2, 3, 4 })
	graph.edges = { graph.edges[1], graph.edges[2], { from = 2, to = 4, kind = "unlock", relatedQuestID = 4 } }
	Open(a, session, graph)
	own.questHistory[1] = { status = "incomplete", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	local rows = Rows(a)
	Equal(session.totalQuests, 2)
	Equal(#session.unfilteredQuests, 2)
	Equal(Find(rows, "chainStep", 1).title, "Secret 1") -- Required blocker context is intentional.
	Equal(Find(rows, "chainStep", 3).title, "Quest name hidden")
	Equal(Find(rows, "chainStep", 4).title, "Active 4")
	Equal(Find(rows, "chainStep", 1).cells[1], "Absent")
	Equal(Find(rows, nil, 2).memberPrerequisiteText[1], "")
	Equal(Find(rows, "chainClose"), nil)
	assert(Find(rows, nil, 2).chainExpanded)
	Equal(Find(rows, "chainMore"), nil)
	local ids = {}; for _, row in ipairs(rows) do assert(not ids[row.rowId]); ids[row.rowId] = true end
	local reads = a.graphReads
	local requests = #a.metadataRequests
	Rows(a); Rows(a)
	Equal(a.graphReads, reads); Equal(#a.metadataRequests, requests)
	session.expandedQuestIds[2] = true
	assert(a:ClosePartyQuestChain())
	Equal(session.expandedQuestIds[2], true)
	Equal(own.entries[1], nil); Equal(own.entries[3], nil)
end)

QT:RegisterTest("chain search and filters consider active roots without hidden future names or context counts", function()
	local a, session = Fixture()
	a.options.compareGroupByChain = true
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	session.search = "Secret 3"
	Equal(#Rows(a), 0)
	Equal(session.totalQuests, 2)
	session.search = "Active 2"
	local rows = Rows(a)
	local group = assert(Find(rows, "chainGroup"))
	Equal(group.hint, "1 quests hidden by filters")
	assert(Find(rows, "chainStep", 1))
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	a:TogglePartyQuestChainGroup(group.groupId)
	Equal(#Rows(a), 1)
	a:TogglePartyQuestChainGroup(group.groupId)
	assert(Find(Rows(a), nil, 2).chainAnchor)
end)

QT:RegisterTest("chain displayed earlier alternatives reveal titles without completion or eligibility inference", function()
	for _, grouped in ipairs({ false, true }) do
		local a, session, own = Fixture()
		a.options.compareGroupByChain = grouped
		local graph = Graph({ 10, 20, 2, 30, 4 })
		graph.edges = {} -- Alternative variants need not be evaluated prerequisites.
		a.metadata[10] = { title = "Orders (Level 10)", questLevel = 10 }
		a.metadata[20] = { title = "Orders (Level 20)", questLevel = 20 }
		a.metadata[30] = { title = "Unreached orders", questLevel = 5 }
		Open(a, session, graph)
		own.questHistory[10] = { status = "incomplete", sampledAt = a.now }
		local rows = Rows(a)
		for _, id in ipairs({ 10, 20 }) do
			local row = assert(Find(rows, "chainStep", id))
			Equal(row.title, a.metadata[id].title); Equal(row.spoilerHidden, false)
			Equal(own.entries[id], nil); assert(row.cells[1] ~= "Completed")
			Equal(row.requirements[1].state, "unknown")
			Equal(session.chains.revealBlockers[id], nil)
			Equal(row.action, nil)
		end
		Equal(own.questHistory[10].status, "incomplete")
		Equal(Find(rows, "chainStep", 30).title, "Quest name hidden")
		Equal(Find(rows, "chainStep", 30).spoilerHidden, true)
		Equal(Find(rows, "chainStep", 4).title, "Active 4")
		local reads, requests = a.graphReads, #a.metadataRequests
		session.search = "Active 4" -- The matching group still displays the opened origin's context.
		rows = Rows(a)
		Equal(Find(rows, "chainStep", 10).title, "Orders (Level 10)")
		Equal(Find(rows, "chainStep", 30).title, "Quest name hidden")
		Equal(a.graphReads, reads); Equal(#a.metadataRequests, requests)
	end
end)

QT:RegisterTest("chain earlier title context follows displayed order and requires an origin position", function()
	local a, session = Fixture()
	local graph = Graph({ 10, 2, 30, 4 })
	graph.edges = {}
	local rows = Open(a, session, graph)
	Equal(Find(rows, "chainStep", 10).title, "Secret 10")
	Equal(Find(rows, "chainStep", 30).title, "Quest name hidden")
	graph.order = { 30, 2, 10, 4 }
	a:QueuePartyQuestCompareRender(); a:Flush()
	rows = Rows(a)
	Equal(Find(rows, "chainStep", 30).title, "Secret 30")
	Equal(Find(rows, "chainStep", 10).title, "Quest name hidden")
	graph.order = { 30, 10, 4 } -- No origin means there is no established earlier prefix.
	a:QueuePartyQuestCompareRender(); a:Flush()
	rows = Rows(a)
	assert(Find(rows, nil, 2).chainAnchor)
	Equal(Find(rows, "chainStep", 30).title, "Quest name hidden")
	Equal(Find(rows, "chainStep", 10).title, "Quest name hidden")
	graph.order = { 10, 2, 30, 4 }
	a:QueuePartyQuestCompareRender(); a:Flush(); Rows(a)
	local replacement = Graph({ 2, 10, 30, 4 })
	replacement.edges = {}
	a.graphs[2], a.graphs[4] = replacement, replacement
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(a:GetPartyQuestChainDisplayTitle(10), "Quest name hidden")
	Equal(Find(Rows(a), "chainStep", 10).title, "Quest name hidden")
end)

QT:RegisterTest("chain earlier title actions retire with hidden or replaced displayed context", function()
	for _, changed in ipairs({ "close", "filter", "collapse", "root", "retire", "session" }) do
		local a, session = Fixture()
		a.options.compareGroupByChain = changed == "collapse"
		local graph = Graph({ 10, 2, 30, 4 })
		graph.edges = {}
		a.metadata[10] = { title = "Earlier alternative", locations = {
			{ mapID = 12, x = 0.3, y = 0.4, name = "Earlier guide" },
		} }
		local validGiver, placed
		function a:ShowQuestChainGiver(_, valid) validGiver = valid; assert(valid()); return true end
		function a:OpenPingWaypoint() placed = (placed or 0) + 1; return true end
		local rows = Open(a, session, graph)
		local giver, waypoint
		for _, action in ipairs(a:GetPartyQuestChainActions(Find(rows, "chainStep", 10))) do
			if action.label:find("Find quest giver", 1, true) then giver = action end
			if action.label:find("Set waypoint", 1, true) then waypoint = action end
		end
		assert(giver and waypoint); assert(giver.action()); assert(waypoint.action()); Equal(placed, 1)
		if changed == "close" then assert(a:ClosePartyQuestChain())
		elseif changed == "filter" then session.search = "no matching roots"; Equal(#Rows(a), 0)
		elseif changed == "collapse" then assert(a:TogglePartyQuestChainGroup(Find(rows, "chainGroup").groupId))
		elseif changed == "root" then
			assert(a:OpenPartyQuestChain(4, "quest:4"))
			graph.order = { 4, 10, 2, 30 }; a:Flush(); Rows(a)
		elseif changed == "retire" then a:RetirePartyQuestChains()
		else
			local replacement = { playerName = session.playerName, members = session.members, byName = session.byName,
				mode = "party", expandedQuestIds = {}, search = "", objectiveOwner = {} }
			a.partyQuestCompareSession = replacement
			a:AttachPartyQuestChains(replacement, session); a:Flush()
		end
		Equal(a:GetPartyQuestChainDisplayTitle(10), "Quest name hidden")
		Equal(validGiver(), false); Equal(giver.action(), false); Equal(waypoint.action(), false); Equal(placed, 1)
	end
end)

QT:RegisterTest("chain earlier titles become visible only when the reopened section is painted", function()
	local a, session = Fixture()
	local graph = Graph({ 10, 2, 30, 4 })
	graph.edges = {}
	Open(a, session, graph)
	assert(a:ClosePartyQuestChain()); a:Flush()
	assert(a:OpenPartyQuestChain(2, "quest:2")); a:Flush()
	Equal(a:GetPartyQuestChainDisplayTitle(10), "Quest name hidden")
	Equal(Find(Rows(a), "chainStep", 10).title, "Secret 10")
end)

QT:RegisterTest("chain aliases survive a merge and earlier later expansion is explicit", function()
	local a, session = Fixture()
	a.options.compareGroupByChain = true
	a.graphs[2], a.graphs[4] = Graph({ 1, 2 }, "first"), Graph({ 4, 5 }, "second")
	a:QueuePartyQuestCompareRender(); a:Flush()
	local before = Rows(a)
	local oldIDs = {}; for _, row in ipairs(before) do if row.kind == "chainGroup" then oldIDs[#oldIDs + 1] = row.rowId end end
	Equal(#oldIDs, 2)
	local graph = Graph({ 1, 2, 3, 4, 5 }, "merged")
	graph.partial, graph.frontier.earlier = true, { 99 }
	local rows = Open(a, session, graph)
	local group = Find(rows, "chainGroup")
	for _, id in ipairs(oldIDs) do Equal(a:ResolvePartyQuestChainRowID(id), group.rowId) end
	Equal(Find(rows, "chainMore").direction, "earlier")
	local earlier, later = session.chains.earlier, session.chains.later
	assert(a:ExpandPartyQuestChain("earlier")); a:Flush()
	Equal(session.chains.earlier, earlier + 80); Equal(session.chains.later, later)
end)

QT:RegisterTest("chain grouping scopes every descendant and ends before unrelated roots", function()
	local a, session, own, friend = Fixture()
	a.options.compareGroupByChain = true
	own.entries[8], friend.entries[8] = Entry(8), Entry(8)
	own.objectiveDetails = { [2] = { questId = 2, state = "ready", objectives = {
		{ text = "Collect things", kind = "item", current = 1, required = 3, finished = false },
	} } }
	session.expandedQuestIds[2] = true
	local graph = Graph({ 1, 2, 3, 4 })
	graph.partial, graph.frontier.later = true, { 9 }
	local rows = Open(a, session, graph)
	local group = assert(Find(rows, "chainGroup"))
	local standalone, ends, kinds = nil, 0, {}
	for index, row in ipairs(rows) do
		if not row.kind and row.questId == 8 then
			standalone = index
			Equal(row.chainGroupId, nil); Equal(row.chainGroupMember, nil); Equal(row.chainGroupEnd, nil)
		else
			Equal(row.chainGroupId, group.groupId)
			Equal(row.chainGroupMember, row.kind ~= "chainGroup" and true or nil)
			if row.chainGroupEnd then ends = ends + 1 end
			kinds[row.kind or "quest"] = true
		end
	end
	assert(standalone and rows[standalone - 1].chainGroupEnd)
	Equal(ends, 1); Equal(group.chainGroupMember, nil)
	assert(kinds.quest and kinds.member and kinds.objective and kinds.chainStep and kinds.chainNotice and kinds.chainMore)
	Equal(Find(rows, nil, 2).rowId, "quest:2")
	Equal(Find(rows, "objective", 2).parentRowId, "quest:2")
	-- Reusing already-decorated roots must not leak grouping when the option changes.
	local roots = a:BuildPartyQuestDiffRows()
	a:BuildPartyQuestCompareDisplayRows(roots)
	a.options.compareGroupByChain = false
	for _, row in ipairs(a:BuildPartyQuestCompareDisplayRows(roots)) do
		Equal(row.chainGroupId, nil); Equal(row.chainGroupMember, nil); Equal(row.chainGroupEnd, nil)
		assert(row.kind ~= "chainGroup")
	end
	a.options.compareGroupByChain = true
	a:TogglePartyQuestChainGroup(group.groupId)
	rows = Rows(a)
	group = assert(Find(rows, "chainGroup"))
	assert(group.chainGroupEnd); Equal(group.chainGroupMember, nil)
	Equal(Find(rows, "chainStep"), nil); Equal(Find(rows, "objective"), nil)
	Equal(Find(rows, nil, 8).chainGroupId, nil)
end)

QT:RegisterTest("chain grouping keeps a filtered open origin inside its matching group", function()
	local a, session, own, friend = Fixture()
	a.options.compareGroupByChain = true
	own.entries[8], friend.entries[8] = Entry(8), Entry(8)
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	local roots = a:BuildPartyQuestDiffRows()
	local visible = { assert(Find(roots, nil, 4)), assert(Find(roots, nil, 8)) }
	local rows = a:BuildPartyQuestCompareDisplayRows(visible)
	local group = assert(Find(rows, "chainGroup"))
	Equal(group.hint, "1 quests hidden by filters")
	Equal(Find(rows, nil, 2), nil); assert(Find(rows, "chainStep", 2))
	local standalone
	for index, row in ipairs(rows) do
		if row.questId == 8 then standalone = index
		else Equal(row.chainGroupId, group.groupId) end
	end
	Equal(standalone, #rows)
	assert(rows[standalone - 1].chainGroupEnd)
	Equal(rows[standalone].chainGroupId, nil)
	a.options.compareGroupByChain = false
	rows = a:BuildPartyQuestCompareDisplayRows(visible)
	Equal(Find(rows, nil, 2), nil); Equal(Find(rows, "chainGroup"), nil)
	local origins, context = 0, assert(Find(rows, "chainStep", 2))
	for _, row in ipairs(rows) do
		if row.questId == 2 then origins = origins + 1 end
		if row.kind == "chainStep" then Equal(row.chainInstanceId, context.chainInstanceId) end
	end
	Equal(origins, 1); Equal(context.chainAnchor, nil)
	Equal(session.totalQuests, 3); Equal(#visible, 2)
end)

QT:RegisterTest("chain owned and completed players omit acceptance requirements without hiding missing peers blockers", function()
	local a, session, own, friend = Fixture()
	function a:EvaluateQuestChainRequirements()
		return { state = "blocked", requirements = { { kind = "requiredLevel", level = 60, state = "blocked" } }, blockers = {} }
	end
	local graph = Graph({ 1, 2, 3 })
	graph.edges[#graph.edges + 1] = { from = 1, to = 3, questID = 1, relatedQuestID = 3, kind = "replacement" }
	Open(a, session, graph)
	own.questHistory[1] = { status = "completed", sampledAt = a.now }
	friend.questHistory[1] = { status = "incomplete", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	local row = assert(Find(Rows(a), "chainStep", 1))
	Equal(row.cells[1], "Completed"); Equal(row.hint, nil)
	Equal(row.prerequisiteText, nil); Equal(row.memberPrerequisiteText[1], "")
	assert(row.memberPrerequisiteText[2]:find("Prerequisites not met", 1, true))
	for _, action in ipairs(a:GetPartyQuestChainActions(row, own.name)) do
		assert(not action.label:find("Prerequisites", 1, true) and not action.label:find("Requires level", 1, true))
	end
	own.questHistory[1] = { status = "incomplete", sampledAt = a.now }
	friend.questHistory[1] = { status = "completed", sampledAt = a.now }
	row = assert(Find(Rows(a), "chainStep", 1))
	Equal(row.hint, nil); Equal(row.memberPrerequisiteText[2], "")
	assert(row.memberPrerequisiteText[1]:find("Prerequisites not met", 1, true))
	friend.questHistory[1].sampledAt = a.now - 61
	row = assert(Find(Rows(a), "chainStep", 1))
	assert(row.cells[2] ~= "Completed")
	assert(row.memberPrerequisiteText[2]:find("Prerequisites not met", 1, true))
	for _, complete in ipairs({ false, true }) do
		own.entries[1] = Entry(1); own.entries[1].isComplete = complete
		row = assert(Find(Rows(a), "chainStep", 1))
		Equal(row.cells[1], complete and "Ready" or "Have")
		Equal(row.memberPrerequisiteText[1], ""); Equal(row.hint, nil)
		assert(row.memberPrerequisiteText[2]:find("Prerequisites not met", 1, true))
	end
end)

QT:RegisterTest("chain linear progress requires verified complete proof and character completion", function()
	local a, session, own, friend = Fixture()
	local graph = Graph({ 1, 2, 3 })
	graph.completeLinearPath, graph.linear = true, true
	Open(a, session, graph)
	own.questHistory[1] = { status = "completed", sampledAt = a.now }
	friend.questHistory[3] = { status = "completed", sampledAt = a.now }
	own.questHistory[3] = { status = "incomplete", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	local rows = Rows(a)
	local progress
	for _, row in ipairs(rows) do if row.rowId:match(":progress$") then progress = row.title end end
	Equal(progress, "1/3 completed")
	Equal(Find(rows, "chainStep", 3).title, "Quest name hidden") -- Peers' completion cannot reveal local spoilers.
	graph.partial = true
	a:QueuePartyQuestCompareRender(); a:Flush()
	for _, row in ipairs(Rows(a)) do assert(not row.rowId:match(":progress$")) end
	own.questHistory[3] = { status = "completed", sampledAt = a.now }
	Equal(Find(Rows(a), "chainStep", 3).title, "Secret 3")
	a.options.compareHideFutureQuestNames = false
	Equal(Find(Rows(a), "chainStep", 3).spoilerHidden, false)
end)

QT:RegisterTest("chain unavailable loading and retired providers leave a closable ordinary comparison", function()
	local a, session = Fixture()
	a.providerState, a.providerReason = "unavailable", "provider_missing"
	assert(a:OpenPartyQuestChain(2)); a:Flush()
	local rows = Rows(a)
	Equal(#a:BuildPartyQuestDiffRows(), 2)
	Equal(Find(rows, "chainClose"), nil)
	assert(Find(rows, nil, 2).chainExpanded)
	Equal(Find(rows, "chainNotice").title, "Install QuestieDB to view related quests on this client.")
	local callback, paints = a.providerCallbacks[1], a.renders
	a:RetirePartyQuestChains()
	callback(); a:Flush()
	Equal(a.renders, paints)
	assert(session.chains.retired)
end)

QT:RegisterTest("chain context history retains bounded evidence with existing wire budgets and retires on close", function()
	local a, session, own, friend = Fixture()
	local ids = {}; for id = 1000, 1120 do ids[#ids + 1] = id end
	session.chains.rootQuestID, session.chains.selectedQuestID = 2, 1099
	a:SetPartyQuestCompletionInterest(ids, "chain")
	a:SetPartyQuestCompletionInterest({ 2 })
	Equal(#session.historyInterestOrder, 100)
	Equal(session.historyInterestOrder[1], 1099)
	local count = 0; for _ in pairs(session.historyContext) do count = count + 1 end
	Equal(count, 99)
	friend.questHistory[1000] = { status = "completed", sampledAt = a.now }
	a:SetPartyQuestCompletionInterest({ 4 })
	assert(friend.questHistory[1000])
	a:UpdatePartyQuestCompletion()
	local pending = assert(a:GetPendingQuestCompare(friend.historyRequestId))
	Equal(#pending.historyQuestIds, 32)
	Equal(own.entries[1000], nil)
	assert(a:ClosePartyQuestChain())
	Equal(friend.questHistory[1000], nil)
	Equal(friend.historyRequestId, nil)
	pending.receiver.onHistory({ { questId = 1000, status = "completed", sampledAt = a.API.GetServerTime() } })
	Equal(friend.questHistory[1000], nil)
end)

QT:RegisterTest("chain history callbacks reject provider profile and chain-instance replacements", function()
	for _, replacement in ipairs({ "provider", "profile", "chain", "member" }) do
		local a, session, _, friend = Fixture()
		session.chains.rootQuestID = 2
		a:SetPartyQuestCompletionInterest({ 1000 }, "chain")
		a:UpdatePartyQuestCompletion()
		local pending = assert(a:GetPendingQuestCompare(friend.historyRequestId))
		if replacement == "provider" then a.questChainProviderSnapshot = { generation = 99 }
		elseif replacement == "profile" then a.db.profile = {}
		elseif replacement == "chain" then session.chains.historyGeneration = (session.chains.historyGeneration or 0) + 1
		else session.byName[friend.name] = {} end
		pending.receiver.onHistory({ { questId = 1000, status = "completed", sampledAt = a.API.GetServerTime() } })
		Equal(friend.questHistory[1000], nil)
	end
end)

QT:RegisterTest("chain giver browsing and waypoint actions stay distinct and stale menus are inert", function()
	local a, session = Fixture()
	a.options.compareHideFutureQuestNames = false
	a.metadata[3] = { title = "Future 3", locations = {
		{ mapID = 12, x = 0.3, y = 0.4, name = "Guide", kind = "npc" },
		{ mapID = 15, x = 0.2, y = 0.5, name = "Other Guide", kind = "object" },
	} }
	local browsed, placed, focused = {}, {}, 0
	function a:ShowQuestChainGiver(location, valid) assert(valid()); browsed[#browsed + 1] = location.mapID; return true end
	function a:OpenPingWaypoint(map, x, y) placed[#placed + 1] = { map, x, y }; return true end
	function a:RequestPartyQuestFocus() focused = focused + 1; return true end
	local rows = Open(a, session, Graph({ 1, 2, 3, 4 }))
	local actions = a:GetPartyQuestChainActions(Find(rows, "chainStep", 3))
	local maps, waypoints = {}, {}
	for _, action in ipairs(actions) do
		if action.label:find("Find quest giver", 1, true) then maps[#maps + 1] = action end
		if action.label:find("Set waypoint", 1, true) then waypoints[#waypoints + 1] = action end
	end
	Equal(#maps, 2); Equal(#waypoints, 2)
	assert(maps[1].action()); Equal(#browsed, 1); Equal(#placed, 0); Equal(focused, 0)
	assert(waypoints[1].action()); Equal(placed[1][1], 12); Equal(placed[1][2], 30)
	a:ClosePartyQuestChain()
	Equal(maps[2].action(), false); Equal(waypoints[2].action(), false)
	Equal(#placed, 1)
end)

QT:RegisterTest("chain metadata work stays demand driven and stale owners cannot repaint replacement sessions", function()
	local a, session = Fixture()
	a.graphs[2], a.graphs[4] = Graph({ 1, 2, 3, 4 }), Graph({ 1, 2, 3, 4 })
	a:QueuePartyQuestCompareRender(); a:Flush()
	assert(a.metadataInterested[2] and a.metadataInterested[4], "active row levels need their own metadata")
	Equal(a.metadataInterested[1], nil); Equal(a.metadataInterested[3], nil)
	Open(a, session, a.graphs[2])
	assert(#a.metadataRequests > 0)
	local callback, before = a.metadataRequests[#a.metadataRequests].callback, a.renders
	a.partyQuestCompareSession = { members = {}, byName = {} }
	callback(); a:Flush()
	Equal(a.renders, before)
end)

QT:RegisterTest("chain menus retire on concealment filter and provider revision changes", function()
	for _, changed in ipairs({ "conceal", "filter", "revision", "snapshot" }) do
		local a, session, own = Fixture()
		a.options.compareHideFutureQuestNames = false
		a.metadata[3] = { title = "Hidden future", locations = { { mapID = 12, x = 0.3, y = 0.4, name = "Guide" } } }
		local placed = 0
		function a:OpenPingWaypoint() placed = placed + 1; return true end
		local rows = Open(a, session, Graph({ 1, 2, 3, 4 }))
		local action
		for _, value in ipairs(a:GetPartyQuestChainActions(Find(rows, "chainStep", 3))) do
			if value.label:find("Set waypoint", 1, true) then action = value end
		end
		assert(action)
		if changed == "conceal" then a.options.compareHideFutureQuestNames = true
		elseif changed == "filter" then session.search = "no matching roots"; Rows(a)
		elseif changed == "revision" then a.questChainProviderSnapshot.revision = 2
		else own.entries = {} end
		Equal(action.action(), false); Equal(placed, 0)
	end
end)

QT:RegisterTest("chain prerequisite explanations distinguish evaluated gates and contextual relationships", function()
	local a, session, own = Fixture()
	local graph = Graph({ 1, 2, 3 })
	graph.edges[#graph.edges + 1] = { from = 2, to = 90, questID = 2, relatedQuestID = 90, kind = "breadcrumb" }
	Open(a, session, graph)
	local result = { state = "blocked", requirements = {
		{ kind = "level", value = 20, state = "blocked" },
		{ kind = "class", allowedNames = { "Warrior", "Mage" }, state = "met" },
		{ kind = "race", allowedNames = { "Human" }, state = "unknown" },
		{ kind = "active_parent", questID = 1, state = "unknown" },
		{ kind = "prerequisite_all", questID = 1, negative = true, state = "unknown" },
	} }
	local text = a:DescribePartyQuestChainRequirements(result)
	assert(text:find("Requires level 20", 1, true)); assert(text:find("Warrior, Mage", 1, true))
	assert(text:find("Human", 1, true)); assert(text:find("Not evaluated", 1, true))
	assert(text:find("Signed prerequisite semantics unknown", 1, true))
	assert(Find(Rows(a), nil, 2).relationshipText:find("Breadcrumb quest: Quest name hidden", 1, true))
	Equal(Find(Rows(a), "chainStep", 1).title, "Secret 1") -- Displayed earlier titles do not require a named blocker.
	Equal(own.entries[90], nil)
end)

local function PlainRequirements(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function RequirementCount(text, label)
	local count, position = 0, 1
	while true do
		local first, last = text:find(label, position, true)
		if not first then return count end
		count, position = count + 1, last + 1
	end
end
local function RequirementSection(text, heading)
	local section, active = {}, false
	for line in (PlainRequirements(text) .. "\n"):gmatch("([^\n]*)\n") do
		if line == heading or line == heading .. ":" then active = true
		elseif active then
			if line == "" then break end
			section[#section + 1] = line
		end
	end
	return table.concat(section, "\n")
end

QT:RegisterTest("chain permanent prerequisite tooltip separates impossible recoverable and unknown gates", function()
	local a = Fixture()
	local text = a:DescribePartyQuestChainRequirements({ state = "blocked", permanentlyBlocked = true, requirements = {
		{ kind = "level", value = 20, state = "blocked" },
		{ kind = "requiredSkill", state = "unknown" },
		{ kind = "max_level", value = 10, state = "blocked", permanent = true },
		{ kind = "class", allowedNames = { "Mage" }, state = "met" },
	} })
	local plain, reason = PlainRequirements(text), "Level exceeds the maximum of 10."
	assert(plain:find("No longer obtainable", 1, true))
	local permanent = assert(plain:find("\n\nCannot be met", 1, true))
	local recoverable = assert(plain:find("\n\nNot met", 1, true))
	local unknown = assert(plain:find("\n\nNot evaluated", 1, true))
	assert(permanent < recoverable and recoverable < unknown)
	assert(RequirementSection(text, "Cannot be met"):find(reason, 1, true))
	assert(RequirementSection(text, "Not met"):find("Requires level 20", 1, true))
	assert(RequirementSection(text, "Not evaluated"):find("Skill requirement", 1, true))
	assert(RequirementSection(text, "Satisfied"):find("Class requirement: Mage", 1, true))
	Equal(RequirementCount(plain, reason), 1)
	assert(not RequirementSection(text, "Not met"):find(reason, 1, true))
	assert(not plain:find("Prerequisites not met", 1, true))
	Equal(RequirementCount(plain, "Other availability conditions may apply."), 0)
	local ordinary = a:DescribePartyQuestChainRequirements({ state = "unknown", requirements = {
		{ kind = "max_level", value = 10, state = "unknown" },
	} })
	Equal(RequirementSection(ordinary, "Cannot be met"), "")
	assert(RequirementSection(ordinary, "Not evaluated"):find("Maximum level: 10", 1, true))
	assert(not PlainRequirements(ordinary):find("No longer obtainable", 1, true))
end)

QT:RegisterTest("chain prerequisite tooltip puts blockers before unknown and satisfied checks", function()
	local a = Fixture()
	local text = a:DescribePartyQuestChainRequirements({ state = "blocked", requirements = {
		{ kind = "class", allowedNames = { "Mage" }, state = "met" },
		{ kind = "requiredSkill", state = "unknown" },
		{ kind = "level", value = 20, state = "blocked" },
	} })
	local plain = PlainRequirements(text)
	assert(plain:find("Prerequisites not met", 1, true))
	local blocked = assert(plain:find("\n\nNot met", 1, true))
	local unknown = assert(plain:find("\n\nNot evaluated", 1, true))
	local met = assert(plain:find("\n\nSatisfied", 1, true))
	assert(blocked < unknown and unknown < met)
	assert(RequirementSection(text, "Not met"):find("Requires level 20", 1, true))
	assert(RequirementSection(text, "Not evaluated"):find("Skill requirement", 1, true))
	assert(RequirementSection(text, "Satisfied"):find("Class requirement: Mage", 1, true))
	Equal(RequirementCount(plain, "Requires level 20"), 1)
	Equal(RequirementCount(plain, "Other availability conditions may apply."), 1)
	assert(plain:find("\n\nOther availability conditions may apply.", 1, true))
	assert(not plain:find(" — ", 1, true), "each gate should use its section status once")
end)

QT:RegisterTest("chain prerequisite tooltip deduplicates gates without losing distinct hidden quests", function()
	local a = Fixture()
	local text = a:DescribePartyQuestChainRequirements({ state = "met", requirements = {
		{ kind = "active_parent", questID = 90, state = "met" },
		{ kind = "active_parent", questID = 90, state = "met" },
		{ kind = "active_parent", questID = 91, state = "met" },
		{ kind = "active_parent", questID = 92, state = "met" },
		{ kind = "starting_with", questID = 90, state = "met" },
	} }, {
		{ kind = "active_parent", relatedQuestID = 90 },
		{ kind = "active_parent", relatedQuestID = 91 },
		{ kind = "active_parent", relatedQuestID = 92 },
		{ kind = "starting_with", relatedQuestID = 90 },
		{ kind = "breadcrumb", relatedQuestID = 90 },
		{ kind = "breadcrumb", relatedQuestID = 90 },
	})
	local plain = PlainRequirements(text)
	assert(RequirementSection(text, "Satisfied"):find("Requires active quest: Quest name hidden (3)", 1, true))
	Equal(RequirementCount(plain, "Requires active quest:"), 1)
	Equal(RequirementCount(plain, "Requires active or completed quest: Quest name hidden"), 1)
	assert(not plain:find("Active parent quest:", 1, true))
	assert(not plain:find("Available starting with quest:", 1, true))
	Equal(RequirementCount(RequirementSection(text, "Related quests"), "Breadcrumb quest: Quest name hidden"), 1)
	assert(not plain:find("Quest 90", 1, true) and not plain:find("Quest 91", 1, true))
end)

QT:RegisterTest("chain prerequisite tooltip retains separate blocked and unknown hidden quest gates", function()
	local a = Fixture()
	local text = a:DescribePartyQuestChainRequirements({ state = "blocked", requirements = {
		{ kind = "active_parent", questID = 90, state = "blocked" },
		{ kind = "active_parent", questID = 90, state = "blocked" },
		{ kind = "active_parent", questID = 91, state = "blocked" },
		{ kind = "starting_with", questID = 92, state = "unknown" },
		{ kind = "starting_with", questID = 93, state = "unknown" },
	} })
	Equal(RequirementCount(RequirementSection(text, "Not met"), "Requires active quest: Quest name hidden"), 2)
	Equal(RequirementCount(RequirementSection(text, "Not evaluated"), "Requires active or completed quest: Quest name hidden"), 2)
	assert(not PlainRequirements(text):find("(2)", 1, true))
end)

QT:RegisterTest("chain prerequisite tooltip presents alternatives as one evaluated OR gate", function()
	for _, case in ipairs({
		{ first = true, second = false, state = "met", section = "Satisfied" },
		{ first = false, state = "unknown", section = "Not evaluated" },
		{ first = false, second = false, state = "blocked", section = "Not met" },
	}) do
		local a = Fixture()
		local snapshot = UseProviderSnapshot(a, "questiedb")
		snapshot.nodes[10], snapshot.metadata[10] = { questID = 10 }, {}
		snapshot.relations[10] = {
			{ kind = "prerequisite_any", relatedQuestID = 90 },
			{ kind = "prerequisite_any", relatedQuestID = 91 },
		}
		local result = QT.EvaluateQuestChainRequirements(a, 10, {
			[90] = { completed = case.first }, [91] = { completed = case.second },
		})
		Equal(result.state, case.state); Equal(result.groups.any, case.state)
		local text = a:DescribePartyQuestChainRequirements(result, snapshot.relations[10])
		local label = "One of these quests must be completed:"
		Equal(RequirementCount(PlainRequirements(text), label), 1)
		assert(RequirementSection(text, case.section):find(label, 1, true))
		for _, section in ipairs({ "Not met", "Not evaluated", "Satisfied" }) do
			if section ~= case.section then Equal(RequirementSection(text, section), "") end
		end
		Equal(RequirementSection(text, "Related quests"), "")
	end
end)

QT:RegisterTest("chain prerequisite tooltip never colors unknown or signed gates as satisfied", function()
	local a = Fixture()
	local met = a:DescribePartyQuestChainRequirements({ state = "met", requirements = {
		{ kind = "level", value = 20, state = "met" },
	} })
	local satisfiedColor = assert(met:match("|c(%x%x%x%x%x%x%x%x)Known prerequisites met"))
	local unknown = a:DescribePartyQuestChainRequirements({ state = "unknown", requirements = {
		{ kind = "prerequisite_all", questID = 90, negative = true, state = "unknown" },
		{ kind = "requiredSpell", value = 1, state = "unknown" },
	} }, { { kind = "prerequisite_all", relatedQuestID = 90, negative = true } })
	assert(not unknown:find("|c" .. satisfiedColor, 1, true))
	local pending = RequirementSection(unknown, "Not evaluated")
	assert(pending:find("Signed prerequisite semantics unknown", 1, true))
	assert(pending:find("Spell requirement", 1, true))
	Equal(RequirementSection(unknown, "Satisfied"), "")
	Equal(RequirementCount(unknown, "Signed prerequisite semantics unknown"), 1)
	Equal(RequirementSection(unknown, "Related quests"), "")
	-- A signed alternative remains unknown even when its history says complete.
	local snapshot = UseProviderSnapshot(a, "questiedb")
	snapshot.nodes[10], snapshot.metadata[10] = { questID = 10 }, {}
	snapshot.relations[10] = {
		{ kind = "prerequisite_any", relatedQuestID = 90, negative = true },
		{ kind = "prerequisite_any", relatedQuestID = 91 },
	}
	local result = QT.EvaluateQuestChainRequirements(a, 10, {
		[90] = { completed = true }, [91] = { completed = false },
	})
	Equal(result.state, "unknown"); Equal(result.groups.any, "unknown")
	local alternative = a:DescribePartyQuestChainRequirements(result, snapshot.relations[10])
	assert(RequirementSection(alternative, "Not evaluated"):find("Signed prerequisite semantics unknown", 1, true))
	assert(not alternative:find("|c" .. satisfiedColor, 1, true))
	Equal(RequirementSection(alternative, "Not met"), "")
	Equal(RequirementSection(alternative, "Satisfied"), "")
end)

QT:RegisterTest("chain prerequisite tooltip supports blockers-only and context-only provider data", function()
	local a = Fixture()
	local blocked = a:DescribePartyQuestChainRequirements({ state = "blocked", blockers = {
		{ kind = "active_parent", questID = 90 },
		{ kind = "active_parent", questID = 90 },
	} }, { { kind = "active_parent", relatedQuestID = 90 } })
	Equal(RequirementCount(RequirementSection(blocked, "Not met"), "Requires active quest: Quest name hidden"), 1)
	Equal(RequirementSection(blocked, "Related quests"), "")
	local context = a:DescribePartyQuestChainRequirements(nil, {
		{ kind = "breadcrumb", relatedQuestID = 90 },
		{ kind = "breadcrumb", relatedQuestID = 90 },
		{ kind = "active_parent", relatedQuestID = 90 },
	}, true)
	local related = RequirementSection(context, "Related quests")
	Equal(RequirementCount(related, "Breadcrumb quest: Quest name hidden"), 1)
	Equal(RequirementCount(related, "Active parent quest: Quest name hidden"), 1)
	assert(not PlainRequirements(context):find("Prerequisites", 1, true))
	Equal(RequirementSection(context, "Not met"), "")
	Equal(RequirementSection(context, "Satisfied"), "")
end)

QT:RegisterTest("chain prerequisite tooltip keeps signed quest identities and fallback OR uncertainty", function()
	local a, session = Fixture()
	a.options.compareHideFutureQuestNames = false
	session.chains.metadata[90] = { title = "Signed alternative" }
	session.chains.metadata[91] = { title = "Incomplete alternative" }
	local alternatives = {
		{ kind = "prerequisite_any", questID = 90, negative = true, state = "unknown" },
		{ kind = "prerequisite_any", questID = 91, state = "blocked" },
	}
	-- Older provider shapes can omit groups.any; the signed alternative still
	-- makes the OR gate unknown rather than proving the positive branch blocks it.
	local text = a:DescribePartyQuestChainRequirements({ state = "unknown", requirements = alternatives })
	local pending = RequirementSection(text, "Not evaluated")
	Equal(RequirementCount(pending, "One of these conditions must be met:"), 1)
	assert(pending:find("Signed prerequisite semantics unknown: Signed alternative", 1, true))
	assert(pending:find("Requires completed quest: Incomplete alternative", 1, true))
	Equal(RequirementSection(text, "Not met"), "")
	Equal(RequirementSection(text, "Satisfied"), "")
	local signed = a:DescribePartyQuestChainRequirements({ state = "unknown", requirements = {
		{ kind = "prerequisite_all", questID = 90, negative = true, state = "unknown" },
		{ kind = "prerequisite_all", questID = 91, negative = true, state = "unknown" },
	} })
	pending = RequirementSection(signed, "Not evaluated")
	Equal(RequirementCount(pending, "Signed prerequisite semantics unknown:"), 2)
	assert(pending:find("Signed alternative", 1, true))
	assert(pending:find("Incomplete alternative", 1, true))
	a.options.compareHideFutureQuestNames = true
	local hidden = a:DescribePartyQuestChainRequirements({ state = "unknown", requirements = alternatives })
	assert(not hidden:find("Signed alternative", 1, true) and not hidden:find("Incomplete alternative", 1, true))
	assert(hidden:find("Signed prerequisite semantics unknown: Quest name hidden", 1, true))
end)

QT:RegisterTest("chain member eligibility reads only stable matching grouped unit identities", function()
	local a, session, _, friend = Fixture()
	local unitName, reads = friend.name, 0
	a.partyMembers[friend.name] = { classFile = "MAGE" }
	function a:GetUnitFullName(unit) return unit == "party2" and unitName or nil end
	a.API.IsInRaid = function() return false end
	a.API.GetQuestChainUnitInfo = function(unit)
		Equal(unit, "party2"); reads = reads + 1
		return { level = 20, raceID = 1, classFile = "MAGE" }
	end
	local info = a:GetPartyQuestChainCharacterEvidence(friend)
	Equal(info.level, 20); Equal(info.raceID, 1); Equal(reads, 1)
	a.API.GetQuestChainUnitInfo = function() unitName = "Replacement-Realm"; return { level = 99, raceID = 2 } end
	info = a:GetPartyQuestChainCharacterEvidence(friend)
	Equal(info.level, nil); Equal(info.raceID, nil)
	a.partyMembers[friend.name] = nil
	info = a:GetPartyQuestChainCharacterEvidence(friend)
	Equal(info.level, nil)
end)

QT:RegisterTest("chain revealed details and peer focus actions reuse current availability guards", function()
	local a, session, _, friend = Fixture()
	local details, follows = 0, 0
	a.options.compareHideFutureQuestNames = false
	function a:GetQuestDetailsAvailability(id) return self.detailsUnavailable ~= true and id or nil end
	function a:ShowQuestDetails(id, title) Equal(id, 3); Equal(title, "Secret 3"); details = details + 1; return true end
	function a:FollowPartyQuestFocus(name) Equal(name, friend.name); follows = follows + 1; return true end
	local rows = Open(a, session, Graph({ 1, 2, 3, 4 }))
	local actions = a:GetPartyQuestChainActions(Find(rows, "chainStep", 3), friend.name)
	local detail
	for _, action in ipairs(actions) do
		if action.label == "Quest Details" then detail = action; assert(action.action()) end
		if action.label == "Follow quest focus" then assert(action.action()) end
	end
	Equal(details, 1); Equal(follows, 1); assert(detail)
	a.detailsUnavailable = true
	Equal(detail.action(), false); Equal(details, 1)
end)

QT:RegisterTest("chain origin retains guarded context actions without duplicating its ordinary controls", function()
	local a, session, _, friend = Fixture()
	a.metadata[2] = { title = "Current quest", locations = {
		{ mapID = 12, x = 0.3, y = 0.4, name = "Guide", kind = "npc" },
	} }
	local details, focus, follows, givers, waypoints = 0, 0, 0, 0, 0
	function a:GetQuestDetailsAvailability(id) return id end
	function a:ShowQuestDetails(id, title)
		Equal(id, 2); Equal(title, "Current quest"); details = details + 1; return true
	end
	function a:RequestPartyQuestFocus(name, id) Equal(name, friend.name); Equal(id, 2); focus = focus + 1; return true end
	function a:FollowPartyQuestFocus(name) Equal(name, friend.name); follows = follows + 1; return true end
	function a:ShowQuestChainGiver(location, valid) Equal(location.mapID, 12); assert(valid()); givers = givers + 1; return true end
	function a:OpenPingWaypoint(map) Equal(map, 12); waypoints = waypoints + 1; return true end
	local rows = Open(a, session, Graph({ 1, 2, 3, 4 }))
	local origin = assert(Find(rows, nil, 2))
	Equal(origin.action, "share")
	local actions = a:GetPartyQuestChainActions(origin, friend.name)
	local labels = {}
	for _, action in ipairs(actions) do
		assert(not labels[action.label], "duplicate anchor action")
		labels[action.label] = true
		assert(action.label ~= "Open in Quest Log" and action.label ~= "Expand or collapse quest"
			and action.label ~= "Share" and action.label ~= "Request Share")
		assert(action.action())
	end
	Equal(details, 1); Equal(focus, 1); Equal(follows, 1); Equal(givers, 1); Equal(waypoints, 1)
	assert(labels["Focus quest"] and labels["Follow quest focus"] and labels["Quest Details"])
	assert(a:ClosePartyQuestChain())
	for _, action in ipairs(actions) do Equal(action.action(), false) end
	Equal(details, 1); Equal(focus, 1); Equal(follows, 1); Equal(givers, 1); Equal(waypoints, 1)
end)

QT:RegisterTest("chain eligibility preserves fresher active history over an older absent snapshot", function()
	local a, session, _, friend = Fixture()
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	friend.questHistory[1] = { status = "active", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(a.evidenceByQuest[2][1].active, true)
	Equal(friend.entries[1], nil)
end)

QT:RegisterTest("share readiness prepares ordinary visible prerequisites without opening a chain", function()
	local a, session, _, friend = Fixture()
	a.graphs[2] = Graph({ 1, 2 })
	friend.entries = {}
	friend.questHistory[2] = { status = "incomplete", sampledAt = a.now }
	a:SetPartyQuestCompletionInterest({ 2 })
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(session.chains.rootQuestID, nil)
	Equal(session.historyInterests[1], true)
	friend.questHistory[1] = { status = "incomplete", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	local evaluate = a.EvaluateQuestChainRequirements
	function a:EvaluateQuestChainRequirements() error("painting must not evaluate requirements") end
	local row
	for _, candidate in ipairs(a:BuildPartyQuestDiffRows()) do if candidate.questId == 2 then row = candidate end end
	assert(row); Equal(row.shareReadiness.disabled, true)
	Equal(row.shareReadiness.byName[friend.name].state, "blocked")
	a.EvaluateQuestChainRequirements = evaluate
	a:SetPartyQuestCompletionInterest({ 4 }); a:Flush()
	Equal(session.historyInterests[1], nil)
	Equal(friend.questHistory[1].status, "incomplete")
	-- Retaining accepted facts avoids action-filter churn but does not renew them.
	a.now = a.now + 60
	a:SetPartyQuestCompletionInterest({ 4 }); a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(friend.questHistory[1], nil)
end)

QT:RegisterTest("chain world resumption replaces only an existing visible retired session without focus", function()
	local a, session = Fixture()
	local refreshes = 0
	a.partyQuestCompareWindow.IsShown = function() return true end
	function a:RefreshPartyQuestCompare(_, target, conditional)
		Equal(target, session.targetName); Equal(conditional, true); refreshes = refreshes + 1
	end
	function a:RequestPartyQuestKeyboardFocus() error("world resume stole keyboard focus") end
	function a:RequestPartyQuestGamepadFocus() error("world resume stole native focus") end
	a:RetirePartyQuestChains()
	assert(a:ResumePartyQuestChains()); a:Flush(); Equal(refreshes, 1)
	a.partyQuestCompareWindow.IsShown = function() return false end
	Equal(a:ResumePartyQuestChains(), false)
end)

QT:RegisterTest("chain profile replacement retires work before effects and resumes only its unchanged visible view", function()
	for _, replace in ipairs({ false, true }) do
		local events, scheduled = {}, nil
		local a = { isEnabled = true, db = { profile = {} }, partyQuestCompareSession = { targetName = "Friend-Realm" },
			partyQuestCompareWindow = { IsShown = function() return true end } }
		function a:GetOption() return nil end
		-- Other presentation services are inert in this profile-order fixture.
		for _, method in ipairs({
			"AnnounceQuestPartnerSearch",
			"ApplyAudioSettings",
			"BroadcastQuestPartnerStatus",
			"CancelDeveloperDiagnosticReplies",
			"ClearPlayerLocationClusterExpansion",
			"ClearPlayerMapSelection",
			"InitializeAutoThanks",
			"OnPlayerLocationOptionsChanged",
			"QueuePartyNavigationUpdate",
			"QueueQuestFocusRefresh",
			"RefreshActiveAnnouncementBubbles",
			"RefreshDataBroker",
			"RefreshManagedWindowLayouts",
			"RefreshMinimapButton",
			"RefreshMinimapPartnerGlow",
			"RefreshNameplateAugmentation",
			"RefreshOptionsWindow",
			"RefreshPartyRoster",
			"RefreshPartyWaypointPins",
			"RefreshPersonalBubbleAnchorVisualState",
			"RefreshPersonalBubbleEditModeDialog",
			"RefreshPlayerLocationPins",
			"RefreshProfilesWindow",
			"RefreshQuestTogetherMapControl",
			"RefreshWindowThemes",
			"ResetObjectiveAnnouncements",
			"ResetQuestStarterItems",
			"ResetPlayerPhases",
			"SetGamepadIntegrationEnabled",
			"UpdatePartyChatReminder",
			"UpdatePlayerTooltipBadge",
		}) do a[method] = function() end end
		function a:ApplyFeaturePolicies() end
		function a:IsAudioSetting() return false end
		function a:CancelPartyQuestCompare() events[#events + 1] = "cancel"; self.partyQuestCompareSession = nil end
		function a:InvalidateQuestCompareSnapshot() events[#events + 1] = "invalidate" end
		function a:CloseQuestLogChatFrame() end
		function a:Debugf() end
		function a:ScheduleDeferredWork(_, _, callback) scheduled = callback end
		function a:RefreshPartyQuestCompare(_, target, conditional)
			Equal(target, "Friend-Realm"); Equal(conditional, true); events[#events + 1] = "resume"
		end
		assert(QT.ApplySettingsTransaction(a, {}, { replace = true }))
		Equal(events[1], "cancel"); Equal(events[2], "invalidate"); assert(scheduled)
		if replace then a.db.profile = {} end
		scheduled()
		if replace then Equal(events[3], nil) else Equal(events[3], "resume") end
	end
end)

QT:RegisterTest("chain large session presentation buckets relationship work once per edge", function()
	local a, session = Fixture()
	local ids, size = {}, 10000
	for id = 1, size do ids[id] = id end
	local graph, sourceReads = Graph(ids), 0
	for index, edge in ipairs(graph.edges) do
		local source = edge
		graph.edges[index] = setmetatable({}, { __index = function(_, field)
			if field == "questID" then
				sourceReads = sourceReads + 1
				assert(sourceReads <= 2 * size, "presentation rescanned every component edge for each node")
			end
			return source[field]
		end })
	end
	local rows = Open(a, session, graph)
	Equal(sourceReads, size - 1)
	local steps = 0; for _, row in ipairs(rows) do if row.kind == "chainStep" or row.chainAnchor then steps = steps + 1 end end
	Equal(steps, size)
	local bucketReads, bucketCount = 0, 0
	for _, bucket in pairs(session.chains.relationshipsByQuest) do
		for index, edge in ipairs(bucket) do
			bucketCount = bucketCount + 1
			local source = edge
			bucket[index] = setmetatable({}, { __index = function(_, field)
				if field == "kind" then bucketReads = bucketReads + 1 end
				return source[field]
			end })
		end
	end
	Equal(bucketCount, size - 1)
	Rows(a); Rows(a)
	Equal(sourceReads, size - 1) -- Painting never revisits the source graph edges.
	Equal(bucketReads, 2 * (size - 1)) -- Each paint consumes exactly one node bucket.
end)

QT:RegisterTest("chain metadata demand retires immediately on close replacement and group collapse", function()
	local a, session = Fixture()
	local function OnlyActiveRoots()
		assert(a.metadataInterested[2] and a.metadataInterested[4])
		Equal(a.metadataInterested[1], nil); Equal(a.metadataInterested[3], nil)
	end
	a.options.compareGroupByChain = true
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	assert(a.metadataInterested[1] and a.metadataInterested[3])
	local callback, before = a.metadataRequests[#a.metadataRequests].callback, a.renders
	local groupID = session.chains.questGroups[2]
	a:TogglePartyQuestChainGroup(groupID)
	OnlyActiveRoots()
	local afterCollapse = a.renders
	callback(); Equal(a.renders, afterCollapse)
	a:Flush(); OnlyActiveRoots()
	local requests = #a.metadataRequests
	a:TogglePartyQuestChainGroup(groupID); a:Flush()
	assert(a.metadataInterested[1] and #a.metadataRequests > requests)
	a:OpenPartyQuestChain(4, "quest:4")
	OnlyActiveRoots()
	a:Flush(); assert(a.metadataInterested[3])
	a:ClosePartyQuestChain(); OnlyActiveRoots()
	a:Flush(); OnlyActiveRoots()
	assert(a.renders > before)
end)

QT:RegisterTest("chain retired Retail context retains only active native membership demand", function()
	local a, session = Fixture()
	a.providerKind = "retail"
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	assert(a.metadataInterested[1] and a.metadataInterested[3])
	a:ClosePartyQuestChain()
	Equal(a.metadataInterested[1], nil); Equal(a.metadataInterested[3], nil)
	assert(a.metadataInterested[2] and a.metadataInterested[4])
	a:Flush()
	Equal(a.metadataInterested[1], nil); Equal(a.metadataInterested[3], nil)
	assert(a.metadataInterested[2] and a.metadataInterested[4])
end)

QT:RegisterTest("chain failed provider retires metadata demand without repeating requests", function()
	local a, session = Fixture()
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	local requests = #a.metadataRequests
	a.providerState = "unavailable"
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(next(a.metadataInterested), nil); Equal(#a.metadataRequests, requests)
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(#a.metadataRequests, requests)
end)

QT:RegisterTest("chain same control opens closes reopens and switches roots without collapsing objectives", function()
	local a, session, own, friend = Fixture()
	local graph = Graph({ 1, 2, 3, 4 })
	a.graphs[2], a.graphs[4] = graph, graph
	for id in pairs(graph.nodes) do a.metadata[id] = { title = "Secret " .. id } end
	session.expandedQuestIds[2] = true
	assert(a:TogglePartyQuestChain(2, "quest:2")); a:Flush()
	local rows = Rows(a)
	assert(Find(rows, nil, 2).chainExpanded); Equal(Find(rows, nil, 4).chainExpanded, false)
	Equal(Find(rows, "chainClose"), nil); assert(Find(rows, "chainStep", 3))
	assert(a.metadataInterested[1])
	friend.questHistory[1] = { status = "completed", sampledAt = a.now }
	a:UpdatePartyQuestCompletion()
	local pending = assert(a:GetPendingQuestCompare(friend.historyRequestId))
	local closed, origin = a:TogglePartyQuestChain(2, "quest:2")
	assert(closed); Equal(origin, "quest:2"); Equal(session.chains.rootQuestID, nil)
	Equal(a.metadataInterested[1], nil); Equal(a.metadataInterested[3], nil)
	assert(a.metadataInterested[2] and a.metadataInterested[4])
	Equal(friend.questHistory[1], nil); Equal(friend.historyRequestId, nil)
	Equal(next(session.historyContext), nil); Equal(session.expandedQuestIds[2], true)
	pending.receiver.onHistory({ { questId = 1, status = "completed", sampledAt = a.API.GetServerTime() } })
	Equal(friend.questHistory[1], nil)
	a:Flush(); rows = Rows(a)
	Equal(Find(rows, nil, 2).chainExpanded, false); Equal(Find(rows, "chainStep"), nil)
	assert(a:TogglePartyQuestChain(2, "quest:2")); a:Flush()
	assert(a.metadataInterested[1]); Equal(session.chains.rootQuestID, 2)
	local previousInstance = session.chains.instance
	assert(a:TogglePartyQuestChain(4, "quest:4"))
	Equal(session.chains.rootQuestID, 4); Equal(session.chains.originRowId, "quest:4")
	assert(session.chains.instance > previousInstance)
	Equal(a.metadataInterested[1], nil); Equal(a.metadataInterested[3], nil)
	a:Flush(); rows = Rows(a)
	Equal(Find(rows, nil, 2).chainExpanded, false); assert(Find(rows, nil, 4).chainExpanded)
	assert(a:TogglePartyQuestChain(4, "quest:4"))
	Equal(session.chains.rootQuestID, nil); Equal(session.expandedQuestIds[2], true)
	Equal(own.entries[1], nil); Equal(own.entries[3], nil)
end)

QT:RegisterTest("chain toggle preserves restrictions and lets the origin close an unavailable section", function()
	local a, session = Fixture()
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	local original = a.IsWorkBlocked
	function a:IsWorkBlocked() return true end
	Equal(a:TogglePartyQuestChain(2, "quest:2"), false); Equal(session.chains.rootQuestID, 2)
	a.IsWorkBlocked = original
	Equal(a:TogglePartyQuestChain(-1, "quest:2"), false); Equal(session.chains.rootQuestID, 2)
	a.providerState = "unavailable"
	a:QueuePartyQuestCompareRender(); a:Flush()
	local rows = Rows(a)
	assert(Find(rows, nil, 2).chainExpanded and Find(rows, nil, 2).chainAvailable)
	Equal(Find(rows, nil, 4).chainAvailable, false); Equal(Find(rows, "chainClose"), nil)
	assert(a:TogglePartyQuestChain(2, "quest:2")); a:Flush()
	Equal(Find(Rows(a), nil, 2).chainAvailable, false)
end)

QT:RegisterTest("quest levels use deferred native snapshot and provider facts without render reads", function()
	local a, session = Fixture()
	local nativeLevel, colorReads, levelReads = 21, 0, 0
	local nativeColor = { r = 1, g = 0.5, b = 0 }
	a.API.GetQuestDifficultyLevel = function(id) levelReads = levelReads + 1; return id == 2 and nativeLevel or nil end
	a.API.GetQuestDifficultyColor = function() colorReads = colorReads + 1; return nativeColor end
	function a:GetQuestSnapshot(id) return id == 4 and { questLevel = 19 } or nil end
	a.metadata[1] = { title = "Earlier", questLevel = 18, requiredLevel = 16 }
	a.metadata[2] = { title = "Current", questLevel = 18, requiredLevel = 16 }
	a.metadata[3] = { title = "Future", questLevel = 18, requiredLevel = 16 }
	a.metadata[4] = { title = "Other", requiredLevel = 16 }
	local rows = Open(a, session, Graph({ 1, 2, 3, 4, 5 }))
	Equal(Find(rows, nil, 2).questLevel, 21); Equal(Find(rows, nil, 4).questLevel, 19)
	Equal(Find(rows, "chainStep", 1).questLevel, 18); Equal(Find(rows, "chainStep", 3).questLevel, 18)
	Equal(Find(rows, "chainStep", 5).questLevel, nil)
	Equal(Find(rows, "chainStep", 3).title, "Quest name hidden")
	Equal(Find(rows, nil, 2).title, "Current")
	Equal(session.members[1].entries[2].questTitle, "Active 2")
	Equal(colorReads, 3, "one native color read for each distinct known level")
	nativeColor.g = 0
	Equal(Find(rows, nil, 2).questDifficultyColor.g, 0.5, "native color objects must not escape")
	local reads = levelReads
	a.API.GetQuestDifficultyLevel = function() error("paint read native quest level") end
	a.API.GetQuestDifficultyColor = function() error("paint read native difficulty") end
	function a:GetQuestChainQuestInfo() error("paint read provider metadata") end
	rows = Rows(a)
	Equal(Find(rows, nil, 2).questLevel, 21); Equal(Find(rows, "chainStep", 1).questLevel, 18)
	Equal(levelReads, reads)
end)

QT:RegisterTest("quest level presentation refreshes without providers and rejects unknown or inaccessible data", function()
	local a, session = Fixture()
	a.providerState, a.providerReason = "unavailable", "provider_missing"
	local level, color = nil, { r = 1, g = 0.82, b = 0 }
	a.API.GetQuestDifficultyLevel = function(id) return id == 2 and level or nil end
	a.API.GetQuestDifficultyColor = function() return color end
	function a:GetQuestSnapshot(id) return id == 4 and { questLevel = 18 } or nil end
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(Find(Rows(a), nil, 2).questLevel, nil); Equal(Find(Rows(a), nil, 4).questLevel, 18)
	function a:OnQuestChainDataEvent() end
	a.localizedQuestTitles = false
	level = 20
	a:QUEST_DATA_LOAD_RESULT("QUEST_DATA_LOAD_RESULT", 2, true); a:Flush()
	Equal(Find(Rows(a), nil, 2).questLevel, 20)
	function a:PickRandomCompletionEmote() return "CHEER" end
	function a:PublishAnnouncementEvent() end
	function a:PlayLocalCelebrationEmote() end
	color = { r = 0.5, g = 0.5, b = 0.5 }
	a:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 30); a:Flush()
	Equal(Find(Rows(a), nil, 2).questDifficultyColor.r, 0.5)
	local inaccessible = {}
	function a:CanAccessValue(value) return value ~= inaccessible end
	function a:CanAccessTable(value) return value ~= inaccessible and type(value) == "table" end
	for _, invalid in ipairs({ inaccessible, 0, -1, 0.5, math.huge }) do
		level = invalid; a:QueuePartyQuestCompareRender(); a:Flush()
		Equal(Find(Rows(a), nil, 2).questLevel, nil)
	end
	level, color = 20, inaccessible; a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(Find(Rows(a), nil, 2).questLevel, 20); Equal(Find(Rows(a), nil, 2).questDifficultyColor, nil)
end)

QT:RegisterTest("quest group recommendations preserve authoritative false and cache per-ID evidence for rendering", function()
	local a, session = Fixture()
	local native = { [2] = true, [4] = false }
	local snapshots = { [4] = { questLevel = 25, questGroupRecommended = true } }
	a.API.GetQuestGroupRecommended = function(id) return native[id] end
	function a:GetQuestSnapshot(id) return snapshots[id] end
	a.metadata[1] = { title = "Earlier", questLevel = 25, questGroupRecommended = true }
	a.metadata[3] = { title = "Future", questLevel = 25, inGroupWith = { 1 }, requiredLevel = 20 }
	local rows = Open(a, session, Graph({ 1, 2, 3, 4 }))
	Equal(Find(rows, nil, 2).questGroupRecommended, true)
	Equal(Find(rows, nil, 4).questGroupRecommended, false)
	Equal(Find(rows, "chainStep", 1).questGroupRecommended, true)
	Equal(Find(rows, nil, 2).questGroupRecommended, true)
	Equal(Find(rows, "chainStep", 3).questGroupRecommended, nil, "chain groups never imply party recommendation")
	native, snapshots = {}, {}
	a.metadata[1].questGroupRecommended = nil
	a:QueuePartyQuestCompareRender(); a:Flush()
	rows = Rows(a)
	Equal(Find(rows, nil, 2).questGroupRecommended, true, "known evidence survives temporarily unreadable metadata")
	Equal(Find(rows, nil, 4).questGroupRecommended, false)
	Equal(Find(rows, "chainStep", 1).questGroupRecommended, true)
	snapshots[4] = { questGroupRecommended = true }
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(Find(Rows(a), nil, 4).questGroupRecommended, true, "new snapshot evidence refreshes remembered facts")
	native[2] = false; a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(Find(Rows(a), nil, 2).questGroupRecommended, false)
	a.API.GetQuestGroupRecommended = function() error("render queried native group recommendation") end
	rows = Rows(a)
	Equal(Find(rows, nil, 2).questGroupRecommended, false)
	Equal(Find(rows, "chainStep", 3).title, "Quest name hidden")
end)

_G.QuestTogether:RecordTestModule("scripts/regression_quest_compare_chains.lua")
