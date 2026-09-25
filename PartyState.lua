--[[
QuestTogether Group Roster State

This file now owns only lightweight group identity data:
1) Normalized player/member names.
2) Current party/raid roster membership.
3) Class metadata for grouped players.
]]

local QuestTogether = _G.QuestTogether

QuestTogether.partyMembers = QuestTogether.partyMembers or {}
QuestTogether.partyMemberOrder = QuestTogether.partyMemberOrder or {}
QuestTogether.partyRosterFingerprint = QuestTogether.partyRosterFingerprint or ""

local function SafeText(value, fallback)
	return QuestTogether:SafeToString(value, fallback or "")
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second = pcall(string.match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second
end

local function NormalizeRealmName(addon, realmName)
	if not addon:CanAccessValue(realmName) then
		return nil
	end
	if realmName == nil or realmName == "" then
		realmName = addon.API.GetRealmName() or ""
	end
	if addon and addon.SafeStripWhitespace then
		return addon:SafeStripWhitespace(realmName, "")
	end
	-- Realm values can come from protected APIs; keep fallback normalization non-fatal.
	local okText, textValue = pcall(tostring, realmName)
	if not okText then
		return ""
	end
	local okStrip, stripped = pcall(string.gsub, textValue, "%s+", "")
	if not okStrip then
		return ""
	end
	return stripped
end

local function SortNames(nameList)
	table.sort(nameList, function(left, right)
		return SafeText(left, "") < SafeText(right, "")
	end)
end

function QuestTogether:UsesRegionalPlayerNames()
	local getter = self.API and self.API.RegionalUniqueNamesEnabled
	if type(getter) ~= "function" then
		return false
	end
	local ok, enabled = pcall(getter)
	return ok and self:CanAccessValue(enabled) and enabled == true
end

function QuestTogether:NormalizeMemberName(name)
	name = self:SafeTrimString(name, "")
	if name == "" then
		return nil
	end
	if self:UsesRegionalPlayerNames() then
		-- Forever transports First Surname, while old QT payloads used
		-- First-Surname. Normalize both to the native full identity. Never
		-- append a realm or remove a surname because of a display setting.
		local first, surname = SafeMatch(name, "^([^%s%-]+)%-(.+)$")
		if first and surname then
			return first .. " " .. surname
		end
		return name
	end

	local baseName, realmName = SafeMatch(name, "^([^%-]+)%-(.+)$")
	if not baseName then
		baseName = name
		realmName = NormalizeRealmName(self, nil)
	else
		realmName = NormalizeRealmName(self, realmName)
	end
	if not realmName or realmName == "" then
		return nil
	end

	local normalized = baseName .. "-" .. realmName
	return normalized
end

function QuestTogether:GetUnitFullName(unitToken)
	local name, realm
	if self.API.UnitFullName then
		name, realm = self.API.UnitFullName(unitToken)
	end
	name = self:SafeTrimString(name, "")
	if name == "" then
		return self:NormalizeMemberName(self.API.UnitName and self.API.UnitName(unitToken) or nil)
	end
	if self:UsesRegionalPlayerNames() then
		if not self:CanAccessValue(realm) then
			return nil
		end
		local surname = self:SafeTrimString(realm, "")
		if surname ~= "" and not name:find(" ", 1, true) then
			name = name .. " " .. surname
		end
		return self:NormalizeMemberName(name)
	end
	realm = NormalizeRealmName(self, realm)
	if name == "" or not realm or realm == "" then
		return nil
	end
	return name .. "-" .. realm
end

function QuestTogether:GetPlayerFullName()
	return self:GetUnitFullName("player")
end

function QuestTogether:InitializePartyState()
	self.partyMembers = self.partyMembers or {}
	self.partyMemberOrder = self.partyMemberOrder or {}
	self.partyRosterFingerprint = self.partyRosterFingerprint or ""
end

local function AddUnitToRoster(addon, unitToken, membersByName, orderedNames)
	if not addon.API.UnitExists(unitToken) then
		return
	end

	local fullName = addon:GetUnitFullName(unitToken)

	if not fullName or membersByName[fullName] then
		return
	end

	local _, classFile = addon.API.UnitClass(unitToken)
	classFile = addon:SafeTrimString(classFile, "")
	membersByName[fullName] = {
		fullName = fullName,
		displayName = addon:GetShortDisplayName(fullName),
		classFile = classFile ~= "" and classFile or nil,
	}
	orderedNames[#orderedNames + 1] = fullName
end

function QuestTogether:RefreshPartyRoster()
	local membersByName = {}
	local orderedNames = {}

	AddUnitToRoster(self, "player", membersByName, orderedNames)

	if self.API.IsInRaid() then
		for raidIndex = 1, 40 do
			AddUnitToRoster(self, "raid" .. SafeText(raidIndex, ""), membersByName, orderedNames)
		end
	else
		for partyIndex = 1, 4 do
			AddUnitToRoster(self, "party" .. SafeText(partyIndex, ""), membersByName, orderedNames)
		end
	end

	SortNames(orderedNames)
	self.partyMembers = membersByName
	self.partyMemberOrder = orderedNames
	self.partyRosterFingerprint = table.concat(orderedNames, "|")
end

function QuestTogether:GetPartyRosterFingerprint()
	return self.partyRosterFingerprint or ""
end

function QuestTogether:IsGroupedSender(senderName)
	local normalizedName = self:NormalizeMemberName(senderName)
	if not normalizedName then
		return false
	end
	return self.partyMembers and self.partyMembers[normalizedName] ~= nil
end

function QuestTogether:GetGroupedSenderClassFile(senderName)
	local normalizedName = self:NormalizeMemberName(senderName)
	if not normalizedName then
		return nil
	end

	local member = self.partyMembers and self.partyMembers[normalizedName]
	return member and member.classFile or nil
end
