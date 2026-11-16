-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
-- Optional provider boundary. Only composed, public QuestieDB contract-4 reads
-- are used. See https://github.com/Questie/QuestieDB/blob/v1.1.1/docs/api.md.
local QT = _G.QuestTogether
local BATCH, METADATA_BATCH = 40, 8
local RELATION_FIELDS = {
	"preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo",
	"nextQuestInChain", "parentQuest", "breadcrumbForQuestId", "breadcrumbs",
	"availableUntilCompleted", "availableStartingWith", "disabledByQuest",
}
local META_FIELDS = {
	"name", "startedBy", "requiredLevel", "requiredMaxLevel", "requiredRaces", "requiredClasses",
	"requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSpell", "requiredSpecialization",
	"requiredRanks", "requiredSourceItems", "questFlags", "specialFlags",
}
local KINDS = {
	preQuestGroup = { "prerequisite_all", "before", true },
	preQuestSingle = { "prerequisite_any", "before", true },
	childQuests = { "unlock", "after", true },
	inGroupWith = { "group", "after" }, exclusiveTo = { "exclusive", "after" },
	nextQuestInChain = { "replacement", "after" }, parentQuest = { "active_parent", "before" },
	breadcrumbForQuestId = { "breadcrumb", "after" }, breadcrumbs = { "breadcrumb", "before" },
	availableUntilCompleted = { "until_completed", "after" },
	availableStartingWith = { "starting_with", "before" }, disabledByQuest = { "disabled_by", "after" },
}
local function ID(value)
	return type(value) == "number" and value == value and value > 0 and value <= 2147483647
		and value == math.floor(value) and value or nil
