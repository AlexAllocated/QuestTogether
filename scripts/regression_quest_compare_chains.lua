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
	Equal(Find(rows, "chainStep", 3).title, "Future quest")
	Equal(Find(rows, "chainStep", 4).title, "Active 4")
	Equal(Find(rows, "chainStep", 1).cells[1], "Absent")
	assert(Find(rows, "chainStep", 2).memberPrerequisiteText[1]:find("Secret 1", 1, true))
	assert(Find(rows, "chainClose"))
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
	assert(Find(Rows(a), "chainStep", 2))
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
	Equal(Find(rows, "chainStep", 3).title, "Future quest") -- Peers' completion cannot reveal local spoilers.
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
	assert(Find(rows, "chainClose"))
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
	Equal(#a.metadataRequests, 0)
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
	assert(Find(Rows(a), "chainStep", 2).relationshipText:find("Breadcrumb quest: Future quest", 1, true))
	Equal(Find(Rows(a), "chainStep", 1).title, "Future quest") -- An unevaluated ancestor is not a named blocker.
	Equal(own.entries[90], nil)
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

QT:RegisterTest("chain eligibility preserves fresher active history over an older absent snapshot", function()
	local a, session, _, friend = Fixture()
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	friend.questHistory[1] = { status = "active", sampledAt = a.now }
	a:QueuePartyQuestCompareRender(); a:Flush()
	Equal(a.lastEvidence[1].active, true)
	Equal(friend.entries[1], nil)
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
	local steps = 0; for _, row in ipairs(rows) do if row.kind == "chainStep" then steps = steps + 1 end end
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
	a.options.compareGroupByChain = true
	Open(a, session, Graph({ 1, 2, 3, 4 }))
	assert(a.metadataInterested[1] and a.metadataInterested[3])
	local callback, before = a.metadataRequests[#a.metadataRequests].callback, a.renders
	local groupID = session.chains.questGroups[2]
	a:TogglePartyQuestChainGroup(groupID)
	Equal(next(a.metadataInterested), nil)
	local afterCollapse = a.renders
	callback(); Equal(a.renders, afterCollapse)
	a:Flush(); Equal(next(a.metadataInterested), nil)
	local requests = #a.metadataRequests
	a:TogglePartyQuestChainGroup(groupID); a:Flush()
	assert(a.metadataInterested[1] and #a.metadataRequests > requests)
	a:OpenPartyQuestChain(4, "quest:4")
	Equal(next(a.metadataInterested), nil)
	a:Flush(); assert(a.metadataInterested[3])
	a:ClosePartyQuestChain(); Equal(next(a.metadataInterested), nil)
	a:Flush(); Equal(next(a.metadataInterested), nil)
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

_G.QuestTogether:RecordTestModule("scripts/regression_quest_compare_chains.lua")
