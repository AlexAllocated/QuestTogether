-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local nativeAPI = QT.API
local function WithNative(callback)
	local previousAPI = QT.API
	QT.API = nativeAPI
	local saved = { C_QuestLine = C_QuestLine, C_QuestLog = C_QuestLog, C_Map = C_Map,
		WOW_PROJECT_ID = WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE,
		UnitClass = UnitClass, UnitRace = UnitRace, UnitLevel = UnitLevel, UnitFactionGroup = UnitFactionGroup }
	local restricted, work, names = QT.IsRuntimeRestricted, QT.IsWorkBlocked, QT.UsesRegionalPlayerNames
	local ok, err = pcall(callback)
	for _, key in ipairs({ "C_QuestLine", "C_QuestLog", "C_Map", "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE",
		"UnitClass", "UnitRace", "UnitLevel", "UnitFactionGroup" }) do _G[key] = saved[key] end
	QT.IsRuntimeRestricted, QT.IsWorkBlocked, QT.UsesRegionalPlayerNames = restricted, work, names
	QT.API = previousAPI
	if not ok then error(err, 0) end
end
QT:RegisterTest("native chain adapters sanitize membership and never infer account completion", function()
	WithNative(function()
		QT.IsRuntimeRestricted = function() return false end
		QT.UsesRegionalPlayerNames = function() return false end
		WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
		Equal(QT.API.GetQuestChainClient(), "retail")
		C_QuestLine = nil; Equal(QT.API.CanReadNativeQuestChains(), false)
		local raw = { 7, 8, 7 }
		C_QuestLine = {
			GetQuestLineInfo = function() return { questLineID = 12, questID = 7, questLineName = "Line", isAccountCompleted = true } end,
			GetQuestLineQuests = function() return raw end,
		}
		assert(QT.API.CanReadNativeQuestChains())
		local info = QT.API.GetQuestLineInfo(7)
		Equal(info.questLineID, 12); Equal(info.isAccountCompleted, nil)
		local ids = QT.API.GetQuestLineQuests(12)
		Equal(#ids, 2); raw[1] = 99; Equal(ids[1], 7)
		raw[2] = "not an id"; Equal(QT.API.GetQuestLineQuests(12), nil)
		QT.IsRuntimeRestricted = function() return true end
		Equal(QT.API.GetQuestLineInfo(7), nil); Equal(QT.API.CanReadNativeQuestChains(), false)
	end)
end, { offline = true })
QT:RegisterTest("chain metadata uses stable character identifiers and guards native map browsing", function()
	WithNative(function()
		QT.IsRuntimeRestricted = function() return false end
		UnitClass = function() return "Localized Mage", "MAGE", 8 end
		UnitRace = function() return "Localized Race", "RaceToken", 95 end
		UnitLevel = function() return 20 end
		UnitFactionGroup = function() return "Alliance" end
		local info = QT.API.GetQuestChainUnitInfo("player")
		Equal(info.classFile, "MAGE"); Equal(info.raceID, 95); Equal(info.level, 20)
		Equal(QT.API.GetQuestChainUnitInfo("invalid-unit"), nil)
		local calls = 0
		C_Map = { GetMapInfo = function() return { name = "Map", mapID = 12 } end,
			OpenWorldMap = function(id) Equal(id, 12); calls = calls + 1 end,
			SetUserWaypoint = function() error("browsing changed waypoint") end }
		QT.IsWorkBlocked = function() return true end
		Equal(QT.API.OpenQuestChainMap(12), false); Equal(calls, 0)
		QT.IsWorkBlocked = function() return false end
		assert(QT.API.OpenQuestChainMap(12)); Equal(calls, 1)
		Equal(QT.API.OpenQuestChainMap(-1), false); Equal(calls, 1)
	end)
end, { offline = true })
local function GiverFixture()
	local a = setmetatable({ isEnabled = true, queued = {}, opens = 0, current = true }, { __index = QT })
	a.parent = a:CreateTestUIRegion(a); a.parent:SetSize(1000, 800)
	a.geometry = { parent = a.parent, mapID = 12, width = 1000, height = 800,
		canvasLeft = 0, canvasTop = 0, canvasWidth = 1000, canvasHeight = 800 }
	a.API = { GetMapInfo = function(id) return id == 12 and { name = "Map" } or nil end,
		OpenQuestChainMap = function() a.opens = a.opens + 1; return true end }
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:IsWorkBlocked() return self.blocked == true end
	function a:IsQuestTogetherMapDataShown() return true end
	function a:GetLocationPinSurface() return self.geometry end
	function a:ProjectPlayerLocationPin(_, row, g) return row.x * g.canvasWidth, row.y * g.canvasHeight end
	function a:CreateLocationPinFrame(kind, _, parent) return self:CreateTestUIRegion(self, parent, kind) end
	function a:ScheduleRuntimeWork(_, _, callback) self.queued[#self.queued + 1] = callback end
	function a:CreateOwnedUICleanupFrame() return self:CreateTestUIRegion({}) end
	for _, method in ipairs({ "StopPartyQuestFollow", "OpenPingWaypoint", "Publish", "Request" }) do
		a[method] = function() error("location preview crossed action boundary") end
	end
	function a:Flush() local work = self.queued; self.queued = {}; for _, callback in ipairs(work) do callback() end end
	return a
end
QT:RegisterTest("giver preview marks the chosen location without focus waypoint or network side effects", function()
	local a = GiverFixture()
	assert(a:ShowQuestChainGiver({ mapID = 12, x = .25, y = .75, name = "Quest giver" }, function() return a.current end))
	a:Flush()
	local surface = a.questChainGiverState.surfaces.map
	assert(surface and surface.frame:IsShown()); Equal(surface.pins[1].mapAnchor.x, .25)
	Equal(surface.pins[1].label.text, "Quest giver"); Equal(a.opens, 1)
	a.current = false
	assert(not surface.canShowMapGeometry(), "stationary map retained a retired giver")
	surface.hideMapGeometry()
	assert(not surface.frame:IsShown() and not a.questChainGiverState.selection)
end)
QT:RegisterTest("giver preview rejects invalid locations and retired delayed work", function()
	local a = GiverFixture(); local valid = function() return true end
	assert(not a:ShowQuestChainGiver({ mapID = 12, x = 1.2, y = .5 }, valid)); Equal(a.opens, 0)
	assert(not a:ShowQuestChainGiver({ mapID = 999, x = .2, y = .5 }, valid)); Equal(a.opens, 0)
	assert(a:ShowQuestChainGiver({ mapID = 12, x = .2, y = .5 }, valid))
	a:HideQuestChainGiver(); a:Flush(); Equal(a.questChainGiverState.surfaces.map, nil)
	a.blocked = true; assert(not a:ShowQuestChainGiver({ mapID = 12, x = .2, y = .5 }, valid))
	Equal(a.opens, 1)
end)
QT:RegisterTest("native chain membership expands progressively without inventing prerequisite edges", function()
	local order = {}; for id = 1, 1000 do order[id] = id end
	local a = setmetatable({ questChainProviderSnapshot = { kind = "retail", nodes = {}, metadata = {},
		membership = { [500] = 7 }, lines = { [7] = { title = "Line", order = order } } } }, { __index = QT })
	local graph = a:GetQuestChainGraph(500, { limit = 80, earlier = 39, later = 40 })
	Equal(#graph.order, 80); Equal(graph.order[1], 461); Equal(graph.order[80], 540)
	Equal(graph.total, 1000); assert(graph.moreEarlier and graph.moreLater and graph.partial)
	Equal(#graph.edges, 0); Equal(graph.completeLinearPath, false)
	local expanded = a:GetQuestChainGraph(500, { earlier = 1000, later = 1000 })
	Equal(#expanded.order, 1000); Equal(expanded.partial, false)
	Equal(expanded.lineID, graph.lineID); Equal(expanded.key, graph.key)
	Equal(#expanded.edges, 0)
end, { offline = true })
_G.QuestTogether:RecordTestModule("scripts/regression_quest_chain_boundaries.lua")
