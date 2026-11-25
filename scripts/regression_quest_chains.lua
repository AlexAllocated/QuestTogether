-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
local QT = _G.QuestTogether
local function Equal(actual, expected, label)
	assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Provider(rows)
	local provider = { calls = 0, addonName = "QuestieDB", Enum = { raceMaskById = { [1] = 1, [95] = 4294967296, [96] = 8589934592 },
		classKeys = { WARRIOR = 1, MAGE = 128 }, factionRaceMasks = { Alliance = 4294967373, Horde = 8589934770 } } }
	provider.RequireContract = function(contract) Equal(contract, 4); return true end
	-- Packaged QuestieDB 1.1.1 reports its mode but no Source expansion.
	provider.ModeIndicator = { GetStatus = function() return { mode = "baked" } end }
	provider.Quest = {
		GetAllIds = function() local result = {}; for id in pairs(rows) do result[#result + 1] = id end; table.sort(result); return result end,
		GetAll = function(id, fields)
			provider.calls = provider.calls + 1
			if provider.failure == id then error("broken getter") end
			if not rows[id] then return nil end
			local values = { n = #fields }
			for index, field in ipairs(fields) do values[index] = rows[id][field] end
			return values
		end,
	}
	provider.Support = { Get = function(name) Equal(name, "ZoneDB"); return { private = { areaIdToUiMapId = "return {[12]=101,[13]=102,[14]=999}" } } end }
	return provider
end
local function Fixture(client)
	local a = setmetatable({ API = {}, callbacks = {}, notices = 0, questChainProviderGeneration = 0 }, { __index = QT })
	a.API.GetQuestChainClient = function() return client or "forever" end
	a.API.GetAddOnMetadata = function(addonName, field)
		Equal(addonName, "QuestieDB", "active provider addon")
		if field == "X-Flavor" then return "Forever" end
		if field == "X-Mode" then return "baked" end
	end
	a.API.Delay = function(_, callback) a.callbacks[#a.callbacks + 1] = callback end
	a.API.GetBestMapForUnit = function() return 101 end
	a.API.GetMapInfo = function(id) if id ~= 999 then return { name = id == 101 and "First" or "Second" } end end
	a.ScheduleRuntimeWork = function(self, _, _, callback) self.API.Delay(0, callback); return true end
	a.CancelRuntimeWorkOwner = function(_, owner) owner.active = false end
	function a:Flush(count)
		local iterations = 0
		while #self.callbacks > 0 and (not count or iterations < count) do
			iterations = iterations + 1; assert(iterations < 10000, "provider work did not settle")
			local callback = table.remove(self.callbacks, 1); callback()
		end
	end
	function a:Open()
		self.owner = { active = true }
		self:RevalidateQuestChainProvider(self.owner, function() self.notices = self.notices + 1 end)
	end
	return a
end
local function WithProvider(provider, callback)
	local old = _G.LibQuestieDB
	_G.LibQuestieDB = provider
	local ok, message = pcall(callback)
	_G.LibQuestieDB = old
	if not ok then error(message, 0) end
end
local function Metadata(a, ids)
	a:RequestQuestChainMetadata(ids, a.owner); a:Flush()
end

QT:RegisterTest("quest chain metadata retains quest difficulty level separately from acceptance level", function()
	WithProvider(Provider({ [1] = { name = "Level test", questLevel = 18, requiredLevel = 16 },
		[2] = { name = "Unknown level", requiredLevel = 16 }, [3] = { name = "Scaling", questLevel = -1, requiredLevel = 16 } }), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1, 2, 3 })
		Equal(a:GetQuestChainQuestInfo(1).questLevel, 18); Equal(a:GetQuestChainQuestInfo(1).requiredLevel, 16)
		Equal(a:GetQuestChainQuestInfo(2).questLevel, nil); Equal(a:GetQuestChainQuestInfo(3).questLevel, nil)
	end)
end, { offline = true })

QT:RegisterTest("quest area metadata distinguishes geographic areas from quest categories", function()
	WithProvider(Provider({ [1] = { name = "Area", zoneOrSort = 12 },
		[2] = { name = "Category", zoneOrSort = -12 }, [3] = { name = "Unmapped", zoneOrSort = 123456 } }), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1, 2, 3 })
		Equal(a:GetQuestChainQuestInfo(1).questAreaMapID, 101)
		Equal(a:GetQuestChainQuestInfo(2).questAreaMapID, nil)
		Equal(a:GetQuestChainQuestInfo(3).questAreaMapID, nil)
	end)
end, { offline = true })

