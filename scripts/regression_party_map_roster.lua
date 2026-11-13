-- Native identity seams only; safe for /qt test without replacing globals.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local function Fixture()
	local a = setmetatable({ isEnabled = true, grouped = true, raid = false, count = 3,
		units = { player = { name = "You-Realm", class = "ROGUE" },
			party1 = { name = "Zed-Realm", class = "MAGE" },
			party2 = { name = "Amy-Realm", class = "WARRIOR" } }, secret = {} }, { __index = QT })
	a.API = {
		IsInAnyGroup = function() return a.grouped end,
		IsInRaid = function() return a.raid end,
		UnitClass = function(unit) local row = a.units[unit]; return row and row.class, row and row.class end,
		UnitRace = function() return a.race or "Human" end,
		UnitLevel = function() return a.level or 60 end,
	}
	function a:CanAccessValue(value) return value ~= self.secret and QT.CanAccessValue(self, value) end
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:GetUnitFullName(unit) return self.units[unit] and self.units[unit].name end
	function a:GetPartyMapNativeGroupCount() return self.count end
	function a:GetPartyMapNativeUnitExists(unit)
		if self.unreadableExists == unit then return nil end
		return self.units[unit] ~= nil
	end
	function a:GetPartyMapNativeSubgroup(unit) return self.units[unit].subgroup end
	function a:GetPartyMapNativeUnitSex() return self.sex or 2 end
	return a
end

QT:RegisterTest("party map roster is stable native identity without network or coordinate evidence", function()
	local a = Fixture()
	local rows = assert(a:GetPartyMapRoster())
	Equal(#rows, 2)
	Equal(rows[1].name, "Amy-Realm")
	Equal(rows[1].unit, "party2")
	Equal(rows[2].name, "Zed-Realm")
	Equal(rows[1].classFile, "WARRIOR")
	Equal(rows[1].level, 60)
	Equal(rows[1].raceName, "Human")
	Equal(rows[1].race, "Human")
	Equal(rows[1].sex, 2)
	assert(rows[1].inSubgroup and rows[1].nativeParty)
	assert(a:IsPartyMapRowCurrent(rows[1]))
	for _, row in ipairs(rows) do
		Equal(row.mapID, nil); Equal(row.x, nil); Equal(row.receivedAt, nil)
	end
	Equal(rawget(a, "playerLocationState"), nil)
	Equal(rawget(a, "peerSnapshotState"), nil)
	Equal(rawget(a, "communicationState"), nil)
	rows[1].name = "Altered"
	Equal(a:GetPartyMapRoster()[1].name, "Amy-Realm")
	-- Full Forever identities survive without display-name shortening.
	a.units.party1.name, a.units.party2.name = "Skye Cinder", "Amy Winters"
	Equal(a:GetPartyMapRoster()[2].name, "Skye Cinder")
end)

QT:RegisterTest("party map roster preserves raid subgroup visibility and excludes the local player", function()
	local a = Fixture()
	a.raid, a.count = true, 4
	a.units = { player = { name = "You-Realm", class = "ROGUE" },
		raid1 = { name = "First-Realm", class = "MAGE", subgroup = true },
		raid2 = { name = "You-Realm", class = "ROGUE", subgroup = true },
		raid3 = { name = "Other-Realm", class = "DRUID", subgroup = false },
		raid40 = { name = "Last-Realm", class = "PRIEST", subgroup = false } }
	local rows = assert(a:GetPartyMapRoster())
	Equal(#rows, 3)
	Equal(rows[1].name, "First-Realm"); Equal(rows[1].inSubgroup, true)
	Equal(rows[2].unit, "raid40"); Equal(rows[2].inSubgroup, false)
	assert(a:IsPartyMapRowCurrent(rows[2]))
	a.units.raid3.subgroup = nil
	Equal(a:GetPartyMapRoster(), nil)
end)

QT:RegisterTest("party map roster fails closed for incomplete inaccessible and changing identities", function()
	for _, change in ipairs({
		function(a) a.grouped = nil end,
		function(a) a.grouped = a.secret end,
		function(a) a.raid = nil end,
		function(a) a.count = 4 end,
		function(a) a.count = 41 end,
		function(a) a.units.player.name = nil end,
		function(a) a.units.party1.name = a.secret end,
		function(a) a.units.party1.name = "Unsafe|name" end,
		function(a) a.units.party1.name = a.units.party2.name end,
		function(a) a.units.party1.name = a.units.player.name end,
		function(a) a.units.party1.class = a.secret end,
		function(a) a.unreadableExists = "party3" end,
		function(a) a.API.IsInRaid = function() error("native read failed") end end,
	}) do
		local a = Fixture(); change(a)
		Equal(a:GetPartyMapRoster(), nil)
	end
	local a = Fixture()
	local calls = 0
	function a:GetUnitFullName(unit)
		if unit == "party1" then calls = calls + 1; return calls > 1 and "Replacement-Realm" or "Zed-Realm" end
		return self.units[unit] and self.units[unit].name
	end
	Equal(a:GetPartyMapRoster(), nil)
end)

QT:RegisterTest("party map optional metadata is sanitized without dropping valid class identity", function()
	local a = Fixture()
	a.level, a.race, a.sex = a.secret, a.secret, a.secret
	local row = assert(a:GetPartyMapRoster())[1]
	Equal(row.level, nil); Equal(row.raceName, nil); Equal(row.sex, nil)
	Equal(row.classFile, "WARRIOR")
end)

QT:RegisterTest("party map actions reject recycled unit tokens stale group modes and retired runtimes", function()
	for _, change in ipairs({
		function(a) a.units.party2.name = "Replacement-Realm" end,
		function(a) a.units.party2 = nil end,
		function(a) a.grouped = false end,
		function(a) a.raid = true end,
		function(a) a.isEnabled = false end,
		function(a) a.isLoggingOut = true end,
		function(a) a.blocked = true end,
		function(a) a.units.party2.name = a.secret end,
	}) do
		local a = Fixture(); local row = assert(a:GetPartyMapRoster())[1]
		assert(a:IsPartyMapRowCurrent(row)); change(a)
		assert(not a:IsPartyMapRowCurrent(row))
	end
	local a = Fixture()
	a.grouped = false
	Equal(#a:GetPartyMapRoster(), 0)
	a.blocked = true
	Equal(a:GetPartyMapRoster(), nil)
end)

_G.QuestTogether:RecordTestModule("scripts/regression_party_map_roster.lua")