end
local function Text(value)
	if type(value) ~= "string" then return nil end
	return value:sub(1, 512):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		:gsub("|K.-|k", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("[%z\001-\031\127]", ""):gsub("||", "|"):gsub("|", "||")
end
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	return ok and value or nil
end
local function Current(addon, state)
	return addon.questChainProviderState == state and state.active and state.owner.active ~= false
end
local function Notify(addon, state)
	if Current(addon, state) and type(state.onChange) == "function" then state.onChange(state.generation) end
end
local function Schedule(addon, state, key, callback)
	if state.failed then return false end
	local run = function() if Current(addon, state) and not state.failed then callback() end end
	if addon.ScheduleRuntimeWork then
		return addon:ScheduleRuntimeWork("quest_chain_provider", key, run, { mode = "nextFrame", owner = state.workOwner })
	end
	if addon.API and addon.API.Delay then addon.API.Delay(0, run); return true end
	return false
end
local function Snapshot(state, status, reason)
	return { kind = state.kind, state = status, reason = reason, generation = state.generation,
		nodes = {}, edges = {}, adjacency = {}, relations = {}, components = {}, keyByQuest = {}, metadata = {},
		lines = {}, membership = {}, partial = status ~= "ready", revision = 0 }
end
local function Fail(addon, state, reason)
	if not Current(addon, state) then return end
	state.failed = true
	state.workOwner.active = false
	if addon.CancelRuntimeWorkOwner then addon:CancelRuntimeWorkOwner(state.workOwner) end
	addon.questChainProviderSnapshot = Snapshot(state, "unavailable", reason)
	Notify(addon, state)
end
local function Find(stage, id)
	local parent = stage.parents[id]
	if not parent then stage.parents[id] = id; return id end
	while parent ~= stage.parents[parent] do parent = stage.parents[parent] end
	while id ~= parent do local nextID = stage.parents[id]; stage.parents[id] = parent; id = nextID end
	return parent
end
local function Node(stage, id, known)
	local node = stage.nodes[id]
	if not node then
		node = { questID = id, questId = id, missing = not known }
		stage.nodes[id] = node
		stage.nodeOrder[#stage.nodeOrder + 1] = id
	end
	if known then node.missing = false end
	return node
end
local function Edge(stage, id, signedID, field)
	if signedID == 0 or signedID == nil then return end
	local other = type(signedID) == "number" and ID(math.abs(signedID)) or nil
	if not other then stage.nodes[id].invalid = true; return end
	local spec = KINDS[field]
	local from, to = id, other
	if spec[2] == "before" then from, to = other, id end
	local key = field .. ":" .. id .. ":" .. signedID
	if stage.edgeKeys[key] then return end
	stage.edgeKeys[key] = true
	local edge = { from = from, to = to, questID = id, relatedQuestID = other, kind = spec[1],
		field = field, signedID = signedID, negative = signedID < 0, connects = spec[3] == true }
	stage.edges[#stage.edges + 1] = edge
	stage.relations[id] = stage.relations[id] or {}
	stage.relations[id][#stage.relations[id] + 1] = edge
	Node(stage, other, false)
	if edge.connects then
		stage.adjacency[from] = stage.adjacency[from] or {}
		stage.adjacency[to] = stage.adjacency[to] or {}
		stage.adjacency[from][#stage.adjacency[from] + 1] = edge
		if from ~= to then stage.adjacency[to][#stage.adjacency[to] + 1] = edge end
		local a, b = Find(stage, from), Find(stage, to)
		if a ~= b then stage.parents[math.max(a, b)] = math.min(a, b) end
	end
end
-- Four possible states for one referenced quest: neither, active, completed,
-- or both (repeatable quests may be active after an earlier completion). Only
-- the positive-ID conditions explicitly documented by questMeta are combined.
local REQUIREMENT_STATES = {
	prerequisite_all = 12, active_parent = 10, until_completed = 3,
	disabled_by = 5, exclusive = 1, replacement = 1, starting_with = 14,
}
local function IntersectStates(a, b)
	local result, bit = 0, 1
	for _ = 1, 4 do
		if a % 2 == 1 and b % 2 == 1 then result = result + bit end
		a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
	end
	return result
end
local function MarkConflictingRequirements(stage, id)
	local allowed, alternatives, unknownAlternative = {}, {}, false
	local function Conflict()
		stage.nodes[id].invalid, stage.nodes[id].conflicting = true, true
	end
	for _, edge in ipairs(stage.relations[id] or {}) do
		if edge.kind == "prerequisite_any" then
			if edge.negative then unknownAlternative = true else alternatives[edge.relatedQuestID] = true end
		elseif not edge.negative and REQUIREMENT_STATES[edge.kind] then
			local subject = edge.relatedQuestID
			allowed[subject] = IntersectStates(allowed[subject] or 15, REQUIREMENT_STATES[edge.kind])
			if allowed[subject] == 0 then Conflict(); return end
		end
	end
	-- Alternative prerequisites remain OR conditions. One unavailable branch is
	-- legitimate; only a fully contradicted positive alternative set is invalid.
	if not unknownAlternative and next(alternatives) then
		for subject in pairs(alternatives) do
			if IntersectStates(allowed[subject] or 15, 12) ~= 0 then return end
		end
		Conflict()
	end
end
local function ReadRelations(stage, provider, id)
	Node(stage, id, true)
	local values = provider.Quest.GetAll(id, RELATION_FIELDS)
	if type(values) ~= "table" then stage.nodes[id].missing = true; return end
	for index, field in ipairs(RELATION_FIELDS) do
		local value = values[index]
		if type(value) == "table" then
			for _, reference in ipairs(value) do Edge(stage, id, reference, field) end
		elseif value ~= nil then Edge(stage, id, value, field) end
	end
	MarkConflictingRequirements(stage, id)
end
local function StartIndex(addon, state)
	local provider = state.provider
	local ok, ids = pcall(provider.Quest.GetAllIds)
	if not ok or type(ids) ~= "table" then Fail(addon, state, "provider_failed"); return end
	-- GetAllIds is shared: keep this published list read-only. Validation,
	-- relationship reads, and component publication each use bounded slices.
	local list, seen = ids, {}
	local stage = Snapshot(state, "ready")
	stage.parents, stage.edgeKeys, stage.nodeOrder = {}, {}, {}
	state.indexTotal, state.indexDone = #list, 0
	local cursor, componentList = 1, nil
	local function Advance()
		local success = pcall(function()
			if not componentList then
				for _ = 1, BATCH do
					local id = list[cursor]
					if not id then break end
					if not ID(id) then error("invalid provider ID", 0) end
					if not seen[id] then ReadRelations(stage, provider, id); seen[id] = true end
					cursor, state.indexDone = cursor + 1, cursor
				end
				if cursor <= #list then Schedule(addon, state, "index", Advance); return end
				componentList, cursor = stage.nodeOrder, 1
			end
			for _ = 1, BATCH do
				local id = componentList[cursor]
				if not id then break end
				local key = "related:" .. Find(stage, id)
				stage.keyByQuest[id] = key
				stage.components[key] = stage.components[key] or {}
				stage.components[key][#stage.components[key] + 1] = id
				cursor = cursor + 1
			end
			if cursor <= #componentList then Schedule(addon, state, "index", Advance); return end
			stage.parents, stage.edgeKeys, stage.nodeOrder, stage.partial = nil, nil, nil, false
			-- Metadata work may have finished while the relationship index was staged.
			stage.metadata = addon.questChainProviderSnapshot.metadata
			stage.revision = addon.questChainProviderSnapshot.revision + 1
			addon.questChainProviderSnapshot = stage
			Notify(addon, state)
		end)
		if not success then Fail(addon, state, "provider_failed") end
	end
	Schedule(addon, state, "index", Advance)
end

function QT:CancelQuestChainProvider(owner)
	local state = self.questChainProviderState
	if not state or (owner and state.owner ~= owner) then return false end
	state.active, state.workOwner.active = false, false
	if self.CancelRuntimeWorkOwner then self:CancelRuntimeWorkOwner(state.workOwner) end
	self.questChainProviderState = nil
	return true
end

local function HasForeverData(addon, state, status)
	if type(status) ~= "table" then return false end
	if status.mode ~= "source" and status.mode ~= "baked" then return false end
	state.mode = status.mode
	local metadata = addon.API and addon.API.GetAddOnMetadata
	local flavor = SafeCall(metadata, "QuestieDB", "X-Flavor")
	local mode = SafeCall(metadata, "QuestieDB", "X-Mode")
	if (flavor ~= nil and flavor ~= "Forever") or (mode ~= nil and mode ~= status.mode) then return false end
	if status.expansion ~= nil then
		if status.expansion ~= "Forever" then return false end
		state.flavorSource = "status"
		return true
	end
	-- QuestieDB 1.1.1 reports expansion only in Source mode. Its packaged
	-- backend selects data from the active TOC's X-Flavor and X-Mode metadata.
	-- Verify those public fields; the running client alone cannot certify data.
	if status.mode == "baked" and flavor == "Forever" and mode == "baked" then
		state.flavorSource = "package"
		return true
	end
	return false
end

function QT:RevalidateQuestChainProvider(owner, onChange)
	self:CancelQuestChainProvider()
	owner = owner or { active = true }
	self.questChainProviderGeneration = (self.questChainProviderGeneration or 0) + 1
	local client = SafeCall(self.API and self.API.GetQuestChainClient) or "unsupported"
	local state = { owner = owner, workOwner = { active = true }, active = true, onChange = onChange,
		generation = self.questChainProviderGeneration, kind = client, metadataQueue = {}, metadataQueued = {},
		metadataRequests = {}, requested = {}, requestedMaps = {}, questDataRequests = {}, nativeDataUpdated = {} }
	self.questChainProviderState = state
	if client == "forever" then
		state.kind = "questiedb"
		local provider = rawget(_G, "LibQuestieDB")
		self.questChainProviderSnapshot = Snapshot(state, "loading", "index_loading")
		if type(provider) ~= "table" then Fail(self, state, "provider_missing"); return self:GetQuestChainProviderCapability() end
		local ok, compatible = pcall(function() return provider.RequireContract(4) end)
		if not ok or compatible ~= true then Fail(self, state, "provider_contract"); return self:GetQuestChainProviderCapability() end
		local status = SafeCall(provider.ModeIndicator and provider.ModeIndicator.GetStatus)
		if not HasForeverData(self, state, status) then
			Fail(self, state, "provider_flavor"); return self:GetQuestChainProviderCapability()
		end
		if type(provider.Quest) ~= "table" or type(provider.Quest.GetAll) ~= "function"
			or type(provider.Quest.GetAllIds) ~= "function" or type(provider.Enum) ~= "table"
			or type(provider.Enum.raceMaskById) ~= "table" or type(provider.Enum.classKeys) ~= "table"
			or type(provider.Enum.factionRaceMasks) ~= "table" then
			Fail(self, state, "provider_contract"); return self:GetQuestChainProviderCapability()
		end
		state.provider, state.mode = provider, status.mode
		StartIndex(self, state)
	elseif client == "retail" then
		if type(self.API.GetQuestLineInfo) ~= "function" or type(self.API.GetQuestLineQuests) ~= "function"
			or (self.API.CanReadNativeQuestChains and SafeCall(self.API.CanReadNativeQuestChains) ~= true) then
			self.questChainProviderSnapshot = Snapshot(state, "unavailable", "native_unavailable")
		else self.questChainProviderSnapshot = Snapshot(state, "ready", "membership_only") end
	else self.questChainProviderSnapshot = Snapshot(state, "unavailable", "client_unsupported") end
	return self:GetQuestChainProviderCapability()
end

function QT:GetQuestChainProviderCapability()
	local snapshot, state = self.questChainProviderSnapshot, self.questChainProviderState
	return { kind = snapshot and snapshot.kind or "unsupported", state = snapshot and snapshot.state or "unavailable",
		reason = snapshot and snapshot.reason or "not_initialized", generation = snapshot and snapshot.generation or 0,
		mode = state and state.mode, flavorSource = state and state.flavorSource,
		indexed = state and state.indexDone or 0, total = state and state.indexTotal or 0 }
end

local function ReadAreaMaps(state)
	if state.areaMaps ~= nil then return state.areaMaps or nil end
	state.areaMaps = false
	local provider = state.provider
	local support = SafeCall(provider.Support and provider.Support.Get, "ZoneDB")
	local source = type(support) == "table" and type(support.private) == "table" and support.private.areaIdToUiMapId
	if type(source) == "table" then state.areaMaps = source; return source end
	if type(source) ~= "string" or #source > 2000000 then return nil end
	-- This documented support value is Lua data; do not allow global access when
	-- evaluating its table expression. This is never saved or copied into QT.
	local loader = loadstring or load
	local fn
	if loadstring then
		fn = loader(source) or loader("return " .. source)
		if fn and setfenv then setfenv(fn, {}) end
	else fn = loader(source, "QuestieDB map data", "t", {}) or loader("return " .. source, "QuestieDB map data", "t", {}) end
	local maps = fn and SafeCall(fn)
	if type(maps) == "table" then state.areaMaps = maps; return maps end
end
local function ReadStarters(addon, state, startedBy)
	local locations, seen, itemStarted = {}, {}, type(startedBy) == "table" and type(startedBy[3]) == "table" and #startedBy[3] > 0
	local maps = ReadAreaMaps(state)
	for slot = 1, 2 do
		local entity = slot == 1 and state.provider.Npc or state.provider.Object
		if type(entity) == "table" and type(entity.GetAll) == "function" then
			for _, id in ipairs(type(startedBy) == "table" and startedBy[slot] or {}) do
				if ID(id) then
					local values = entity.GetAll(id, { "name", "spawns" })
					local name, spawns = type(values) == "table" and Text(values[1]), type(values) == "table" and values[2]
					for areaID, points in pairs(type(spawns) == "table" and spawns or {}) do
						local mapID = maps and ID(maps[areaID])
						local mapInfo = mapID and SafeCall(addon.API.GetMapInfo, mapID)
						if type(mapInfo) == "table" and type(mapInfo.name) == "string" then
							for _, point in ipairs(type(points) == "table" and points or {}) do
								local x, y = type(point) == "table" and point[1], type(point) == "table" and point[2]
								if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
									local key = slot .. ":" .. id .. ":" .. mapID .. ":" .. x .. ":" .. y
									if not seen[key] then
										seen[key] = true
										locations[#locations + 1] = { kind = slot == 1 and "npc" or "object", id = id,
											name = name, mapID = mapID, mapName = Text(mapInfo.name), x = x / 100, y = y / 100,
											areaID = areaID, phase = point[3] }
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return locations, #locations > 0 and nil or (itemStarted and "item_started" or "location_unknown")
end
local function ReadQuestieMetadata(addon, state, id)
	local values = state.provider.Quest.GetAll(id, META_FIELDS)
	if type(values) ~= "table" then return { questID = id, missing = true, locationReason = "quest_unknown" } end
	local info = { questID = id, questId = id }
	for index, field in ipairs(META_FIELDS) do info[field] = values[index] end
	for _, field in ipairs({ "requiredLevel", "requiredMaxLevel", "requiredRaces", "requiredClasses", "requiredSpell", "requiredSpecialization", "questFlags", "specialFlags" }) do
		local value = info[field]
		if value ~= nil and (type(value) ~= "number" or value ~= value or value < 0 or value > 9007199254740991 or value ~= math.floor(value)) then
			info[field], info.invalid = nil, true
		end
	end
	info.title = Text(info.name)
	info.name = nil
	info.locations, info.locationReason = ReadStarters(addon, state, info.startedBy)
	return info
end
local function CopyMap(input)
	local result = {}; for key, value in pairs(input or {}) do result[key] = value end; return result
end
local function ReadNativeMetadata(addon, state, id, snapshot)
	local mapID = SafeCall(addon.API.GetBestMapForUnit, "player")
	local native = SafeCall(addon.API.GetQuestLineInfo, id, mapID)
	local nativeLineID = type(native) == "table" and ID(native.questLineID)
	-- Per-quest offer information is nullable even for a positively listed line
	-- member. A title request must not erase that authoritative membership.
	local lineID = nativeLineID or snapshot.membership[id]
	local title = Text(SafeCall(addon.API.GetQuestChainQuestTitle, id))
	if not title and not state.questDataRequests[id] then
		state.questDataRequests[id] = true
		SafeCall(addon.API.RequestQuestChainQuestData, id)
	end
	local info = { questID = id, questId = id, title = title, lineID = lineID, locations = {}, locationReason = "native_location_unknown" }
	if lineID then
		local nativeIDs = SafeCall(addon.API.GetQuestLineQuests, lineID)
		local oldLine = snapshot.lines[lineID]
		local ids, seen = {}, {}
		local returnedList = type(nativeIDs) == "table"
		for _, questID in ipairs(returnedList and nativeIDs or oldLine and oldLine.order or {}) do
			questID = type(questID) == "table" and questID.questID or questID
			if ID(questID) and not seen[questID] then ids[#ids + 1], seen[questID] = questID, true end
		end
		local partial = not returnedList or (nativeLineID and not seen[id]) or false
		if nativeLineID and not seen[id] then ids[#ids + 1], seen[id] = id, true end
		local line = { id = lineID, title = Text(type(native) == "table" and native.questLineName) or (oldLine and oldLine.title),
			order = ids, partial = partial,
			loading = partial and not state.nativeDataUpdated[id] }
		for _, oldID in ipairs(oldLine and oldLine.order or {}) do
			if not seen[oldID] and snapshot.membership[oldID] == lineID then
				snapshot.membership[oldID], snapshot.keyByQuest[oldID] = nil, nil
			end
		end
		snapshot.lines[lineID] = line
		for _, questID in ipairs(ids) do
			snapshot.membership[questID] = lineID
			snapshot.nodes[questID] = { questID = questID, questId = questID }
			snapshot.keyByQuest[questID] = "line:" .. lineID
		end
		if seen[id] then info.loading = line.loading
		else
			-- Only a returned membership list can remove an earlier positive fact.
			info.lineID, info.loading = nil, not state.nativeDataUpdated[id]
			info.reason = info.loading and "native_loading" or "native_line_unknown"
		end
	else
		info.loading = not state.nativeDataUpdated[id]
		info.reason = info.loading and "native_loading" or "native_line_unknown"
	end
	if info.loading and ID(mapID) and not state.requestedMaps[mapID] then
		state.requestedMaps[mapID] = true
		SafeCall(addon.API.RequestQuestLinesForMap, mapID)
	end
	return info
end
local function QueueMetadata(addon, state)
	if state.metadataRunning then return end
	state.metadataRunning = true
	Schedule(addon, state, "metadata", function()
		state.metadataRunning = false
		local previous = addon.questChainProviderSnapshot
		if not previous or state.failed or #state.metadataQueue == 0 then return end
		local snapshot = CopyMap(previous)
		snapshot.metadata = CopyMap(previous.metadata)
		if state.kind == "retail" then
			snapshot.lines, snapshot.membership = CopyMap(previous.lines), CopyMap(previous.membership)
			snapshot.nodes, snapshot.keyByQuest = CopyMap(previous.nodes), CopyMap(previous.keyByQuest)
		end
		local ok = pcall(function()
			for _ = 1, METADATA_BATCH do
				local id = table.remove(state.metadataQueue, 1)
				if not id then break end
				state.metadataQueued[id] = nil
				snapshot.metadata[id] = state.kind == "questiedb" and ReadQuestieMetadata(addon, state, id)
					or ReadNativeMetadata(addon, state, id, snapshot)
			end
		end)
		if not ok then Fail(addon, state, "provider_failed"); return end
		snapshot.revision = previous.revision + 1
		addon.questChainProviderSnapshot = snapshot
		Notify(addon, state)
		for callback in pairs(state.metadataRequests) do callback(state.generation) end
		state.metadataRequests = {}
		if #state.metadataQueue > 0 then QueueMetadata(addon, state) end
	end)
end

-- The comparison owns metadata demand independently of the long-lived provider
-- index. Retiring a section cancels unread work without discarding useful cache.
function QT:SetQuestChainMetadataInterest(ids, owner)
	local state = self.questChainProviderState
	if not state or not Current(self, state) or (owner and owner ~= state.owner) then return false end
	local wanted, queue, queued = {}, {}, {}
	for _, id in ipairs(ids or {}) do if ID(id) then wanted[id] = true end end
	for _, id in ipairs(state.metadataQueue) do
		if wanted[id] then queue[#queue + 1], queued[id] = id, true end
	end
	for id in pairs(state.requested) do
		if not wanted[id] then state.questDataRequests[id], state.nativeDataUpdated[id] = nil, nil end
	end
	for callback, request in pairs(state.metadataRequests) do
		local retained = false
		for id in pairs(request) do
			if wanted[id] then retained = true else request[id] = nil end
		end
		if not retained then state.metadataRequests[callback] = nil end
	end
	state.requested, state.metadataQueue, state.metadataQueued = wanted, queue, queued
	return true
end

function QT:RequestQuestChainMetadata(ids, owner, onChange)
	local state = self.questChainProviderState
	if not state or not Current(self, state) or (owner and owner ~= state.owner) or state.failed
		or (state.kind ~= "questiedb" and state.kind ~= "retail") then return false end
	local snapshot, queued, requested = self.questChainProviderSnapshot, false, {}
	for _, id in ipairs(ids or {}) do
		if ID(id) then
			state.requested[id] = true
			if not snapshot.metadata[id] and not state.metadataQueued[id] then
				state.metadataQueue[#state.metadataQueue + 1], state.metadataQueued[id], queued = id, true, true
				requested[id] = true
			end
		end
	end
	if queued and type(onChange) == "function" then state.metadataRequests[onChange] = requested end
	if queued then QueueMetadata(self, state) end
	return queued
end

function QT:GetQuestChainQuestInfo(id)
	local snapshot = self.questChainProviderSnapshot
	return snapshot and snapshot.metadata[id] or nil
end

function QT:GetQuestChainStarterLocations(id, currentMap)
	local info = self:GetQuestChainQuestInfo(id)
	local result = {}
	for index, location in ipairs(info and info.locations or {}) do result[index] = location end
	table.sort(result, function(a, b)
		if (a.mapID == currentMap) ~= (b.mapID == currentMap) then return a.mapID == currentMap end
		if (a.mapName or "") ~= (b.mapName or "") then return (a.mapName or "") < (b.mapName or "") end
		if a.mapID ~= b.mapID then return a.mapID < b.mapID end
		if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
		if a.id ~= b.id then return a.id < b.id end
		if a.x ~= b.x then return a.x < b.x end
		return a.y < b.y
	end)
	return result, info and info.locationReason or "loading"
end

function QT:OnQuestChainDataEvent(event, questID, success)
	local state = self.questChainProviderState
	if not state or not Current(self, state) then return end
	if event == "ADDON_LOADED" then
		if questID == "QuestieDB" and state.failed then self:RevalidateQuestChainProvider(state.owner, state.onChange) end
		return
	end
	if state.kind ~= "retail" then return end
	if event == "QUEST_DATA_LOAD_RESULT" and (not state.requested[questID] or success == false) then return end
	if event ~= "QUEST_DATA_LOAD_RESULT" and event ~= "QUESTLINE_UPDATE" then return end
	-- QUESTLINE_UPDATE(true) invalidates cached map data; false reports that
	-- requested data can be read. Quest text loading is a separate lifecycle.
	if event == "QUESTLINE_UPDATE" and questID == true then
		if state.nativeRefreshWaiting then return end
		state.nativeRefreshWaiting = true
		for id in pairs(state.requested) do state.nativeDataUpdated[id] = nil end
		Schedule(self, state, "native_refresh", function()
			local mapID = SafeCall(self.API.GetBestMapForUnit, "player")
			if ID(mapID) then
				state.requestedMaps[mapID] = true
				SafeCall(self.API.RequestQuestLinesForMap, mapID)
			end
		end)
		return
	end
	if event == "QUESTLINE_UPDATE" then state.nativeRefreshWaiting = nil end
	for id in pairs(state.requested) do
		if event == "QUESTLINE_UPDATE" or id == questID then
			if event == "QUESTLINE_UPDATE" then state.nativeDataUpdated[id] = true end
			if not state.metadataQueued[id] then state.metadataQueue[#state.metadataQueue + 1], state.metadataQueued[id] = id, true end
		end
	end
	if #state.metadataQueue > 0 then QueueMetadata(self, state) end
end

function QT:GetQuestChainProviderDiagnostics()
	local result = self:GetQuestChainProviderCapability()
	local snapshot, state = self.questChainProviderSnapshot, self.questChainProviderState
	local function Count(values)
		local count = 0
		for _ in pairs(values or {}) do count = count + 1; if count >= 100000 then break end end
		return count
	end
	result.nodes, result.metadata = Count(snapshot and snapshot.nodes), Count(snapshot and snapshot.metadata)
	result.edges = math.min(100000, snapshot and #snapshot.edges or 0)
	result.indexed, result.total = math.min(100000, result.indexed), math.min(100000, result.total)
	result.missingReferences, result.unresolvedReferences, result.conflicts = 0, 0, 0
	for _, node in pairs(snapshot and snapshot.nodes or {}) do
		if node.missing then result.missingReferences = math.min(100000, result.missingReferences + 1) end
		if node.conflicting then result.conflicts = math.min(100000, result.conflicts + 1) end
		if result.missingReferences >= 100000 and result.conflicts >= 100000 then break end
	end
	for _, edge in ipairs(snapshot and snapshot.edges or {}) do
		local from, to = snapshot.nodes[edge.from], snapshot.nodes[edge.to]
		if not from or not to or from.missing or to.missing or from.invalid or to.invalid then
			result.unresolvedReferences = result.unresolvedReferences + 1
		end
		if result.unresolvedReferences >= 100000 then break end
	end
	result.pendingMetadata = math.min(100000, state and #state.metadataQueue or 0)
	result.requestInterests = Count(state and state.requested)
	return result
end