QT:RegisterTest("quest chains reject missing wrong contract wrong flavor and recover late providers", function()
	WithProvider(nil, function()
		local a = Fixture(); a:Open(); Equal(a:GetQuestChainProviderCapability().reason, "provider_missing")
		_G.LibQuestieDB = Provider({ [1] = { name = "One" } })
		a:OnQuestChainDataEvent("ADDON_LOADED", "OtherAddon"); Equal(a:GetQuestChainProviderCapability().reason, "provider_missing")
		a:OnQuestChainDataEvent("ADDON_LOADED", "QuestieDB"); a:Flush(); Equal(a:GetQuestChainProviderCapability().state, "ready")
		_G.LibQuestieDB.RequireContract = function() return false end
		a:Open(); Equal(a:GetQuestChainProviderCapability().reason, "provider_contract")
		_G.LibQuestieDB.RequireContract = function() return true end
		_G.LibQuestieDB.ModeIndicator.GetStatus = function() return { expansion = "Vanilla" } end
		a:Open(); Equal(a:GetQuestChainProviderCapability().reason, "provider_flavor")
		local b = Fixture("unsupported"); b:Open(); Equal(b:GetQuestChainProviderCapability().reason, "client_unsupported")
		local c = Fixture("retail")
		c.API.GetQuestLineInfo, c.API.GetQuestLineQuests = function() end, function() end
		c.API.CanReadNativeQuestChains = function() return false end
		c:Open(); Equal(c:GetQuestChainProviderCapability().reason, "native_unavailable")
	end)
end, { offline = true })

