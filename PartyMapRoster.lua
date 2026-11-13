-- Native group identities for the world map only. These rows are presentation
-- data, never peer observations, discovery evidence or shared coordinates.
local QT = _G.QuestTogether
local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
	DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
	DRUID = true, DEMONHUNTER = true, EVOKER = true }

local function Read(a, fn, ...)
	if not a:CanAccessValue(fn) or type(fn) ~= "function" then return nil end
	local ok, first, second, third = pcall(fn, ...)
	if not ok then return nil end
	if not a:CanAccessValue(first) then first = nil end
	if not a:CanAccessValue(second) then second = nil end
	if not a:CanAccessValue(third) then third = nil end
	return first, second, third
end
local function Integer(a, value, low, high)
	value = a:SafeToNumber(value)
	return value and value == math.floor(value) and value >= low and value <= high and value or nil
end
local function Text(a, value, limit)
	if not a:CanAccessValue(value) or type(value) ~= "string" then return nil end
	if #value == 0 or #value > limit or value:find("[%c|]") then return nil end
	return value
end
local function Available(a)
	return a.isEnabled and not a.isLoggingOut and not a:IsRuntimeRestricted()
end

-- Separate native seams preserve unreadable state instead of treating it as
-- an empty group. Private fixtures override these without touching globals.
function QT:GetPartyMapNativeGroupCount()
	if self ~= QT then return nil end
	return Integer(self, Read(self, GetNumGroupMembers), 0, 40)
end
function QT:GetPartyMapNativeUnitExists(unit)
	if self ~= QT then return nil end
	local exists = Read(self, UnitExists, unit)
	if type(exists) == "boolean" then return exists end
end
function QT:GetPartyMapNativeSubgroup(unit)
	if self ~= QT then return nil end
	local member = Read(self, UnitInSubgroup, unit)
	if type(member) == "boolean" then return member end
	local index = tonumber(unit:match("^raid(%d+)$"))
	local own = Integer(self, Read(self, UnitInRaid, "player"), 1, 40)
	if not index or not own then return nil end
	local _, _, ownGroup = Read(self, GetRaidRosterInfo, own)
	local _, _, group = Read(self, GetRaidRosterInfo, index)
	ownGroup, group = Integer(self, ownGroup, 1, 8), Integer(self, group, 1, 8)
	if ownGroup and group then return ownGroup == group end
end
function QT:GetPartyMapNativeUnitSex(unit)
	if self ~= QT then return nil end
	return Integer(self, Read(self, UnitSex, unit), 1, 3)
end

local function Group(a)
	local grouped = Read(a, a.API and a.API.IsInAnyGroup)
	if grouped == false then return false, false, 0 end
	if grouped ~= true then return nil end
	local raid = Read(a, a.API and a.API.IsInRaid)
	local count = Integer(a, a:GetPartyMapNativeGroupCount(), 1, 40)
	if type(raid) ~= "boolean" or not count or (not raid and count > 5) then return nil end
	return true, raid, count
end
local function Name(a, unit)
	return Text(a, Read(a, a.GetUnitFullName, a, unit), 120)
end

function QT:GetPartyMapRoster()
	if not Available(self) then return nil end
	local grouped, raid, count = Group(self)
	if grouped == nil then return nil end
	if not grouped then return {} end
	local own = Name(self, "player")
	if not own then return nil end
	local rows, names, found = {}, {}, raid and 0 or 1
	for index = 1, raid and 40 or 4 do
		local unit = (raid and "raid" or "party") .. index
		local exists = self:GetPartyMapNativeUnitExists(unit)
		if type(exists) ~= "boolean" then return nil end
		if exists then
			local name = Name(self, unit)
			if not name or names[name] or (not raid and name == own) then return nil end
			names[name], found = true, found + 1
			if name ~= own then
				local className, classFile = Read(self, self.API and self.API.UnitClass, unit)
				classFile = Text(self, classFile, 32)
				-- Class identity drives native icon ownership, so incomplete class
				-- data leaves the entire native group renderer as the fallback.
				if not classFile or not CLASSES[classFile] then return nil end
				local inSubgroup = not raid
				if raid then inSubgroup = self:GetPartyMapNativeSubgroup(unit) end
				if type(inSubgroup) ~= "boolean" then return nil end
				local race = Text(self, Read(self, self.API and self.API.UnitRace, unit), 64)
				rows[#rows + 1] = {
					unit = unit, name = name, classFile = classFile,
					className = Text(self, className, 64), raceName = race, race = race,
					level = Integer(self, Read(self, self.API and self.API.UnitLevel, unit), 1, 1000),
					sex = Integer(self, self:GetPartyMapNativeUnitSex(unit), 1, 3),
					inSubgroup = inSubgroup, nativeParty = true,
				}
			end
		end
	end
	if found ~= count or (raid and not names[own]) then return nil end
	-- Roster events may replace unit tokens while a native call is executing.
	local currentGrouped, currentRaid, currentCount = Group(self)
	if currentGrouped ~= true or currentRaid ~= raid or currentCount ~= count then return nil end
	for _, row in ipairs(rows) do
		if Name(self, row.unit) ~= row.name then return nil end
	end
	table.sort(rows, function(left, right) return left.name < right.name end)
	return rows
end

function QT:IsPartyMapRowCurrent(row)
	if not Available(self) or not self:CanAccessTable(row)
		or not self:CanAccessValue(row.nativeParty) or row.nativeParty ~= true then return false end
	local unit, name = Text(self, row.unit, 8), Text(self, row.name, 120)
	if not unit or not name then return false end
	local grouped, raid = Group(self)
	if grouped ~= true then return false end
	local index = tonumber(unit:match(raid and "^raid(%d+)$" or "^party(%d+)$"))
	if not index or index < 1 or index > (raid and 40 or 4)
		or self:GetPartyMapNativeUnitExists(unit) ~= true then return false end
	local own, current = Name(self, "player"), Name(self, unit)
	return own ~= nil and current == name and current ~= own
end
