-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
-- Derived graph views consume published provider snapshots only. Membership,
-- active logs, completion evidence and prerequisite evaluation stay separate.
local QT = _G.QuestTogether
local function PositiveID(value)
	return type(value) == "number" and value > 0 and value <= 2147483647 and value == math.floor(value) and value
end
local function SortedKeys(values)
	local result = {}; for key in pairs(values or {}) do result[#result + 1] = key end
	table.sort(result); return result
end
local function NodeInfo(snapshot, id)
	local source, info = snapshot.nodes[id] or {}, snapshot.metadata[id] or {}
	local missing = source.missing or info.missing or (snapshot.kind == "questiedb" and snapshot.state == "ready" and not snapshot.nodes[id])
	return { questID = id, questId = id, title = info.title, missing = missing,
		invalid = source.invalid or info.invalid, conflicting = source.conflicting,
		loading = info.loading, metadataLoaded = snapshot.metadata[id] ~= nil }
end
local function NativeGraph(snapshot, id, options)
	local lineID = snapshot.membership[id]
	local line = lineID and snapshot.lines[lineID]
	local info = snapshot.metadata[id]
	local graph = { key = lineID and "line:" .. lineID or "quest:" .. id, providerKind = "retail",
		rootQuestID = id, generation = snapshot.generation, revision = snapshot.revision, lineID = lineID,
		title = line and line.title, nodes = {}, order = {}, edges = {}, depths = {}, frontier = { earlier = {}, later = {} },
		partial = not line or line.partial == true, loading = line and line.loading == true or (not line and (not info or info.loading == true)),
		reason = info and info.reason,
		linear = false, completeLinearPath = false, membershipOnly = true, total = line and #line.order or 1 }
	local order, origin = line and line.order or { id }, 1
	for index, questID in ipairs(order) do if questID == id then origin = index; break end end
	local limit = math.max(1, math.floor(tonumber(options.limit) or 100))
	local earlier = math.max(0, math.floor(tonumber(options.earlier) or math.floor((limit - 1) / 2)))
	local later = math.max(0, math.floor(tonumber(options.later) or (limit - 1 - earlier)))
	local first, last = math.max(1, origin - earlier), math.min(#order, origin + later)
	if first > 1 then graph.frontier.earlier[1] = order[first - 1] end
	if last < #order then graph.frontier.later[1] = order[last + 1] end
	graph.moreEarlier, graph.moreLater = first > 1, last < #order
	graph.partial = graph.partial or graph.moreEarlier or graph.moreLater
	for index = first, last do
		local questID = order[index]
		graph.order[#graph.order + 1], graph.nodes[questID], graph.depths[questID] = questID, NodeInfo(snapshot, questID), 0
	end
	return graph
end
local function SelectNodes(snapshot, root, options)
	local limit = math.max(1, math.floor(tonumber(options.limit) or 100))
	local earlierLimit = math.max(0, math.floor(tonumber(options.earlier) or math.floor((limit - 1) / 2)))
	local laterLimit = math.max(0, math.floor(tonumber(options.later) or (limit - 1 - earlierLimit)))
	local selected, frontier = { [root] = true }, { earlier = {}, later = {} }
	-- Walk both directions from each discovered vertex. The direction is carried
	-- by the first edge from the origin, so sibling branches remain discoverable.
	local queue, cursor, counts = { { id = root } }, 1, { earlier = 0, later = 0 }
	local seen = { [root] = true }
	while queue[cursor] do
		local entry = queue[cursor]; cursor = cursor + 1
		local neighbors = {}
		for _, edge in ipairs(snapshot.adjacency[entry.id] or {}) do
			local other = edge.from == entry.id and edge.to or edge.from
			neighbors[#neighbors + 1] = { id = other, direction = entry.direction or (edge.to == entry.id and "earlier" or "later") }
		end
		table.sort(neighbors, function(a, b) return a.id < b.id end)
		for _, neighbor in ipairs(neighbors) do
			if not seen[neighbor.id] then
				seen[neighbor.id] = true
				local direction = neighbor.direction
				local maximum = direction == "earlier" and earlierLimit or laterLimit
				if counts[direction] < maximum then
					selected[neighbor.id], counts[direction] = true, counts[direction] + 1
					queue[#queue + 1] = neighbor
				else frontier[direction][#frontier[direction] + 1] = neighbor.id end
			end
		end
	end
	return selected, frontier
end
local function OrderGraph(graph)
	local incoming, outgoing, ready, connections = {}, {}, {}, {}
	for id in pairs(graph.nodes) do incoming[id], outgoing[id] = 0, {} end
	for _, edge in ipairs(graph.edges) do
		if edge.connects and graph.nodes[edge.from] and graph.nodes[edge.to] then
			local key = edge.from .. ":" .. edge.to
			if not connections[key] then
				connections[key] = true
				incoming[edge.to] = incoming[edge.to] + 1
				outgoing[edge.from][#outgoing[edge.from] + 1] = edge.to
			end
		end
	end
	for id, count in pairs(incoming) do if count == 0 then ready[#ready + 1] = id end end
	table.sort(ready)
	local depths = {}
	while #ready > 0 do
		local id = table.remove(ready, 1)
		graph.order[#graph.order + 1], depths[id] = id, depths[id] or 0
		for _, nextID in ipairs(outgoing[id]) do
			depths[nextID] = math.max(depths[nextID] or 0, depths[id] + 1)
			incoming[nextID] = incoming[nextID] - 1
			if incoming[nextID] == 0 then ready[#ready + 1] = nextID; table.sort(ready) end
		end
	end
	local visited = {}; for _, id in ipairs(graph.order) do visited[id] = true end
	for _, id in ipairs(SortedKeys(graph.nodes)) do
		if not visited[id] then graph.order[#graph.order + 1], depths[id], graph.cycle = id, 0, true end
	end
	graph.depths = depths
	for id, node in pairs(graph.nodes) do node.depth = depths[id] end
	return connections, outgoing
end
local function IsCompleteLinear(graph, snapshot, outgoing)
	if graph.partial or graph.cycle or #graph.order < 2 then return false end
	local required, previous, nextIDs, count = {}, {}, {}, 0
	for _, edge in ipairs(graph.edges) do
		if edge.negative then return false end
		if edge.kind == "prerequisite_all" or edge.kind == "prerequisite_any" then
			local key = edge.from .. ":" .. edge.to
			if not required[key] then
				required[key], count = true, count + 1
				if previous[edge.to] and previous[edge.to] ~= edge.from then return false end
				if nextIDs[edge.from] and nextIDs[edge.from] ~= edge.to then return false end
				previous[edge.to], nextIDs[edge.from] = edge.from, edge.to
			end
		elseif edge.kind ~= "unlock" then return false end
	end
	for id, node in pairs(graph.nodes) do
		local info = snapshot.metadata[id]
		if node.missing or node.invalid or not info then return false end
		-- The schema documents these masks without guaranteeing a repeatable enum.
		-- Nonzero special flags therefore prevent an exact finite path claim.
		if (info.specialFlags or 0) ~= 0 or (info.questFlags or 0) ~= 0 then return false end
		for _, nextID in ipairs(outgoing[id]) do if not required[id .. ":" .. nextID] then return false end end
	end
	return count == #graph.order - 1
end

function QT:GetQuestChainGraph(questID, options)
	questID = PositiveID(questID)
	if not questID then return nil end
	options = options or {}
	local snapshot = self.questChainProviderSnapshot
	if not snapshot then return nil end
	if snapshot.kind == "retail" then return NativeGraph(snapshot, questID, options) end
	local key = snapshot.keyByQuest[questID] or "related:" .. questID
	local selected, frontier = SelectNodes(snapshot, questID, options)
	local graph = { key = key, rootQuestID = questID, providerKind = snapshot.kind,
		generation = snapshot.generation, revision = snapshot.revision, nodes = {}, edges = {}, order = {},
		frontier = frontier, total = #(snapshot.components[key] or { questID }),
		loading = snapshot.state == "loading", partial = snapshot.state ~= "ready", reasons = {}, linear = false }
	graph.moreEarlier, graph.moreLater = #frontier.earlier > 0, #frontier.later > 0
	if graph.moreEarlier or graph.moreLater then graph.partial, graph.reasons.large = true, true end
	local edgeSeen = {}
	for id in pairs(selected) do
		local node = NodeInfo(snapshot, id)
		graph.nodes[id] = node
		if node.missing then graph.partial, graph.reasons.missing = true, true end
		if node.invalid then graph.partial, graph.reasons.invalid = true, true end
		if node.conflicting then graph.reasons.conflicting = true end
		for _, edge in ipairs(snapshot.relations[id] or {}) do
			if not edgeSeen[edge] then graph.edges[#graph.edges + 1], edgeSeen[edge] = edge, true end
		end
		for _, edge in ipairs(snapshot.adjacency[id] or {}) do
			if not edgeSeen[edge] then graph.edges[#graph.edges + 1], edgeSeen[edge] = edge, true end
		end
	end
	table.sort(graph.edges, function(a, b)
		if a.from ~= b.from then return a.from < b.from end
		if a.to ~= b.to then return a.to < b.to end
		return a.kind < b.kind
	end)
	local _, outgoing = OrderGraph(graph)
	if graph.cycle then graph.partial, graph.reasons.cycle = true, true end
	graph.linear = IsCompleteLinear(graph, snapshot, outgoing)
	graph.completeLinearPath = graph.linear
	return graph
end

-- Session identities survive component merges but never enter SavedVariables.
-- A split receives a fresh identity for every new component except the one
-- containing its retained origin; aliases only represent actual merges.
function QT:ResolveQuestChainGroupIdentity(store, graph)
	store.keys, store.origins, store.aliases = store.keys or {}, store.origins or {}, store.aliases or {}
	store.sequence = store.sequence or 0
	local identities = {}
	for id in pairs(graph.nodes) do
		local identity = store.keys[id]
		if identity and graph.nodes[store.origins[identity]] then identities[identity] = true end
	end
	local values = SortedKeys(identities)
	local identity = values[1]
	if not identity then
		store.sequence = store.sequence + 1
		identity = "group:" .. store.sequence
		store.origins[identity] = graph.rootQuestID
	end
	for _, old in ipairs(values) do if old ~= identity then store.aliases[old] = identity end end
	for id in pairs(graph.nodes) do store.keys[id] = identity end
	return identity
end

local function Intersects(a, b)
	if type(a) ~= "number" or type(b) ~= "number" or a < 0 or b < 0 then return nil end
	-- Lua doubles represent the documented race masks exactly; bit32 truncates
	-- Skyborne's bits 32/33, so use arithmetic for both masks instead.
	while a > 0 and b > 0 do
		if a % 2 >= 1 and b % 2 >= 1 then return true end
		a, b = math.floor(a / 2), math.floor(b / 2)
	end
	return false
end
local function Truth(value)
	if value == true then return "met" end
	if value == false then return "blocked" end
	return "unknown"
end
local function And(a, b)
	if a == "blocked" or b == "blocked" then return "blocked" end
	if a == "unknown" or b == "unknown" then return "unknown" end
	return "met"
end
local function Or(a, b)
	if a == "met" or b == "met" then return "met" end
	if a == "unknown" or b == "unknown" then return "unknown" end
	return "blocked"
end
local function EvidenceState(edge, evidence)
	if edge.negative then return "unknown" end
	local value = evidence[edge.relatedQuestID] or {}
	if edge.kind == "prerequisite_all" or edge.kind == "prerequisite_any" or edge.kind == "until_completed" then
		local result = Truth(value.completed)
		if edge.kind == "until_completed" then return result == "met" and "blocked" or result == "blocked" and "met" or "unknown" end
		return result
	elseif edge.kind == "active_parent" then return Truth(value.active)
	elseif edge.kind == "starting_with" then return Or(Truth(value.active), Truth(value.completed))
	elseif edge.kind == "disabled_by" then
		return value.active == true and "blocked" or value.active == false and "met" or "unknown"
	elseif edge.kind == "exclusive" or edge.kind == "replacement" then
		local state = Or(Truth(value.active), Truth(value.completed))
		return state == "met" and "blocked" or state == "blocked" and "met" or "unknown"
	end
	return nil
end

function QT:EvaluateQuestChainRequirements(questID, evidence, character)
	evidence = evidence or {}
	local snapshot, result = self.questChainProviderSnapshot, { state = "met", requirements = {}, groups = {}, blockers = {} }
	if not snapshot or snapshot.kind ~= "questiedb" or snapshot.state ~= "ready" then result.state = "unknown"; return result end
	local node = snapshot.nodes[questID]
	if node and node.conflicting then result.state = "unknown"; return result end
	if not node or node.missing or node.invalid then result.state = "unknown" end
	local any, anyCount = "blocked", 0
	for _, edge in ipairs(snapshot.relations[questID] or {}) do
		local state = EvidenceState(edge, evidence)
		if state then
			local requirement = { kind = edge.kind, questID = edge.relatedQuestID, signedID = edge.signedID,
				field = edge.field, state = state, negative = edge.negative }
			result.requirements[#result.requirements + 1] = requirement
			if state == "blocked" then result.blockers[#result.blockers + 1] = requirement end
			if edge.kind == "prerequisite_any" then any, anyCount = Or(any, state), anyCount + 1
			else result.state = And(result.state, state) end
		end
	end
	if anyCount > 0 then result.groups.any = any; result.state = And(result.state, any) end
	local info, provider = snapshot.metadata[questID], self.questChainProviderState and self.questChainProviderState.provider
	if not info or info.invalid then result.state = And(result.state, "unknown"); return result end
	character = character or {}
	local function Add(kind, state, value)
		result.requirements[#result.requirements + 1] = { kind = kind, state = state, value = value }
		result.state = And(result.state, state)
	end
	if (info.requiredLevel or 0) > 0 then Add("level", Truth(character.level and character.level >= info.requiredLevel), info.requiredLevel) end
	if (info.requiredMaxLevel or 0) > 0 then Add("max_level", Truth(character.level and character.level <= info.requiredMaxLevel), info.requiredMaxLevel) end
	if (info.requiredRaces or 0) ~= 0 then
		local mask = provider and provider.Enum.raceMaskById[character.raceID]
		Add("race", Truth(Intersects(info.requiredRaces, mask)), info.requiredRaces)
	end
	if (info.requiredClasses or 0) ~= 0 then
		local mask = provider and provider.Enum.classKeys[character.classFile]
		Add("class", Truth(Intersects(info.requiredClasses, mask)), info.requiredClasses)
	end
	for _, field in ipairs({ "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredRanks", "requiredSourceItems" }) do
		if type(info[field]) == "table" and next(info[field]) then Add(field, "unknown", info[field]) end
	end
	for _, field in ipairs({ "requiredSpell", "requiredSpecialization" }) do
		if (info[field] or 0) ~= 0 then Add(field, "unknown", info[field]) end
	end
	return result
end