QT:RegisterTest("quest chains verify packaged baked and explicit Source flavor evidence", function()
	local cases = {
		{ name = "packaged baked", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" }, source = "package" },
		{ name = "explicit baked", status = { mode = "baked", expansion = "Forever" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" }, source = "status" },
		{ name = "explicit Source", status = { mode = "source", expansion = "Forever" }, metadata = { ["X-Mode"] = "source" }, source = "status" },
		{ name = "explicit Source matching metadata", status = { mode = "source", expansion = "Forever" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "source" }, source = "status" },
		{ name = "explicit Source absent metadata", status = { mode = "source", expansion = "Forever" }, metadata = {}, source = "status" },
		{ name = "explicit baked absent metadata API", status = { mode = "baked", expansion = "Forever" }, missingMetadata = true, source = "status" },
		{ name = "explicit Source failed optional metadata", status = { mode = "source", expansion = "Forever" }, failedMetadata = true, source = "status" },
	}
	for _, case in ipairs(cases) do
		local provider = Provider({ [1] = { name = "One" } })
		provider.ModeIndicator.GetStatus = function() return case.status end
		WithProvider(provider, function()
			local a = Fixture()
			if case.missingMetadata then a.API.GetAddOnMetadata = nil
			else a.API.GetAddOnMetadata = function(addonName, field)
				Equal(addonName, "QuestieDB", case.name)
				if case.failedMetadata then error("unavailable addon metadata") end
				return case.metadata[field]
			end end
			a:Open(); a:Flush()
			local capability = a:GetQuestChainProviderCapability()
			Equal(capability.state, "ready", case.name)
			Equal(capability.mode, case.status.mode, case.name .. " mode")
			Equal(capability.flavorSource, case.source, case.name .. " evidence")
			Equal(provider.calls, 1, case.name .. " index read")
		end)
	end
end, { offline = true })

QT:RegisterTest("quest chains reject absent conflicting or unknown provider flavor evidence before indexing", function()
	local cases = {
		{ name = "wrong baked flavor", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "Classic", ["X-Mode"] = "baked" } },
		{ name = "missing baked flavor", status = { mode = "baked" }, metadata = { ["X-Mode"] = "baked" } },
		{ name = "unknown baked flavor", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "future", ["X-Mode"] = "baked" } },
		{ name = "lowercase baked flavor", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "forever", ["X-Mode"] = "baked" } },
		{ name = "conflicting baked mode", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "source" } },
		{ name = "missing baked mode", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "Forever" } },
		{ name = "unknown baked mode", status = { mode = "baked" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "future" } },
		{ name = "missing status mode", status = { expansion = "Forever" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
		{ name = "unknown status mode", status = { mode = "future", expansion = "Forever" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "future" } },
		{ name = "nil status", metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
		{ name = "failed status", failedStatus = true, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
		{ name = "missing status getter", missingStatus = true, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
		{ name = "missing baked metadata API", status = { mode = "baked" }, missingMetadata = true },
		{ name = "failed baked metadata API", status = { mode = "baked" }, failedMetadata = true },
		{ name = "wrong explicit baked expansion", status = { mode = "baked", expansion = "Classic" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
		{ name = "wrong explicit Source expansion", status = { mode = "source", expansion = "Classic" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "source" } },
		{ name = "unknown explicit expansion", status = { mode = "baked", expansion = "future" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
		{ name = "Source lacks explicit expansion", status = { mode = "source" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "source" } },
		{ name = "explicit expansion conflicts with flavor", status = { mode = "baked", expansion = "Forever" }, metadata = { ["X-Flavor"] = "Classic", ["X-Mode"] = "baked" } },
		{ name = "explicit expansion conflicts with mode", status = { mode = "source", expansion = "Forever" }, metadata = { ["X-Flavor"] = "Forever", ["X-Mode"] = "baked" } },
	}
	for _, case in ipairs(cases) do
		local provider = Provider({ [1] = { name = "One" } })
		if case.missingStatus then provider.ModeIndicator.GetStatus = nil
		else provider.ModeIndicator.GetStatus = function()
			if case.failedStatus then error("unavailable provider status") end
			return case.status
		end end
		WithProvider(provider, function()
			local a = Fixture()
			if case.missingMetadata then a.API.GetAddOnMetadata = nil
			else a.API.GetAddOnMetadata = function(addonName, field)
				Equal(addonName, "QuestieDB", case.name)
				if case.failedMetadata then error("unavailable addon metadata") end
				return case.metadata[field]
			end end
			a:Open(); a:Flush()
			local capability = a:GetQuestChainProviderCapability()
			Equal(capability.state, "unavailable", case.name)
			Equal(capability.reason, "provider_flavor", case.name .. " reason")
			Equal(provider.calls, 0, case.name .. " must not read quest data")
			Equal(capability.indexed, 0, case.name .. " must not index quest data")
		end)
	end
end, { offline = true })

QT:RegisterTest("quest chain index is bounded atomic and discards failures and retired generations", function()
	local rows = {}; for id = 1, 121 do rows[id] = { name = "Quest " .. id, preQuestSingle = id > 1 and { id - 1 } or nil } end
	local provider = Provider(rows)
	WithProvider(provider, function()
		local a = Fixture(); a:Open(); local first = a.questChainProviderSnapshot
		Equal(provider.calls, 0); a:Flush(1); Equal(provider.calls, 40)
		Equal(a.questChainProviderSnapshot, first); Equal(next(first.nodes), nil)
		local staleGeneration = first.generation; a:Open(); a:Flush()
		assert(a.questChainProviderSnapshot.generation > staleGeneration)
		Equal(a:GetQuestChainGraph(50, { earlier = 200, later = 200 }).total, 121)
		provider.failure = 81; a:Open(); a:Flush(); Equal(a:GetQuestChainProviderCapability().reason, "provider_failed")
		Equal(next(a.questChainProviderSnapshot.nodes), nil)
		provider.failure = nil; a:Open(); a:CancelQuestChainProvider(a.owner); a:Flush()
		Equal(a:GetQuestChainProviderCapability().state, "loading")
	end)
end, { offline = true })

QT:RegisterTest("quest chain graphs preserve prerequisite topology and keep availability relations separate", function()
	local rows = {
		[1] = { name = "One" }, [2] = { name = "Middle", preQuestSingle = { 1 } },
		[3] = { name = "Three", preQuestSingle = { 2 } },
		[4] = { name = "Four", parentQuest = 3 }, [5] = { name = "Five", exclusiveTo = { 3 } },
		[6] = { name = "Six", nextQuestInChain = 3 }, [7] = { name = "Seven", breadcrumbForQuestId = 3 },
		[8] = { name = "Eight", availableStartingWith = 3 }, [9] = { name = "Nine", inGroupWith = { 3 } },
	}
	WithProvider(Provider(rows), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1, 2, 3 })
		local graph = a:GetQuestChainGraph(3)
		Equal(#graph.order, 3); Equal(graph.order[1], 1); Equal(graph.order[2], 2); Equal(graph.order[3], 3)
		Equal(graph.linear, true); Equal(graph.depths[3], 2)
		for id = 4, 9 do assert(a:GetQuestChainGraph(id).key ~= graph.key, "availability must not merge related groups") end
		local reads = _G.LibQuestieDB.calls
		a:GetQuestChainGraph(3); a:GetQuestChainQuestInfo(3); a:GetQuestChainStarterLocations(3, 101)
		Equal(_G.LibQuestieDB.calls, reads, "render getters must not read provider")
		rows[2].preQuestSingle = nil; a:Open(); a:Flush()
		assert(a:GetQuestChainGraph(3).key ~= a:GetQuestChainGraph(1).key, "refresh must see provider corrections")
	end)
end, { offline = true })

QT:RegisterTest("quest chain all any signed active exclusive and repeatable evidence remain independent", function()
	local rows = {
		[1] = { name = "One" }, [2] = { name = "Two" },
		[3] = { name = "All", preQuestGroup = { 1, 2 } },
		[4] = { name = "Any", preQuestSingle = { 1, 2 } },
		[5] = { name = "Signed", preQuestSingle = { -1 } },
		[6] = { name = "Active", parentQuest = 1, exclusiveTo = { 2 } },
		[7] = { name = "Replacement", nextQuestInChain = 2 },
		[8] = { name = "Availability", availableStartingWith = 1, availableUntilCompleted = 2, disabledByQuest = 2 },
		[9] = { name = "Repeatable", preQuestSingle = { 8 }, specialFlags = 1 },
	}
	WithProvider(Provider(rows), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
		local evidence = { [1] = { active = true, completed = true }, [2] = { active = false, completed = false } }
		Equal(a:EvaluateQuestChainRequirements(3, evidence).state, "blocked")
		Equal(a:EvaluateQuestChainRequirements(4, evidence).state, "met")
		local signed = a:EvaluateQuestChainRequirements(5, evidence)
		Equal(signed.state, "unknown"); Equal(signed.requirements[1].signedID, -1)
		Equal(a:EvaluateQuestChainRequirements(6, evidence).state, "met")
		Equal(a:EvaluateQuestChainRequirements(8, evidence).state, "met")
		evidence[2].active = true
		Equal(a:EvaluateQuestChainRequirements(6, evidence).state, "blocked")
		Equal(a:EvaluateQuestChainRequirements(7, evidence).state, "blocked")
		Equal(a:EvaluateQuestChainRequirements(8, evidence).state, "blocked")
		Equal(a:GetQuestChainGraph(3).linear, false, "convergence is not linear")
		Equal(a:GetQuestChainGraph(9).linear, false, "repeatable masks cannot prove a finite path")
	end)
end, { offline = true })

QT:RegisterTest("quest chain missing cyclic and huge graphs expose partial state and progressive frontiers", function()
	local rows = { [1] = { preQuestSingle = { 2 } }, [2] = { preQuestSingle = { 1 } }, [3] = { preQuestSingle = { 9999 } } }
	for id = 10, 1010 do rows[id] = { name = "Large " .. id, preQuestSingle = id > 10 and { id - 1 } or nil } end
	WithProvider(Provider(rows), function()
		local a = Fixture(); a:Open(); a:Flush()
		local cycle = a:GetQuestChainGraph(1); Equal(cycle.cycle, true); Equal(cycle.partial, true); Equal(cycle.linear, false)
		local missing = a:GetQuestChainGraph(3); Equal(missing.nodes[9999].missing, true); Equal(missing.reasons.missing, true)
		local small = a:GetQuestChainGraph(500, { earlier = 10, later = 10 })
		Equal(#small.order, 21); Equal(small.total, 1001); Equal(small.moreEarlier, true); Equal(small.moreLater, true)
		local large = a:GetQuestChainGraph(500, { earlier = 2000, later = 2000 })
		Equal(#large.order, 1001); Equal(large.partial, false); Equal(large.moreEarlier, false); Equal(large.moreLater, false)
		local identities = {}
		local first = a:ResolveQuestChainGroupIdentity(identities, small)
		Equal(a:ResolveQuestChainGroupIdentity(identities, large), first)
	end)
end, { offline = true })

QT:RegisterTest("quest chain starter alternatives validate maps and coordinates without guessing item origins", function()
	local provider = Provider({ [1] = { name = "Start", startedBy = { { 11 }, { 22 } } }, [2] = { startedBy = { nil, nil, { 33 } } } })
	provider.Npc = { GetAll = function() return { "NPC", { [12] = { { 20, 30 }, { 101, 2 }, { -1, 2 } }, [14] = { { 40, 50 } } } } end }
	provider.Object = { GetAll = function() return { "Object", { [13] = { { 40, 50, 42 } }, [12] = { { 10, 20 } } } } end }
	WithProvider(provider, function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1, 2 })
		local locations = a:GetQuestChainStarterLocations(1, 102)
		Equal(#locations, 3); Equal(locations[1].mapID, 102); Equal(locations[1].x, 0.4); Equal(locations[1].phase, 42)
		local none, reason = a:GetQuestChainStarterLocations(2, 101); Equal(#none, 0); Equal(reason, "item_started")
		Equal(a:GetQuestChainStarterLocations(1, 101)[1].mapID, 101)
	end)
end, { offline = true })

QT:RegisterTest("quest chain race and class requirements use provider masks beyond 32 bits", function()
	WithProvider(Provider({ [1] = { requiredRaces = 4294967296, requiredClasses = 128, requiredLevel = 10 } }), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1 })
		Equal(a:EvaluateQuestChainRequirements(1, {}, { level = 10, raceID = 95, classFile = "MAGE" }).state, "met")
		Equal(a:EvaluateQuestChainRequirements(1, {}, { level = 10, raceID = 96, classFile = "MAGE" }).state, "blocked")
		Equal(a:EvaluateQuestChainRequirements(1, {}, { level = 10, raceID = 12345, classFile = "MAGE" }).state, "unknown")
		Equal(a:EvaluateQuestChainRequirements(1, {}, { level = 9, raceID = 95, classFile = "MAGE" }).state, "blocked")
	end)
end, { offline = true })

QT:RegisterTest("quest chain maximum acceptance level becomes permanent only above a known positive level", function()
	WithProvider(Provider({ [1] = { requiredMaxLevel = 10 } }), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1 })
		for _, case in ipairs({
			{ level = 9, state = "met" }, { level = 10, state = "met" },
			{ level = 11, state = "blocked", permanent = true },
			{ state = "unknown" }, { level = 0, state = "unknown" }, { level = -1, state = "unknown" },
		}) do
			local result = a:EvaluateQuestChainRequirements(1, {}, { level = case.level })
			Equal(result.state, case.state, "maximum level boundary " .. tostring(case.level))
			Equal(result.permanentlyBlocked == true, case.permanent == true)
			Equal(#result.requirements, 1)
			local requirement = result.requirements[1]
			Equal(requirement.kind, "max_level"); Equal(requirement.value, 10)
			Equal(requirement.state, case.state); Equal(requirement.permanent == true, case.permanent == true)
		end
	end)
end, { offline = true })

QT:RegisterTest("quest chain recoverable and unevaluated restrictions never acquire permanent blockers", function()
	local rows = {
		[1] = { requiredLevel = 10 }, [2] = { requiredClasses = 128 },
		[3] = { requiredRaces = 4294967296 }, [4] = { preQuestGroup = { 99 } },
		[5] = { exclusiveTo = { 99 } }, [6] = { disabledByQuest = 99 },
		[7] = { parentQuest = 98 }, [8] = { requiredSkill = { 1, 50 } },
		[9] = { requiredMaxLevel = 10, requiredSkill = { 1, 50 } },
		[98] = {}, [99] = {},
	}
	WithProvider(Provider(rows), function()
		local a = Fixture(); a:Open(); a:Flush(); Metadata(a, { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
		local evidence = { [98] = { active = false }, [99] = { active = true, completed = false } }
		local character = { level = 9, classFile = "WARRIOR", raceID = 96 }
		for id = 1, 8 do
			local result = a:EvaluateQuestChainRequirements(id, evidence, character)
			Equal(result.state, id == 8 and "unknown" or "blocked", "restriction " .. id)
			Equal(result.permanentlyBlocked == true, false)
			for _, requirement in ipairs(result.requirements) do Equal(requirement.permanent == true, false) end
		end
		local result = a:EvaluateQuestChainRequirements(9, evidence, { level = 11 })
		Equal(result.state, "blocked"); Equal(result.permanentlyBlocked, true)
		Equal(result.requirements[1].permanent, true); Equal(result.requirements[2].state, "unknown")
		Equal(result.requirements[2].permanent == true, false)
	end)
end, { offline = true })

QT:RegisterTest("native quest chains load asynchronously and never infer requirements or completion from order", function()
	local a, loaded, lineLoads = Fixture("retail"), false, 0
	a.API.GetQuestLineInfo = function(id) if id == 10 or id == 20 then return { questLineID = 70, questLineName = "Native story" } end end
	a.API.GetQuestLineQuests = function() return loaded and { 10, 20 } or nil end
	a.API.RequestQuestLinesForMap = function() lineLoads = lineLoads + 1 end
	a.API.GetQuestChainQuestTitle = function(id) return "Native " .. id end
	a:Open(); Metadata(a, { 10 })
	local partial = a:GetQuestChainGraph(10); Equal(partial.loading, true); Equal(partial.partial, true); Equal(lineLoads, 1)
	loaded = true; a:OnQuestChainDataEvent("QUESTLINE_UPDATE"); a:Flush()
	local graph = a:GetQuestChainGraph(10); Equal(graph.title, "Native story"); Equal(#graph.order, 2)
	Equal(graph.linear, false); Equal(graph.membershipOnly, true); Equal(#graph.edges, 0)
	Equal(a:EvaluateQuestChainRequirements(20, { [10] = { completed = true } }).state, "unknown")
	local old = a.questChainProviderSnapshot; a:OnQuestChainDataEvent("QUEST_DATA_LOAD_RESULT", 9999, true); a:Flush(); Equal(a.questChainProviderSnapshot, old)
	a:OnQuestChainDataEvent("QUESTLINE_UPDATE"); a:CancelQuestChainProvider(a.owner); a:Flush(); Equal(a.questChainProviderSnapshot, old)
end, { offline = true })


QT:RegisterTest("quest chain metadata failures and cancellation cannot publish stale titles or locations", function()
	local rows = { [1] = { name = "Before", requiredLevel = "invalid" } }
	local provider = Provider(rows)
	WithProvider(provider, function()
		local a = Fixture(); a:Open(); a:Flush()
		a:RequestQuestChainMetadata({ 1 }, a.owner)
		local oldGeneration = a.questChainProviderSnapshot.generation
		rows[1].name = "After"
		a:Open(); a:Flush()
		assert(a.questChainProviderSnapshot.generation > oldGeneration)
		Equal(a:GetQuestChainQuestInfo(1), nil, "retired metadata must not enter replacement state")
		Metadata(a, { 1 }); Equal(a:GetQuestChainQuestInfo(1).title, "After")
		Equal(a:EvaluateQuestChainRequirements(1, {}, { level = 60 }).state, "unknown")
		provider.failure = 1
		a:Open(); a:Flush(); Equal(a:GetQuestChainProviderCapability().reason, "provider_failed")
		Equal(a:GetQuestChainQuestInfo(1), nil)
	end)
end, { offline = true })

QT:RegisterTest("native quests with no returned line settle as partial unknown instead of perpetual loading", function()
	local a, requests = Fixture("retail"), 0
	a.API.GetQuestLineInfo = function() return nil end
	a.API.GetQuestLineQuests = function() return nil end
	a.API.GetQuestChainQuestTitle = function() return nil end
	a.API.RequestQuestChainQuestData = function() requests = requests + 1 end
	a.API.RequestQuestLinesForMap = function() end
	a:Open(); Metadata(a, { 10 }); Equal(a:GetQuestChainGraph(10).loading, true)
	a:OnQuestChainDataEvent("QUESTLINE_UPDATE"); a:Flush()
	local graph = a:GetQuestChainGraph(10)
	Equal(graph.loading, false); Equal(graph.partial, true); Equal(graph.reason, "native_line_unknown")
	Equal(requests, 1, "events must not recursively request uncached quest data")
end, { offline = true })


QT:RegisterTest("native chain updates retire removed memberships and respect new request lifetimes", function()
	local a, ids, unknown = Fixture("retail"), { 10, 20 }, false
	a.API.GetQuestLineInfo = function(id) if not unknown and id ~= 30 then return { questLineID = 70 } end end
	a.API.GetQuestLineQuests = function() return ids end
	a.API.GetQuestChainQuestTitle = function(id) return "Quest " .. id end
	a.API.RequestQuestLinesForMap = function() end
	a:Open(); Metadata(a, { 10 }); Equal(a:GetQuestChainGraph(20).lineID, 70)
	ids = { 10 }; a:OnQuestChainDataEvent("QUESTLINE_UPDATE"); a:Flush()
	Equal(a:GetQuestChainGraph(20).lineID, nil, "removed native membership must not survive publication")
	Metadata(a, { 30 }); Equal(a:GetQuestChainGraph(30).loading, true, "a new ID gets its own async lifetime")
	unknown, ids = true, {}; a:OnQuestChainDataEvent("QUESTLINE_UPDATE"); a:Flush()
	Equal(a:GetQuestChainGraph(10).lineID, nil)
	Equal(a:GetQuestChainGraph(10).loading, false)
end, { offline = true })

QT:RegisterTest("native line invalidations re-request once and quest text events do not certify line loading", function()
 local a, requests = Fixture("retail"), 0
 a.API.GetQuestLineInfo = function() return nil end
 a.API.GetQuestLineQuests = function() return nil end
 a.API.GetQuestChainQuestTitle = function() return "Known title" end
 a.API.RequestQuestLinesForMap = function() requests = requests + 1; return true end
 a:Open(); Metadata(a, { 10 }); Equal(requests, 1)
 a:OnQuestChainDataEvent("QUEST_DATA_LOAD_RESULT", 10, true); a:Flush()
 Equal(a:GetQuestChainGraph(10).loading, true)
 a:OnQuestChainDataEvent("QUESTLINE_UPDATE", false); a:Flush()
 Equal(a:GetQuestChainGraph(10).loading, false)
 a:OnQuestChainDataEvent("QUESTLINE_UPDATE", true)
 a:OnQuestChainDataEvent("QUESTLINE_UPDATE", true)
 a:Flush(); Equal(requests, 2)
 a:OnQuestChainDataEvent("QUESTLINE_UPDATE", true); a:Flush(); Equal(requests, 2)
 a:OnQuestChainDataEvent("QUESTLINE_UPDATE", false); a:Flush()
 Equal(a:GetQuestChainGraph(10).loading, false)
 a:OnQuestChainDataEvent("QUESTLINE_UPDATE", true)
 a:CancelQuestChainProvider(a.owner); a:Flush(); Equal(requests, 2)
end, { offline = true })

QT:RegisterTest("native member title reads preserve explicit membership when per-quest info is absent", function()
	local a, ids, reads = Fixture("retail"), { 10, 20 }, {}
	a.API.GetQuestLineInfo = function(id)
		reads[id] = (reads[id] or 0) + 1
		if id == 10 then return { questLineID = 70, questLineName = "Known line" } end
	end
	a.API.GetQuestLineQuests = function() return ids end
	a.API.GetQuestChainQuestTitle = function(id) return "Quest " .. id end
	a:Open(); Metadata(a, { 10, 20 })
	Equal(a:GetQuestChainGraph(20).lineID, 70)
	Equal(a:GetQuestChainGraph(20).title, "Known line")
	Equal(a:GetQuestChainQuestInfo(20).lineID, 70)
	local rootReads = reads[10]
	a:OnQuestChainDataEvent("QUEST_DATA_LOAD_RESULT", 20, true); a:Flush()
	Equal(reads[10], rootReads, "one title reply must not reread unrelated members")
	Equal(a:GetQuestChainGraph(20).lineID, 70)
	ids = nil; a:OnQuestChainDataEvent("QUESTLINE_UPDATE", false); a:Flush()
	Equal(a:GetQuestChainGraph(20).lineID, 70, "unavailable member list does not refute positive membership")
	Equal(a:GetQuestChainGraph(20).partial, true)
	ids = { 10 }; a:OnQuestChainDataEvent("QUESTLINE_UPDATE", false); a:Flush()
	Equal(a:GetQuestChainGraph(20).lineID, nil, "returned list may remove a former member")
end, { offline = true })

QT:RegisterTest("metadata interest retirement cancels unread work and callbacks but retains reusable cache", function()
	local rows, ids = {}, {}
	for id = 1, 1000 do rows[id], ids[id] = { name = "Quest " .. id }, id end
	local provider = Provider(rows)
	WithProvider(provider, function()
		local a = Fixture(); a:Open(); a:Flush()
		local retiredCalls, currentCalls = 0, 0
		a:RequestQuestChainMetadata(ids, a.owner, function() retiredCalls = retiredCalls + 1 end)
		local reads, revision = provider.calls, a.questChainProviderSnapshot.revision
		a:SetQuestChainMetadataInterest({}, a.owner); a:Flush()
		Equal(provider.calls, reads); Equal(retiredCalls, 0)
		Equal(a.questChainProviderSnapshot.revision, revision, "empty retired batches never publish")
		a:SetQuestChainMetadataInterest({ 2 }, a.owner)
		a:RequestQuestChainMetadata({ 2 }, a.owner, function() currentCalls = currentCalls + 1 end); a:Flush()
		Equal(provider.calls, reads + 1); Equal(currentCalls, 1)
		Equal(a:GetQuestChainQuestInfo(2).title, "Quest 2")
		a:RequestQuestChainMetadata({ 3, 4 }, a.owner)
		a:SetQuestChainMetadataInterest({ 2, 4 }, a.owner); a:Flush()
		Equal(a:GetQuestChainQuestInfo(3), nil); Equal(a:GetQuestChainQuestInfo(4).title, "Quest 4")
		a:SetQuestChainMetadataInterest({}, a.owner)
		Equal(a:GetQuestChainQuestInfo(2).title, "Quest 2", "retired demand does not destroy cached data")
		a:SetQuestChainMetadataInterest({ 3 }, a.owner); Metadata(a, { 3 })
		Equal(a:GetQuestChainQuestInfo(3).title, "Quest 3", "later demand can request previously pruned work")
	end)
end, { offline = true })

QT:RegisterTest("retired native interests ignore text replies and keep active root updates", function()
	local a, reads = Fixture("retail"), {}
	a.API.GetQuestLineInfo = function(id) reads[id] = (reads[id] or 0) + 1 end
	a.API.GetQuestLineQuests = function() return {} end
	a.API.GetQuestChainQuestTitle = function(id) return "Quest " .. id end
	a:Open(); Metadata(a, { 10, 20 })
	a:SetQuestChainMetadataInterest({ 10 }, a.owner)
	local revision = a.questChainProviderSnapshot.revision
	a:OnQuestChainDataEvent("QUEST_DATA_LOAD_RESULT", 20, true); a:Flush()
	Equal(a.questChainProviderSnapshot.revision, revision)
	a:OnQuestChainDataEvent("QUESTLINE_UPDATE", false); a:Flush()
	Equal(reads[10], 2); Equal(reads[20], 1)
end, { offline = true })

QT:RegisterTest("metadata failure retires concurrent indexing until explicit provider revalidation", function()
	local rows = {}
	for id = 1, 200 do rows[id] = { name = "Quest " .. id, startedBy = { { 11 } } } end
	local provider = Provider(rows)
	provider.Npc = { GetAll = function() error("broken starter getter") end }
	WithProvider(provider, function()
		local a = Fixture(); a:Open()
		a:RequestQuestChainMetadata({ 1 }, a.owner)
		a:Flush(2) -- One bounded index slice, then the failing metadata slice.
		Equal(a:GetQuestChainProviderCapability().reason, "provider_failed")
		local failed, reads, notices = a.questChainProviderSnapshot, provider.calls, a.notices
		a:Flush()
		Equal(a.questChainProviderSnapshot, failed, "retired index must not publish ready after failure")
		Equal(provider.calls, reads); Equal(a.notices, notices)
		Equal(a:RequestQuestChainMetadata({ 2 }, a.owner), false)
		provider.Npc.GetAll = function() return { "Starter", {} } end
		a:Open(); a:Flush(); Metadata(a, { 1 })
		Equal(a:GetQuestChainProviderCapability().state, "ready")
		Equal(a:GetQuestChainQuestInfo(1).title, "Quest 1")
	end)
end, { offline = true })

QT:RegisterTest("provider diagnostics expose bounded unresolved and pending counts without identities", function()
	WithProvider(Provider({ [1] = { name = "Private quest title", preQuestSingle = { 9999 } } }), function()
		local a = Fixture(); a:Open(); a:Flush()
		a:RequestQuestChainMetadata({ 1 }, a.owner)
		local diagnostics = a:GetQuestChainProviderDiagnostics()
		Equal(diagnostics.nodes, 2); Equal(diagnostics.edges, 1)
		Equal(diagnostics.missingReferences, 1); Equal(diagnostics.unresolvedReferences, 1)
		Equal(diagnostics.pendingMetadata, 1); Equal(diagnostics.requestInterests, 1)
		Equal(diagnostics.metadata, 0); Equal(diagnostics.questIDs, nil); Equal(diagnostics.title, nil)
		a.questChainProviderState.indexDone, a.questChainProviderState.indexTotal = 100001, 100001
		diagnostics = a:GetQuestChainProviderDiagnostics()
		Equal(diagnostics.indexed, 100000); Equal(diagnostics.total, 100000)
		a:SetQuestChainMetadataInterest({}, a.owner)
		diagnostics = a:GetQuestChainProviderDiagnostics()
		Equal(diagnostics.pendingMetadata, 0); Equal(diagnostics.requestInterests, 0)
	end)
end, { offline = true })

QT:RegisterTest("contradictory documented positive requirements remain connected but partial and unknown", function()
	local rows = {
		[1] = {}, [2] = {},
		[10] = { preQuestGroup = { 1 }, exclusiveTo = { 1 } },
		[11] = { preQuestGroup = { 1 }, availableUntilCompleted = 1 },
		[12] = { parentQuest = 1, disabledByQuest = 1 },
		[13] = { parentQuest = 1, exclusiveTo = { 1 } },
		[14] = { preQuestGroup = { 1 }, nextQuestInChain = 1 },
		[15] = { availableStartingWith = 1, exclusiveTo = { 1 } },
		[16] = { availableStartingWith = 1, availableUntilCompleted = 1, disabledByQuest = 1 },
		[17] = { preQuestSingle = { 1 }, exclusiveTo = { 1 } },
		[18] = { preQuestSingle = { 1, 2 }, exclusiveTo = { 1, 2 } },
		[20] = { preQuestSingle = { 1, 2 }, exclusiveTo = { 1 } },
		[21] = { preQuestGroup = { 1 }, parentQuest = 1 },
		[22] = { preQuestGroup = { -1 }, exclusiveTo = { 1 } },
		[23] = { preQuestSingle = { -1, 2 }, exclusiveTo = { 2 } },
		[24] = { childQuests = { 1 }, exclusiveTo = { 1 } },
	}
	WithProvider(Provider(rows), function()
		local a, ids = Fixture(), {}
		for id in pairs(rows) do ids[#ids + 1] = id end
		a:Open(); a:Flush(); Metadata(a, ids)
		for id = 10, 18 do
			local node = a.questChainProviderSnapshot.nodes[id]
			Equal(node.invalid, true); Equal(node.conflicting, true)
			local graph = a:GetQuestChainGraph(id)
			Equal(graph.partial, true); Equal(graph.reasons.conflicting, true); Equal(graph.completeLinearPath, false)
			Equal(a:EvaluateQuestChainRequirements(id, { [1] = { active = true, completed = true } }).state, "unknown")
		end
		for id = 20, 24 do Equal(a.questChainProviderSnapshot.nodes[id].conflicting, nil) end
		Equal(a:GetQuestChainGraph(10).key, a:GetQuestChainGraph(1).key, "contradictions do not cut prerequisite membership")
		Equal(#a.questChainProviderSnapshot.relations[10], 2, "both conflicting facts remain inspectable")
		Equal(a:EvaluateQuestChainRequirements(20, { [1] = { active = false, completed = false }, [2] = { completed = true } }).state, "met")
		Equal(a:EvaluateQuestChainRequirements(21, { [1] = { active = true, completed = true } }).state, "met")
		Equal(a:GetQuestChainProviderDiagnostics().conflicts, 9)
		Equal(a:GetQuestChainProviderCapability().state, "ready", "one conflict does not disable the provider")
		rows[10].exclusiveTo = nil; a:Open(); a:Flush()
		Equal(a.questChainProviderSnapshot.nodes[10].conflicting, nil, "revalidation observes corrected facts")
	end)
end, { offline = true })

_G.QuestTogether:RecordTestModule("scripts/regression_quest_chains.lua")
