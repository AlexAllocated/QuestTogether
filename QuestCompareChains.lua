-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
local QT = _G.QuestTogether
local L = QT.Translate
local PAGE_SIZE = 80
local HISTORY_LIFETIME = 60
local SHARE_REQUIREMENTS = { prerequisite_all = true, prerequisite_any = true, active_parent = true,
	starting_with = true, until_completed = true, disabled_by = true, exclusive = true, replacement = true }
local function CapabilityText()
	return {
	provider_missing = L("Install QuestieDB to view related quests on this client."),
	provider_contract = L("QuestieDB needs a compatible public API contract."),
	provider_flavor = L("QuestieDB is not configured for this client."),
	provider_failed = L("QuestieDB could not load quest chain information."),
	client_unsupported = L("Quest chain information is unavailable on this client."),
	native_unavailable = L("Native quest chain information is unavailable."),
	index_loading = L("Loading quest chain information"),
	membership_only = L("Quest line order does not establish prerequisites."),
	}
end

local function Copy(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end
local function IDs(values)
	local ids = {}
	for id in pairs(values or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end
local function Current(addon, session, state)
	return addon.partyQuestCompareSession == session and session.chains == state and not state.retired
		and addon.isEnabled and not addon.isLoggingOut and (addon.db and addon.db.profile) == state.profile
end
local function ActiveUnion(session)
	local union = {}
	for _, member in ipairs(session.members or {}) do
		for id, entry in pairs(member.entries or {}) do
			if not union[id] or member.isLocal then union[id] = entry end
		end
	end
	return union
end
local function Fresh(addon, member, id)
	local evidence = member.questHistory and member.questHistory[id]
	local now = addon:GetPartyQuestCompareTime()
	return evidence and now >= evidence.sampledAt and now < evidence.sampledAt + HISTORY_LIFETIME and evidence or nil
end
local function Text(addon, value)
	return addon:NormalizeQuestDisplayTitleText(type(value) == "string" and value or "")
end
local function Resolve(state, id)
	local seen = {}
	while id and state.aliases[id] and not seen[id] do seen[id], id = true, state.aliases[id] end
	return id
end
local function HasRelatedQuests(graph, rootID)
	-- Loading, partial data or a native line ID alone do not establish another
	-- quest to show. A later provider snapshot can make this available.
	for id in pairs(graph and graph.nodes or {}) do if id ~= rootID then return true end end
	return false
end

function QT:AttachPartyQuestChains(session, previous)
	local old = previous and previous.chains
	local state = {
		owner = {}, profile = self.db and self.db.profile, serial = old and old.serial or 0,
		groups = {}, aliases = Copy(old and old.aliases), questGroups = Copy(old and old.questGroups),
		keyGroups = Copy(old and old.keyGroups), groupOrigins = Copy(old and old.groupOrigins), collapsed = Copy(old and old.collapsed),
		rootQuestID = old and old.rootQuestID, originRowId = old and old.originRowId,
		limit = old and old.limit or PAGE_SIZE, earlier = old and old.earlier or 39, later = old and old.later or 40, instance = (old and old.instance or 0) + 1,
		metadata = {}, metadataInterest = {}, graphs = {}, capability = { state = "loading" },
	}
	session.chains = state
	if self.RevalidateQuestChainProvider then
		self:RevalidateQuestChainProvider(state.owner, function()
			if Current(self, session, state) then self:QueuePartyQuestCompareRender() end
		end)
	end
	self:QueuePartyQuestChainRefresh()
	return state
end

function QT:CancelPartyQuestChains(session)
	local state = session and session.chains
	if not state then return end
	state.retired = true
	if self.HideQuestChainGiver then self:HideQuestChainGiver() end
	if self.CancelQuestChainProvider then self:CancelQuestChainProvider(state.owner) end
	if self.partyQuestCompareSession == session then
		self:SetPartyQuestCompletionInterest({}, "chain")
		self:SetPartyQuestCompletionInterest({}, "share")
	end
end

function QT:RetirePartyQuestChains()
	local session = self.partyQuestCompareSession
	self:CancelPartyQuestChains(session)
	for _, member in ipairs(session and session.members or {}) do self:CancelPartyQuestCompletionRequest(member) end
end

function QT:ResumePartyQuestChains()
	local session, frame = rawget(self, "partyQuestCompareSession"), rawget(self, "partyQuestCompareWindow")
	if not session or not session.chains or not session.chains.retired or not frame or not self.isEnabled then return false end
	local ok, shown = pcall(frame.IsShown, frame)
	if not ok or shown ~= true then return false end
	self:ScheduleDeferredWork("quest_snapshot_refresh", "party_compare_chain_resume", function()
		if self.partyQuestCompareSession == session and not self.isLoggingOut and self.isEnabled then
			self:RefreshPartyQuestCompare(nil, session.targetName, true)
		end
	end, 0, "party compare world resume")
	return true
end

function QT:SetPartyQuestChainMetadataInterest(state, ids)
	local interested, changed = {}, false
	for _, id in ipairs(ids or {}) do
		interested[id] = true
		if not (state.metadataInterest and state.metadataInterest[id]) then changed = true end
	end
	for id in pairs(state.metadataInterest or {}) do if not interested[id] then changed = true; break end end
	if changed then state.metadataGeneration = (state.metadataGeneration or 0) + 1 end
	state.metadataInterest = interested
	if self.SetQuestChainMetadataInterest then self:SetQuestChainMetadataInterest(ids or {}, state.owner) end
end

local function RetireMetadataContext(addon, session)
	local state = session.chains
	if not state then return end
	local roots = (state.capability.kind == "retail" or state.capability.kind == "questiedb")
		and (state.capability.state == "ready" or state.capability.state == "loading") and IDs(ActiveUnion(session)) or {}
	addon:SetPartyQuestChainMetadataInterest(state, roots)
end

local function RetireVisibleContext(addon, session)
	if addon.HideQuestChainGiver then addon:HideQuestChainGiver() end
	RetireMetadataContext(addon, session)
	local union, retained = ActiveUnion(session), {}
	for _, id in ipairs(session.historyInterestOwners and session.historyInterestOwners.visible or {}) do
		if union[id] then retained[#retained + 1] = id end
	end
	addon:SetPartyQuestCompletionInterest(retained)
end

function QT:SetPartyQuestChainSelection(row)
	local state = self.partyQuestCompareSession and self.partyQuestCompareSession.chains
	if not state or not row or (row.kind ~= "chainStep" and not row.chainAnchor)
		or row.chainInstanceId ~= "chain:" .. state.instance then return false end
	if state.selectedQuestID ~= row.questId then
		state.selectedQuestID = row.questId
		self:QueuePartyQuestChainRefresh()
	end
	return true
end

function QT:QueuePartyQuestChainRefresh()
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	if not state or state.pending or not Current(self, session, state) then return end
	state.pending = true
	self:ScheduleDeferredWork("quest_snapshot_refresh", "party_compare_chains", function()
		state.pending = nil
		if Current(self, session, state) then self:PreparePartyQuestChains(session, state) end
	end, 0, "party compare chains")
end

local function AssignGroup(state, graph, rootID)
	local candidates = {}
	local function Candidate(id, sameKey)
		id = Resolve(state, id)
		if id and (sameKey or (graph.nodes or {})[state.groupOrigins[id]]) then candidates[id] = true end
	end
	Candidate(state.keyGroups[graph.key], true)
	Candidate(state.questGroups[rootID])
	for id in pairs(graph.nodes or {}) do Candidate(state.questGroups[id]) end
	local candidateIDs = IDs(candidates)
	local groupID = candidateIDs[1]
	if not groupID then state.serial = state.serial + 1; groupID = state.serial; state.groupOrigins[groupID] = rootID end
	for _, id in ipairs(candidateIDs) do
		if id ~= groupID then
			state.aliases[id] = groupID
			if state.collapsed[id] == false then state.collapsed[groupID] = false end
		end
	end
	state.keyGroups[graph.key or ("quest:" .. rootID)] = groupID
	state.questGroups[rootID] = groupID
	for id in pairs(graph.nodes or {}) do state.questGroups[id] = groupID end
	return groupID
end

local function SharedBranch(a, b)
	while a.depth > b.depth do a = a.parent end
	while b.depth > a.depth do b = b.parent end
	while a ~= b do a, b = a.parent, b.parent end
	return a
end

local function BranchDepths(graph)
	local depths, incoming, outgoing, connections, queue = {}, {}, {}, {}, {}
	local count = 0
	for id in pairs(graph.nodes or {}) do
		depths[id], incoming[id], outgoing[id], connections[id] = 0, 0, {}, {}
		count = count + 1
	end
	-- Native membership establishes no prerequisite shape. Cyclic data has no
	-- reliable branch nesting, so retain its logical order without indentation.
	if graph.membershipOnly or graph.cycle then return depths end
	for _, edge in ipairs(graph.edges or {}) do
		if incoming[edge.from] and incoming[edge.to] and not edge.negative
			and (edge.kind == "prerequisite_all" or edge.kind == "prerequisite_any" or edge.kind == "unlock") then
			-- Provider fields can describe the same connection more than once.
			if not connections[edge.from][edge.to] then
				connections[edge.from][edge.to] = true
				outgoing[edge.from][#outgoing[edge.from] + 1] = edge.to
				incoming[edge.to] = incoming[edge.to] + 1
			end
		end
	end
	for _, id in ipairs(IDs(incoming)) do if incoming[id] == 0 then queue[#queue + 1] = id end end
	local cursor, rank = 1, {}
	while cursor <= #queue do
		local id = queue[cursor]; rank[id], cursor = cursor, cursor + 1
		for _, nextID in ipairs(outgoing[id]) do
			incoming[nextID] = incoming[nextID] - 1
			if incoming[nextID] == 0 then queue[#queue + 1] = nextID end
		end
	end
	if #queue < count then return depths end
	-- Redundant ancestor prerequisites are shortcuts, not additional arms. This
	-- affects presentation only; the original relationships and order stay intact.
	for _, id in ipairs(queue) do
		local successors = outgoing[id]
		if #successors > 1 then
			table.sort(successors, function(a, b) return rank[a] < rank[b] end)
			local lastRank, retained, reachable = rank[successors[#successors]], {}, {}
			for _, nextID in ipairs(successors) do
				if not reachable[nextID] then
					retained[#retained + 1], reachable[nextID] = nextID, true
					local pending, nextIndex = { nextID }, 1
					while nextIndex <= #pending do
						local current = pending[nextIndex]; nextIndex = nextIndex + 1
						for _, descendant in ipairs(outgoing[current]) do
							if rank[descendant] <= lastRank and not reachable[descendant] then
								reachable[descendant], pending[#pending + 1] = true, descendant
							end
						end
					end
				end
			end
			outgoing[id] = retained
		end
	end
	local root, branches = { depth = 0 }, {}
	for _, id in ipairs(queue) do
		branches[id] = branches[id] or root
		local branch = branches[id]
		depths[id] = branch.depth
		for _, nextID in ipairs(outgoing[id]) do
			-- Linear steps share a context. Only an actual fork opens new levels;
			-- convergence returns to the common context of its incoming arms.
			local nextBranch = #outgoing[id] > 1 and { parent = branch, depth = branch.depth + 1 } or branch
			branches[nextID] = branches[nextID] and SharedBranch(branches[nextID], nextBranch) or nextBranch
		end
	end
	return depths
end

function QT:GetPartyQuestChainCharacterEvidence(member)
	local fallback = { classFile = member.classFile }
	local getter = self.API.GetQuestChainUnitInfo
	if type(getter) ~= "function" then return fallback end
	if member.isLocal then
		local ok, info = pcall(getter, "player")
		return ok and type(info) == "table" and info or fallback
	end
	if not self:IsGroupedSender(member.name) then return fallback end
	local units = {}
	local roster = self.partyMembers and self.partyMembers[member.name]
	if roster and type(roster.unit) == "string" then units[#units + 1] = roster.unit end
	local raid = self.API.IsInRaid and self.API.IsInRaid() == true
	for index = 1, raid and 40 or 4 do units[#units + 1] = (raid and "raid" or "party") .. index end
	for _, unit in ipairs(units) do
		local beforeOK, before = pcall(self.GetUnitFullName, self, unit)
		if beforeOK and before == member.name then
			local ok, info = pcall(getter, unit)
			local afterOK, after = pcall(self.GetUnitFullName, self, unit)
			local session = self.partyQuestCompareSession
			if ok and type(info) == "table" and afterOK and after == before
				and session and session.byName[member.name] == member and self:IsGroupedSender(member.name) then
				return info
			end
			return fallback
		end
	end
	return fallback
end

-- Only explicit provider relationships participate in preflight. Chain order
-- does not establish prerequisites, and repeatability says nothing about an
-- earlier completion of a prerequisite.
function QT:PreparePartyQuestShareRequirements(member, questID, character, readLocal)
	local snapshot, now = self.questChainProviderSnapshot, self:GetPartyQuestCompareTime()
	local dependencies, evidence, histories = {}, {}, {}
	for _, edge in ipairs(snapshot and snapshot.relations and snapshot.relations[questID] or {}) do
		if SHARE_REQUIREMENTS[edge.kind] and edge.relatedQuestID then dependencies[edge.relatedQuestID] = true end
	end
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	for _, edge in ipairs(state and state.relationshipsByQuest and state.relationshipsByQuest[questID] or {}) do
		if SHARE_REQUIREMENTS[edge.kind] and edge.relatedQuestID then dependencies[edge.relatedQuestID] = true end
	end
	local expiresAt, reads = now + HISTORY_LIFETIME, 0
	local snapshotFresh = member.sampledAt and now >= member.sampledAt and now < member.sampledAt + HISTORY_LIFETIME
	for _, id in ipairs(IDs(dependencies)) do
		local previous = member.questHistory and member.questHistory[id]
		histories[id] = previous or false
		local history = member.state == "ready" and Fresh(self, member, id) or nil
		if readLocal and member.isLocal then
			-- An explicit activation rechecks a bounded set of local dependencies.
			-- Overflow stays unknown instead of authorizing or vetoing from old data.
			reads = reads + 1
			history = reads <= 32 and { status = self:ReadCharacterQuestHistoryStatus(id), sampledAt = now } or nil
			if history and not member.entries[id] and session and session.historyInterests and session.historyInterests[id] then
				member.questHistory = member.questHistory or {}
				member.questHistory[id], histories[id] = history, history
			end
		end
		local value = {}
		if member.state == "ready" then
			if history and history.status == "active" then value.active = true
			elseif history and (history.status == "completed" or history.status == "incomplete" or history.status == "repeatable") then
				value.active = false
			elseif snapshotFresh then
				value.active = member.entries and member.entries[id] ~= nil or false
				expiresAt = math.min(expiresAt, member.sampledAt + HISTORY_LIFETIME)
			end
		end
		if history then
			expiresAt = math.min(expiresAt, history.sampledAt + HISTORY_LIFETIME)
			if history.status == "completed" then value.completed = true
			elseif history.status == "incomplete" then value.completed = false end
		end
		evidence[id] = value
	end
	local result = self.EvaluateQuestChainRequirements and self:EvaluateQuestChainRequirements(questID, evidence, character)
		or { state = "unknown", requirements = {}, blockers = {}, groups = {} }
	result.certificate = { member = member, entries = member.entries, state = member.state,
		snapshotSampledAt = member.sampledAt,
		historyGeneration = member.historyGeneration or 0, provider = snapshot, histories = histories,
		providerGeneration = snapshot and snapshot.generation, providerRevision = snapshot and snapshot.revision,
		sampledAt = now, expiresAt = expiresAt }
	return result
end

function QT:RefreshPartyQuestShareRequirements(member, questID, readLocal)
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	if not state or not Current(self, session, state) or session.byName[member.name] ~= member
		or self:IsWorkBlocked("quest_snapshot_refresh") then return end
	state.shareRequirements = state.shareRequirements or {}
	state.shareRequirements[questID] = state.shareRequirements[questID] or {}
	state.shareRequirements[questID][member.name] = self:PreparePartyQuestShareRequirements(member, questID,
		self:GetPartyQuestChainCharacterEvidence(member), readLocal)
end

function QT:PreparePartyQuestChains(session, state)
	if not Current(self, session, state) then return end
	local capability = self.GetQuestChainProviderCapability and self:GetQuestChainProviderCapability()
		or { state = "unavailable", reason = "provider_unavailable" }
	capability = Copy(capability)
	capability.explanation = CapabilityText()[capability.reason] or L("Quest chain information is unavailable.")
	local generation = capability.generation
	if state.providerGeneration ~= generation then
		state.providerGeneration = generation
		state.historyGeneration = (state.historyGeneration or 0) + 1
		for _, member in ipairs(session.members) do self:CancelPartyQuestCompletionRequest(member) end
	end
	local union, roots, graphs, groups, metadata = ActiveUnion(session), {}, {}, {}, {}
	local metadataIDs, metadataWanted = {}, {}
	local function DemandMetadata(id)
		if id and not metadataWanted[id] then metadataWanted[id], metadataIDs[#metadataIDs + 1] = true, id end
	end
	local openGroup = state.rootQuestID and Resolve(state, state.questGroups[state.rootQuestID])
	local contextWanted = state.rootQuestID and (capability.state == "ready" or capability.state == "loading")
		and (capability.kind == "questiedb" or capability.kind == "retail")
		and not (self:GetOption("compareGroupByChain") == true and state.collapsed[openGroup])
	if contextWanted then DemandMetadata(state.selectedQuestID or state.rootQuestID) end
	for id in pairs(union) do roots[id] = true end
	if state.rootQuestID then roots[state.rootQuestID] = true end
	for _, id in ipairs(IDs(roots)) do
		local ok, graph = false, nil
		if self.GetQuestChainGraph and capability.state ~= "unavailable" and capability.state ~= "failed" then
			ok, graph = pcall(self.GetQuestChainGraph, self, id, {
				limit = state.rootQuestID == id and state.limit or PAGE_SIZE,
				earlier = state.rootQuestID == id and state.earlier or nil,
				later = state.rootQuestID == id and state.later or nil,
			})
		end
		if ok and type(graph) == "table" then
			graphs[id] = graph
			if HasRelatedQuests(graph, id) then
				local groupID = AssignGroup(state, graph, id)
				groups[groupID] = graph
			else state.questGroups[id] = nil end
			for nodeID in pairs(graph.nodes or {}) do
				local info = self.GetQuestChainQuestInfo and self:GetQuestChainQuestInfo(nodeID)
				metadata[nodeID] = info and Copy(info) or {}
				if (contextWanted and state.rootQuestID == id) or nodeID == id then
					DemandMetadata(nodeID)
				end
			end
		else state.questGroups[id] = nil end
	end
	local canonicalGroups = {}
	for id, value in pairs(groups) do canonicalGroups[Resolve(state, id)] = value end
	groups = canonicalGroups
	-- Publish a complete presentation snapshot before any asynchronous metadata callback.
	state.capability, state.graphs, state.groups, state.metadata, state.union = capability, graphs, groups, metadata, union
	state.sourceEntries, state.sourceStates = {}, {}
	for i, member in ipairs(session.members) do state.sourceEntries[i], state.sourceStates[i] = member.entries, member.state end
	state.providerRevision = self.questChainProviderSnapshot and self.questChainProviderSnapshot.revision
	local graph = contextWanted and graphs[state.rootQuestID]
	state.depths = graph and BranchDepths(graph) or {}
	state.required, state.relationshipsByQuest = {}, {}
	local indexedGraphs, indexedEdges = {}, {}
	for _, candidate in pairs(graphs) do
		if not indexedGraphs[candidate] then
			indexedGraphs[candidate] = true
			for _, edge in ipairs(candidate.edges or {}) do
				if not indexedEdges[edge] then
					indexedEdges[edge] = true
					local questID = edge.questID
					if questID then
						local bucket = state.relationshipsByQuest[questID] or {}
						state.relationshipsByQuest[questID] = bucket
						bucket[#bucket + 1] = { kind = edge.kind, relatedQuestID = edge.relatedQuestID }
					end
				end
			end
		end
	end
	state.shareRootDependencies = {}
	for id in pairs(union) do
		for _, edge in ipairs(state.relationshipsByQuest[id] or {}) do
			if SHARE_REQUIREMENTS[edge.kind] and edge.relatedQuestID then state.shareRootDependencies[edge.relatedQuestID] = true end
		end
	end
	if graph then
		local queue = {}
		for id in pairs(union) do if graph.nodes[id] then state.required[id], queue[#queue + 1] = true, id end end
		local incoming = {}
		for _, edge in ipairs(graph.edges or {}) do
			if edge.kind == "prerequisite_all" or edge.kind == "prerequisite_any" then
				incoming[edge.to] = incoming[edge.to] or {}
				incoming[edge.to][#incoming[edge.to] + 1] = edge.from
			end
		end
		local cursor = 1
		while cursor <= #queue do
			local id = queue[cursor]; cursor = cursor + 1
			for _, prerequisite in ipairs(incoming[id] or {}) do
				if not state.required[prerequisite] then state.required[prerequisite], queue[#queue + 1] = true, prerequisite end
			end
		end
	end
	local interests, seen = {}, {}
	local function Add(id) if id and not seen[id] then seen[id], interests[#interests + 1] = true, id end end
	if graph then
		Add(state.selectedQuestID or state.rootQuestID)
		for _, id in ipairs(IDs(state.required)) do Add(id) end
		for _, edge in ipairs(graph.edges or {}) do Add(edge.relatedQuestID) end
		for _, id in ipairs(graph.order or IDs(graph.nodes)) do Add(id) end
	end
	for _, id in ipairs(interests) do
		DemandMetadata(id)
		if not metadata[id] then
			local info = self.GetQuestChainQuestInfo and self:GetQuestChainQuestInfo(id)
			metadata[id] = info and Copy(info) or {}
		end
	end
	self:SetPartyQuestCompletionInterest(interests, "chain")
	-- Visible ordinary rows need the same explicit prerequisite evidence as an
	-- expanded chain. Share and chain context use one bounded history budget.
	local shareInterest, shareSeen = {}, {}
	for _, id in ipairs(session.historyInterestOwners and session.historyInterestOwners.visible or {}) do
		if union[id] then
			for _, edge in ipairs(state.relationshipsByQuest[id] or {}) do
				if SHARE_REQUIREMENTS[edge.kind] and edge.relatedQuestID and not shareSeen[edge.relatedQuestID] and #shareInterest < 100 then
					shareSeen[edge.relatedQuestID], shareInterest[#shareInterest + 1] = true, edge.relatedQuestID
				end
			end
		end
	end
	self:SetPartyQuestCompletionInterest(shareInterest, "share")
	state.locations, state.locationReasons = {}, {}
	local mapGetter = self.API.GetQuestChainCurrentMapID or self.API.GetPlayerMapID or self.API.GetBestMapForUnit
	local currentMap = mapGetter and mapGetter("player")
	for _, id in ipairs(interests) do
		if self.GetQuestChainStarterLocations then
			local locations, reason = self:GetQuestChainStarterLocations(id, currentMap)
			state.locations[id], state.locationReasons[id] = locations or {}, reason
		end
	end
	-- This evaluates only cached relationship and evidence data. It never certifies availability.
	state.requirements, state.shareRequirements, state.revealBlockers = {}, {}, {}
	if self.EvaluateQuestChainRequirements then
		local evaluated = Copy(union)
		for id in pairs(graph and graph.nodes or {}) do evaluated[id] = true end
		for i, member in ipairs(session.members) do
			local character = self:GetPartyQuestChainCharacterEvidence(member)
			for _, id in ipairs(IDs(evaluated)) do
				state.requirements[id] = state.requirements[id] or {}
				state.shareRequirements[id] = state.shareRequirements[id] or {}
				local result = self:PreparePartyQuestShareRequirements(member, id, character)
				state.requirements[id][i] = result
				state.shareRequirements[id][member.name] = result
				if union[id] and result.state == "blocked" then
					for _, blocker in ipairs(result.blockers or {}) do
						if blocker.questID and (blocker.kind == "prerequisite_all" or
							(blocker.kind == "prerequisite_any" and result.groups and result.groups.any == "blocked")) then
							state.revealBlockers[blocker.questID] = true
						end
					end
				end
			end
		end
	end
	local presentationIDs, presentationSeen = {}, {}
	for id in pairs(union) do presentationIDs[#presentationIDs + 1], presentationSeen[id] = id, true end
	for _, id in ipairs(interests) do
		if not presentationSeen[id] then presentationIDs[#presentationIDs + 1], presentationSeen[id] = id, true end
	end
	self:PreparePartyQuestPresentation(session, presentationIDs, metadata)
	self:SetPartyQuestChainMetadataInterest(state, metadataIDs)
	if #metadataIDs > 0 and self.RequestQuestChainMetadata then
		local instance, metadataGeneration = state.instance, state.metadataGeneration
		-- The provider deduplicates queued and cached IDs. Re-submitting current
		-- demand also restores nodes whose unread work was pruned on collapse.
		self:RequestQuestChainMetadata(metadataIDs, state.owner, function()
			if Current(self, session, state) and state.instance == instance and state.providerGeneration == generation
				and state.metadataGeneration == metadataGeneration then
				self:QueuePartyQuestCompareRender()
			end
		end)
	end
	-- Queue a paint directly: calling QueuePartyQuestCompareRender here would continually reschedule preparation.
	self:ScheduleDeferredWork("foreign_frame_mutation", "party_compare_render", function()
		if Current(self, session, state) then self:RenderPartyQuestCompare() end
	end, 0.05, "party compare chain render")
end

function QT:OpenPartyQuestChain(questID, originRowId)
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	questID = self:NormalizeQuestID(questID)
	if not state or not questID or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	RetireVisibleContext(self, session)
	if type(originRowId) == "string" and originRowId:match("^chain:") then originRowId = state.originRowId end
	state.rootQuestID, state.originRowId, state.selectedQuestID = questID, originRowId or ("quest:" .. questID), questID
	state.instance, state.limit, state.earlier, state.later, state.historyGeneration = state.instance + 1, PAGE_SIZE, 39, 40, (state.historyGeneration or 0) + 1
	local groupID = Resolve(state, state.questGroups[questID])
	if groupID then state.collapsed[groupID] = false end
	for _, member in ipairs(session.members) do self:CancelPartyQuestCompletionRequest(member) end
	self:QueuePartyQuestChainRefresh()
	self:QueuePartyQuestCompareRender()
	return true
end

function QT:TogglePartyQuestChain(questID, originRowId)
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	questID = self:NormalizeQuestID(questID)
	if not state or not questID or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	if state.rootQuestID == questID then return self:ClosePartyQuestChain() end
	return self:OpenPartyQuestChain(questID, originRowId)
end

function QT:ClosePartyQuestChain()
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	if not state or not state.rootQuestID then return false end
	local origin = state.originRowId
	state.rootQuestID, state.originRowId, state.selectedQuestID = nil, nil, nil
	state.instance, state.historyGeneration = state.instance + 1, (state.historyGeneration or 0) + 1
	for _, member in ipairs(session.members) do self:CancelPartyQuestCompletionRequest(member) end
	self:SetPartyQuestCompletionInterest({}, "chain")
	RetireVisibleContext(self, session)
	self:QueuePartyQuestCompareRender()
	return true, self:ResolvePartyQuestChainRowID(origin)
end

function QT:TogglePartyQuestChainGroup(groupID)
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	groupID = state and Resolve(state, groupID)
	if not groupID then return false end
	state.collapsed[groupID] = not state.collapsed[groupID]
	if state.collapsed[groupID] and state.rootQuestID and Resolve(state, state.questGroups[state.rootQuestID]) == groupID then
		RetireMetadataContext(self, session)
		self:SetPartyQuestCompletionInterest({}, "chain")
		RetireVisibleContext(self, session)
	end
	self:QueuePartyQuestCompareRender()
	return true
end

function QT:ExpandPartyQuestChain(direction)
	local state = self.partyQuestCompareSession and self.partyQuestCompareSession.chains
	if not state or not state.rootQuestID then return false end
	state.limit = state.limit + PAGE_SIZE
	if direction == "earlier" then state.earlier = state.earlier + PAGE_SIZE else state.later = state.later + PAGE_SIZE end
	state.expandDirection = direction
	self:QueuePartyQuestCompareRender()
	return true
end

function QT:ResolvePartyQuestChainRowID(rowID)
	local state = self.partyQuestCompareSession and self.partyQuestCompareSession.chains
	if state and type(rowID) == "string" then
		local id = rowID:match("^chainGroup:(%d+)$")
		if id then return "chainGroup:" .. Resolve(state, tonumber(id)) end
	end
	return rowID
end

function QT:GetPartyQuestChainDisplayTitle(id)
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	if not state then return L("Quest ") .. id, false end
	local own = session.byName[session.playerName]
	local history = own and Fresh(self, own, id)
	local visible = self:GetOption("compareHideFutureQuestNames") ~= true or state.union[id] ~= nil
		or (history and history.status == "completed") or (state.revealBlockers and state.revealBlockers[id] == true)
	if not visible then return L("Future quest"), true end
	local entry, info = state.union[id], state.metadata[id]
	local title = Text(self, entry and entry.questTitle or info and (info.title or info.name))
	return title ~= "" and title or (L("Quest ") .. id), false
end

function QT:GetPartyQuestChainStatus(member, id)
	local active = member.entries[id]
	if active then return active.isComplete and "Ready" or "Have" end
	local status = self:GetPartyQuestAbsenceState(member, id)
	if status == "Missing" then return "Absent" end
	return status
end

local function RequirementLabel(addon, requirement)
	local kind, title = requirement.kind, requirement.questID and addon:GetPartyQuestChainDisplayTitle(requirement.questID)
	if requirement.negative then return L("Signed prerequisite semantics unknown") end
	if kind == "prerequisite_all" then return string.format(L("Requires completed quest: %s"), title)
	elseif kind == "prerequisite_any" then return string.format(L("One of these quests must be completed: %s"), title)
	elseif kind == "active_parent" then return string.format(L("Requires active quest: %s"), title)
	elseif kind == "starting_with" then return string.format(L("Requires active or completed quest: %s"), title)
	elseif kind == "until_completed" then return string.format(L("Available until quest completed: %s"), title)
	elseif kind == "disabled_by" then return string.format(L("Unavailable while quest active: %s"), title)
	elseif kind == "exclusive" then return string.format(L("Exclusive quest: %s"), title)
	elseif kind == "replacement" then return string.format(L("Replacement quest: %s"), title)
	elseif kind == "level" then return string.format(L("Requires level %d"), requirement.value)
	elseif kind == "max_level" then return string.format(L("Maximum level: %d"), requirement.value)
	elseif kind == "class" then return requirement.state == "blocked" and L("Different class") or L("Class requirement")
	elseif kind == "race" then return requirement.state == "blocked" and L("Different race") or L("Race requirement")
	elseif kind == "requiredSkill" then return L("Skill requirement")
	elseif kind == "requiredMinRep" then return L("Minimum reputation requirement")
	elseif kind == "requiredMaxRep" then return L("Maximum reputation requirement")
	elseif kind == "requiredRanks" then return L("Rank requirement")
	elseif kind == "requiredSourceItems" then return L("Required starting items")
	elseif kind == "requiredSpell" then return L("Spell requirement")
	elseif kind == "requiredSpecialization" then return L("Specialization requirement") end
	return L("Additional requirement")
end

function QT:DescribePartyQuestChainRequirements(result)
	if not result then return L("Prerequisites unknown") end
	local summary = result.state == "met" and L("Known prerequisites met")
		or result.state == "blocked" and L("Prerequisites not met") or L("Prerequisites unknown")
	local parts = { summary }
	for _, requirement in ipairs(result.requirements or {}) do
		local label = RequirementLabel(self, requirement)
		if requirement.allowedNames and #requirement.allowedNames > 0 then
			local names = {}; for _, name in ipairs(requirement.allowedNames) do names[#names + 1] = Text(self, name) end
			label = label .. ": " .. table.concat(names, ", ")
		end
		local status = requirement.state == "met" and L("Satisfied")
			or requirement.state == "blocked" and L("Not met") or L("Not evaluated")
		parts[#parts + 1] = label .. " — " .. status
	end
	-- Some clients expose only blockers. Keep their necessary explanation while
	-- never making absence from the database a proof of complete availability.
	if #(result.requirements or {}) == 0 and result.state == "blocked" then
		for _, blocker in ipairs(result.blockers or {}) do parts[#parts + 1] = RequirementLabel(self, blocker) end
	end
	parts[#parts + 1] = L("Other availability conditions may apply.")
	return table.concat(parts, "\n")
end

local function RelationshipLabel(kind)
	if kind == "breadcrumb" then return L("Breadcrumb quest")
	elseif kind == "breadcrumb_for" then return L("Breadcrumb quest")
	elseif kind == "replacement" then return L("Replacement quest")
	elseif kind == "exclusive" then return L("Exclusive quest")
	elseif kind == "active_parent" then return L("Active parent quest")
	elseif kind == "starting_with" then return L("Available starting with quest")
	elseif kind == "until_completed" then return L("Available until quest completed")
	elseif kind == "disabled_by" then return L("Disabled by active quest")
	elseif kind == "unlock" then return L("Unlock connection") end
end

local function NeedsQuestRequirements(status)
	return status ~= "Have" and status ~= "Ready" and status ~= "Completed"
end

function QT:AppendPartyQuestChainSection(rows, rootRows, anchor, append)
	local session, state = self.partyQuestCompareSession, self.partyQuestCompareSession.chains
	if not state.rootQuestID then return end
	local graph = state.graphs[state.rootQuestID]
	local instance = "chain:" .. state.instance
	local anchored = false
	local function AppendAnchor(context)
		if not anchor or anchored then return end
		anchored = true
		anchor.chainInstanceId, anchor.chainId, anchor.chainAnchor = instance, instance, true
		anchor.depth, anchor.spoilerHidden = math.min(12, state.depths and state.depths[anchor.questId] or 0), false
		if context then
			anchor.requirements, anchor.memberPrerequisiteText = context.requirements, context.memberPrerequisiteText
			anchor.relationshipText = context.relationshipText
		end
		local first = #rows + 1
		append(rows, anchor)
		-- The retained ordinary row owns its usual objective descendants. Keep
		-- them inside this section without changing their parent or row IDs.
		for index = first, #rows do rows[index].chainInstanceId = instance end
	end
	local function Notice(key, title)
		rows[#rows + 1] = { rowId = instance .. ":" .. key, kind = "chainNotice", title = title, cells = {}, chainInstanceId = instance }
	end
	if not graph then
		AppendAnchor()
		Notice("state", state.capability.state == "loading" and L("Loading") or state.capability.explanation or L("Quest chain information is unavailable."))
		return
	end
	local order = graph.order or IDs(graph.nodes)
	local hasAnchor = false
	for _, id in ipairs(order) do if anchor and id == anchor.questId then hasAnchor = true; break end end
	-- A partial provider snapshot can omit the origin. Keep its ordinary row
	-- first in that case rather than inventing a position among known steps.
	if not hasAnchor then AppendAnchor() end
	if graph.loading then Notice("loading", L("Loading quest chain information")) end
	if graph.membershipOnly then Notice("membership", L("Quest line order does not establish prerequisites.")) end
	if graph.partial then Notice("partial", L("Partial quest chain information")) end
	if graph.cycle then Notice("cycle", L("Quest relationships contain a cycle.")) end
	if graph.reasons and graph.reasons.missing then Notice("missing", L("Some referenced quests are unavailable.")) end
	local frontier = graph.frontier or {}
	local function More(direction)
		if (type(frontier[direction]) == "table" and #frontier[direction] > 0)
			or (type(frontier[direction]) == "number" and frontier[direction] > 0) then
			rows[#rows + 1] = {
				rowId = instance .. ":more:" .. direction, kind = "chainMore", selectable = true, cells = {},
				chainInstanceId = instance, chainId = instance, direction = direction,
				title = direction == "earlier" and L("Show earlier quests") or L("Show later quests"),
			}
		end
	end
	More("earlier")
	local own = session.byName[session.playerName]
	local completed, completionKnown = 0, true
	for _, id in ipairs(order) do
		local title, hidden = self:GetPartyQuestChainDisplayTitle(id)
		local row = Copy(rootRows[id])
		row.rowId, row.kind, row.questId, row.title = instance .. ":quest:" .. id, "chainStep", id, title
		local presentation = session.questPresentation and session.questPresentation[id]
		row.questLevel = presentation and presentation.questLevel
		row.questGroupRecommended = presentation and presentation.questGroupRecommended
		row.questDifficultyColor = presentation and presentation.questDifficultyColor
		row.chainInstanceId, row.chainId, row.selectable, row.spoilerHidden = instance, instance, true, hidden
		row.depth, row.cells, row.missing = math.min(12, state.depths[id] or 0), {}, 0
		row.requirements = state.requirements[id]
		for i, member in ipairs(session.members) do row.cells[i] = self:GetPartyQuestChainStatus(member, id) end
		row.memberPrerequisiteText = {}
		for i, status in ipairs(row.cells) do
			row.memberPrerequisiteText[i] = NeedsQuestRequirements(status)
				and self:DescribePartyQuestChainRequirements(row.requirements and row.requirements[i]) or ""
		end
		local relationships, seen = {}, {}
		for _, edge in ipairs(state.relationshipsByQuest and state.relationshipsByQuest[id] or {}) do
			local label = RelationshipLabel(edge.kind)
			local otherID = edge.relatedQuestID
			if label and otherID and not seen[edge.kind .. ":" .. otherID] then
				seen[edge.kind .. ":" .. otherID] = true
				relationships[#relationships + 1] = label .. ": " .. self:GetPartyQuestChainDisplayTitle(otherID)
			end
		end
		row.relationshipText = table.concat(relationships, "\n")
		row.prerequisiteText = nil
		if row.relationshipText ~= "" then
			for i, text in ipairs(row.memberPrerequisiteText) do
				if NeedsQuestRequirements(row.cells[i]) then row.memberPrerequisiteText[i] = text .. "\n" .. row.relationshipText end
			end
		end
		row.hint = graph.nodes[id] and graph.nodes[id].missing and L("Quest information unavailable") or nil
		local history = Fresh(self, own, id)
		if history and history.status == "completed" then completed = completed + 1
		elseif not own.entries[id] and not (history and (history.status == "incomplete" or history.status == "repeatable")) then
			completionKnown = false
		end
		if anchor and id == anchor.questId then AppendAnchor(row)
		else rows[#rows + 1] = row end
	end
	if graph.completeLinearPath == true and completionKnown and not graph.partial and not graph.loading and #order > 0 then
		Notice("progress", string.format(L("%d/%d completed"), completed, #order))
	end
	More("later")
end

-- Layout consumes only this prepared session snapshot. It neither reads the provider nor sends requests.
function QT:DecoratePartyQuestChainRows(quests, append)
	local session, rows = self.partyQuestCompareSession, {}
	local state = session and session.chains
	local function ScopeRows(first, groupID)
		for index = first, #rows do
			local row = rows[index]
			row.chainGroupId, row.chainGroupMember, row.chainGroupEnd = groupID, groupID and true or nil, nil
		end
	end
	if not state then
		for _, row in ipairs(quests) do append(rows, row) end
		ScopeRows(1)
		return rows
	end
	local groupByChain = self:GetOption("compareGroupByChain") == true
	local openGroup = state.rootQuestID and Resolve(state, state.questGroups[state.rootQuestID])
	local rootRows, groups, ordered = {}, {}, {}
	for _, row in ipairs(session.unfilteredQuests or quests) do
		rootRows[row.questId] = row
		-- Callers can reuse roots across paints, filters and chain replacement.
		row.chainInstanceId, row.chainId, row.chainAnchor, row.depth, row.spoilerHidden = nil, nil, nil, nil, nil
		row.requirements, row.memberPrerequisiteText, row.relationshipText = nil, nil, nil
	end
	for _, row in ipairs(quests) do
		row.rowId, row.selectable = "quest:" .. row.questId, true
		row.chainExpanded = state.rootQuestID == row.questId
		-- The same control remains available to close a section if its provider
		-- becomes unavailable while that section is open.
		row.chainAvailable = row.chainExpanded or ((state.capability.kind == "questiedb" or state.capability.kind == "retail")
			and (state.capability.state == "ready" or state.capability.state == "loading")
			and HasRelatedQuests(state.graphs[row.questId], row.questId))
		row.chainCapability = state.capability
		local groupID = groupByChain and Resolve(state, state.questGroups[row.questId])
		if groupID then
			if not groups[groupID] then groups[groupID] = {}; ordered[#ordered + 1] = groupID end
			groups[groupID][#groups[groupID] + 1] = row
		else ordered[#ordered + 1] = row end
	end
	local inserted = false
	local function AppendRoot(row)
		local first = #rows + 1
		if row.questId == state.rootQuestID then
			self:AppendPartyQuestChainSection(rows, rootRows, row, append); inserted = true
		else append(rows, row) end
		ScopeRows(first)
	end
	for _, item in ipairs(ordered) do
		if type(item) == "table" then AppendRoot(item)
		else
			local members = groups[item]
			local graph = state.groups[item]
			local title = graph and graph.providerKind == "retail" and Text(self, graph.title or graph.name) or ""
			if title == "" then title = L("Related quests") .. " · " .. members[1].title end
			local total = 0
			for id in pairs(rootRows) do if Resolve(state, state.questGroups[id]) == item then total = total + 1 end end
			rows[#rows + 1] = {
				rowId = "chainGroup:" .. item, kind = "chainGroup", groupId = item, selectable = true, cells = {},
				chainGroupId = item,
				title = title, expanded = not state.collapsed[item],
				hint = total > #members and string.format(L("%d quests hidden by filters"), total - #members) or nil,
			}
			if not state.collapsed[item] then
				local first = #rows + 1
				for _, row in ipairs(members) do AppendRoot(row) end
				-- A filtered origin still belongs inside its visible group, before
				-- unrelated roots that happen to follow that group in the list.
				if not inserted and state.rootQuestID and openGroup == item then
					self:AppendPartyQuestChainSection(rows, rootRows); inserted = true
				end
				ScopeRows(first, item)
			end
			rows[#rows].chainGroupEnd = true
		end
	end
	-- Filtering active roots never lets hidden future names cause a match. Keep an opened
	-- section only when its active group still has a matching root.
	if not groupByChain and not inserted and state.rootQuestID then
		for _, row in ipairs(quests) do
			if openGroup and Resolve(state, state.questGroups[row.questId]) == openGroup and not state.collapsed[openGroup] then
				local first = #rows + 1
				self:AppendPartyQuestChainSection(rows, rootRows); ScopeRows(first); break
			end
		end
	end
	state.presentedRows = {}
	for _, row in ipairs(rows) do state.presentedRows[row.rowId] = row end
	return rows
end

function QT:GetPartyQuestChainActions(row, memberName)
	local session = self.partyQuestCompareSession
	local state = session and session.chains
	if not state or not row or not row.questId then return {} end
	local instance, generation, revision, id = state.instance, state.providerGeneration, state.providerRevision, row.questId
	local conceal = self:GetOption("compareHideFutureQuestNames")
	local member = memberName and session.byName[memberName]
	local function Valid()
		local displayed = state.presentedRows and state.presentedRows[row.rowId]
		local _, hiddenNow = self:GetPartyQuestChainDisplayTitle(id)
		if hiddenNow ~= row.spoilerHidden then return false end
		if not displayed or displayed.questId ~= id or displayed.spoilerHidden ~= row.spoilerHidden
			or displayed.action ~= row.action or displayed.owner ~= row.owner
			or self:GetOption("compareHideFutureQuestNames") ~= conceal then return false end
		for i, source in ipairs(session.members) do
			if source.entries ~= state.sourceEntries[i] or source.state ~= state.sourceStates[i] then return false end
		end
		return Current(self, session, state) and state.instance == instance and state.providerGeneration == generation
			and (not self.questChainProviderSnapshot or (self.questChainProviderSnapshot.generation == generation
				and self.questChainProviderSnapshot.revision == revision))
			and (not memberName or session.byName[memberName] == member)
			and not self:IsWorkBlocked("foreign_frame_mutation")
	end
	local actions = {}
	local function Add(label, action, disabled)
		actions[#actions + 1] = { label = label, title = row.title, disabled = disabled,
			action = function() if Valid() and not disabled then return action() end; return false end }
	end
	if row.kind ~= "chainStep" and not row.chainAnchor then return actions end
	local own = session.byName[session.playerName]
	if not row.chainAnchor and own and own.entries[id] then
		Add(L("Open in Quest Log"), function() return self:OpenPartyQuestJournal(id) end)
	end
	if state.union[id] then
		if not row.chainAnchor then Add(L("Expand or collapse quest"), function() return self:TogglePartyQuestObjectives(id) end) end
		local target = memberName or (own and own.entries[id] and session.playerName)
		if target and self.RequestPartyQuestFocus then
			Add(L("Focus quest"), function() return self:RequestPartyQuestFocus(target, id) end)
		end
	end
	if memberName and member and not member.isLocal and self.FollowPartyQuestFocus then
		Add(L("Follow quest focus"), function() return self:FollowPartyQuestFocus(memberName) end)
	end
	if not row.chainAnchor then
		if row.action == "share" then Add(L("Share"), function() return self:SharePartyDiffQuest(id) end)
		elseif row.action == "request" then Add(L("Request Share"), function() return self:RequestPartyQuestShare(id, row.owner) end) end
	end
	if row.spoilerHidden then return actions end
	if self.GetQuestDetailsAvailability and self.ShowQuestDetails then
		local available = self:GetQuestDetailsAvailability(id)
		Add(L("Quest Details"), function()
			return self:GetQuestDetailsAvailability(id) ~= nil and self:ShowQuestDetails(id, row.title) == true
		end, available == nil)
	end
	local locations = state.locations[id] or {}
	if #locations == 0 then
		Add(state.locationReasons[id] == "item_started" and L("This quest starts from an item.")
			or L("Quest giver location unavailable."), function() return false end, true)
	else
		for index, location in ipairs(locations) do
			local mapID, x, y = location.mapID or location.mapId, location.x, location.y
			if type(mapID) == "number" and mapID > 0 and type(x) == "number" and type(y) == "number"
				and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				local name = Text(self, location.name)
				local suffix = " · " .. (name ~= "" and name or tostring(index)) .. " (" .. mapID .. ")"
				Add(L("Find quest giver") .. suffix, function()
					return self.ShowQuestChainGiver and self:ShowQuestChainGiver(location, Valid) == true
				end, not self.ShowQuestChainGiver)
				Add(L("Set waypoint") .. suffix, function() return self:OpenPingWaypoint(mapID, x * 100, y * 100) end)
			end
		end
	end
	return actions
end

function QT:GetPartyQuestChainDiagnostics()
	local state = self.partyQuestCompareSession and self.partyQuestCompareSession.chains
	local result = { active = state ~= nil and state.retired ~= true, open = state and state.rootQuestID ~= nil or false,
		groups = 0, nodes = 0, contextInterests = 0, state = state and state.capability.state or "closed" }
	for _ in pairs(state and state.groups or {}) do result.groups = result.groups + 1 end
	local graph = state and state.rootQuestID and state.graphs[state.rootQuestID]
	for _ in pairs(graph and graph.nodes or {}) do result.nodes = result.nodes + 1 end
	for _ in pairs(self.partyQuestCompareSession and self.partyQuestCompareSession.historyContext or {}) do
		result.contextInterests = result.contextInterests + 1
	end
	result.groups, result.nodes = math.min(result.groups, 100000), math.min(result.nodes, 100000)
	result.partial, result.loading = graph and graph.partial == true or false, graph and graph.loading == true or false
	return result
end
