-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table
local Values = QuestTogether.NativeQuestValues
local ReadOptionalString = Values.ReadOptionalString

QuestTogether:RegisterNativeAPI("units", {
	IsInAnyGroup = function()
		-- Keep unknown native state distinct from solo, and inspect both
		-- group categories so instance groups do not depend on roster caches.
		local function Read(query, ...)
			if not CanAccessForeignValue(query) or type(query) ~= "function" then
				return nil
			end
			local ok, value = pcall(query, ...)
			if ok and CanAccessForeignValue(value) and type(value) == "boolean" then
				return value
			end
		end
		local grouped, raid = Read(IsInGroup), Read(IsInRaid)
		-- Older clients may omit the category constant. Their generic native
		-- membership query still decides solo; unreadable data stays unknown.
		local category, instance = LE_PARTY_CATEGORY_INSTANCE, false
		if not CanAccessForeignValue(category) then
			instance = nil
		elseif category ~= nil then
			if type(category) == "number" then
				instance = Read(IsInGroup, category)
			else
				instance = nil
			end
		end
		if grouped == true or raid == true or instance == true then
			return true
		end
		if grouped == false and raid == false and instance == false then
			return false
		end
		return nil
	end,
	IsInInstanceGroup = function()
		return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
	end,
	IsInGroup = function()
		if type(IsInGroup) ~= "function" then
			return false
		end
		local ok, grouped = pcall(IsInGroup)
		return ok and CanAccessForeignValue(grouped) and grouped == true
	end,
	IsInParty = function()
		return UnitInParty("player")
	end,
	IsInRaid = function()
		return IsInRaid()
	end,
	IsInInstance = function()
		local inInstance = IsInInstance()
		return inInstance and true or false
	end,
	UnitExists = function(unitToken)
		local ok, exists = pcall(UnitExists, unitToken)
		return ok and CanAccessForeignValue(exists) and exists == true
	end,
	UnitIsUnit = function(leftUnitToken, rightUnitToken)
		if type(UnitIsUnit) ~= "function" then
			return false
		end
		local ok, isSameUnit = pcall(UnitIsUnit, leftUnitToken, rightUnitToken)
		if not ok or not CanAccessForeignValue(isSameUnit) then
			return false
		end
		return isSameUnit and true or false
	end,
	UnitGUID = function(unitToken)
		local ok, guidValue = pcall(UnitGUID, unitToken)
		if not ok or not CanAccessForeignValue(guidValue) then
			return nil
		end
		return guidValue
	end,
	UnitFullName = function(unitToken)
		local ok, rawUnitName, rawUnitRealm = pcall(UnitFullName, unitToken)
		if not ok then
			return nil, nil
		end
		return ReadOptionalString(rawUnitName), ReadOptionalString(rawUnitRealm)
	end,
	RegionalUniqueNamesEnabled = function()
		if type(RegionalUniqueNamesEnabled) ~= "function" then
			return false
		end
		local ok, enabled = pcall(RegionalUniqueNamesEnabled)
		if ok and CanAccessForeignValue(enabled) and type(enabled) == "boolean" then
			return enabled
		end
		return nil
	end,
	ShouldDisplaySurname = function()
		if not CanAccessForeignTable(C_PlayerInfo) then
			return nil
		end
		local getter = C_PlayerInfo.ShouldDisplaySurname
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil
		end
		local ok, display = pcall(getter)
		if ok and CanAccessForeignValue(display) and type(display) == "boolean" then
			return display
		end
		return nil
	end,
	UnitClass = function(unitToken)
		local ok, rawClassName, rawClassFile = pcall(UnitClass, unitToken)
		if not ok then
			return nil, nil
		end
		return ReadOptionalString(rawClassName), ReadOptionalString(rawClassFile)
	end,
	UnitRace = function(unitToken)
		local ok, raceName = pcall(UnitRace, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(raceName) then
			return nil
		end
		return raceName
	end,
	GetPlayerRaceID = function()
		local ok, _, _, raceID = pcall(UnitRace, "player")
		local id = ok and QuestTogether:SafeToNumber(raceID) or nil
		return id and id >= 1 and id <= 100000 and id == math.floor(id) and id or nil
	end,
	GetLocalizedRaceName = function(raceID)
		local id = QuestTogether:SafeToNumber(raceID)
		if not id or id < 1 or id > 100000 or id ~= math.floor(id) or not CanAccessForeignTable(C_CreatureInfo) then
			return nil
		end
		local getter = C_CreatureInfo.GetRaceInfo
		if not CanAccessForeignValue(getter) or type(getter) ~= "function" then
			return nil
		end
		local ok, info = pcall(getter, id)
		if not ok or not CanAccessForeignTable(info) then
			return nil
		end
		return ReadOptionalString(info.raceName)
	end,
	GetLocalizedClassName = function(classFile)
		local token = ReadOptionalString(classFile)
		if not token or not CanAccessForeignTable(LOCALIZED_CLASS_NAMES_MALE) then
			return nil
		end
		return ReadOptionalString(LOCALIZED_CLASS_NAMES_MALE[token])
	end,
	UnitLevel = function(unitToken)
		local ok, levelValue = pcall(UnitLevel, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(levelValue) then
			return nil
		end
		return levelValue
	end,
	UnitName = function(unitToken)
		local ok, unitName = pcall(UnitName, unitToken)
		if not ok or not CanAccessForeignValue(unitName) then
			return nil
		end
		return unitName
	end,
	UnitHealth = function(unitToken)
		local ok, unitHealth = pcall(UnitHealth, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(unitHealth) then
			return nil
		end
		return unitHealth
	end,
	UnitHealthMax = function(unitToken)
		local ok, maxHealth = pcall(UnitHealthMax, unitToken)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(maxHealth) then
			return nil
		end
		return maxHealth
	end,
	UnitIsDeadOrGhost = function(unitToken)
		if type(UnitIsDeadOrGhost) == "function" then
			local ok, result = pcall(UnitIsDeadOrGhost, unitToken)
			return ok and result and true or false
		end
		if type(UnitIsDead) == "function" then
			local ok, result = pcall(UnitIsDead, unitToken)
			return ok and result and true or false
		end
		return false
	end,
	UnitIsFriend = function(left, right)
		if type(UnitIsFriend) ~= "function" then
			return nil
		end
		local ok, friendly = pcall(UnitIsFriend, left, right)
		if ok and CanAccessForeignValue(friendly) and type(friendly) == "boolean" then
			return friendly
		end
		return nil
	end,
	UnitIsPlayer = function(unitToken)
		local ok, result = pcall(UnitIsPlayer, unitToken)
		return ok and CanAccessForeignValue(result) and result == true
	end,
	GetLayerObservationUnit = function(unitToken)
		-- All results are checked before use; observations never mutate native units.
		if
			not CanAccessForeignValue(unitToken)
			or type(unitToken) ~= "string"
			or (
				unitToken ~= "target"
				and unitToken ~= "mouseover"
				and unitToken ~= "focus"
				and not unitToken:match("^nameplate%d+$")
				and not unitToken:match("^party%d+$")
				and not unitToken:match("^raid%d+$")
			)
		then
			return nil
		end
		if type(UnitGUID) ~= "function" then
			return nil
		end
		local okGUID, guid = pcall(UnitGUID, unitToken)
		if not okGUID or not CanAccessForeignValue(guid) or type(guid) ~= "string" then
			return nil
		end
		local phaseMismatch = false
		if type(UnitPhaseReason) == "function" then
			local ok, reason = pcall(UnitPhaseReason, unitToken)
			if not ok or not CanAccessForeignValue(reason) then
				return nil
			end
			if reason ~= nil then
				local reasons = CanAccessForeignTable(Enum) and Enum.PhaseReason
				if type(reason) ~= "number" or not CanAccessForeignTable(reasons) then
					return nil
				end
				for _, value in pairs(reasons) do
					if CanAccessForeignValue(value) and type(value) == "number" and reason == value then
						phaseMismatch = true
						break
					end
				end
				if not phaseMismatch or #guid > 48 or not guid:match("^Player%-%d+%-%x+$") then
					return nil
				end
				-- A readable native Player GUID supplies identity. Explicit phase
				-- evidence needs no additional loaded-unit or visibility flags.
				return { guid = guid, controlled = true, phaseMismatch = true }
			end
		elseif type(UnitInPhase) == "function" then
			local ok, inPhase = pcall(UnitInPhase, unitToken)
			if not ok or not CanAccessForeignValue(inPhase) or type(inPhase) ~= "boolean" then
				return nil
			end
			phaseMismatch = not inPhase
		end
		-- Legacy UnitInPhase(false) also needs native presence: it supplies
		-- no reason that distinguishes an absent unit from another phase.
		for _, query in ipairs({ "UnitExists", "UnitIsVisible" }) do
			local fn = _G[query]
			if type(fn) ~= "function" then
				return nil
			end
			local ok, value = pcall(fn, unitToken)
			if not ok or not CanAccessForeignValue(value) or value ~= true then
				return nil
			end
		end
		if type(UnitPlayerControlled) ~= "function" then
			return nil
		end
		local okControlled, controlled = pcall(UnitPlayerControlled, unitToken)
		if not okControlled or not CanAccessForeignValue(controlled) or type(controlled) ~= "boolean" then
			return nil
		end
		if phaseMismatch then
			if
				not controlled
				or #guid > 48
				or not guid:match("^Player%-%d+%-%x+$")
				or type(UnitIsPlayer) ~= "function"
			then
				return nil
			end
			local ok, player = pcall(UnitIsPlayer, unitToken)
			if not ok or not CanAccessForeignValue(player) or player ~= true then
				return nil
			end
			return { guid = guid, controlled = true, phaseMismatch = true }
		end
		return { guid = guid, controlled = controlled }
	end,
	CanTargetUnitForEmote = function(unitToken)
		if not CanAccessForeignValue(unitToken) or type(unitToken) ~= "string" then
			return false
		end
		-- A name or a map dot is not evidence that the unit is in this layer.
		if
			unitToken ~= "target"
			and unitToken ~= "mouseover"
			and unitToken ~= "focus"
			and not unitToken:match("^nameplate%d+$")
		then
			return false
		end
		for _, query in ipairs({ "UnitExists", "UnitIsPlayer", "UnitIsVisible" }) do
			local fn = _G[query]
			if type(fn) ~= "function" then
				return false
			end
			local ok, value = pcall(fn, unitToken)
			if not ok or not CanAccessForeignValue(value) or value ~= true then
				return false
			end
		end
		if type(UnitPhaseReason) == "function" then
			local ok, reason = pcall(UnitPhaseReason, unitToken)
			if not ok or not CanAccessForeignValue(reason) or reason ~= nil then
				return false
			end
		elseif type(UnitInPhase) == "function" then
			local ok, inPhase = pcall(UnitInPhase, unitToken)
			if not ok or not CanAccessForeignValue(inPhase) or inPhase ~= true then
				return false
			end
		end
		return true
	end,
	GetPartyJoinInfo = function()
		-- Flat copied primitives only. Unknown native state is not solo.
		local function Read(fn, ...)
			if not CanAccessForeignValue(fn) or type(fn) ~= "function" then
				return nil
			end
			local ok, value = pcall(fn, ...)
			if ok and CanAccessForeignValue(value) then
				return value
			end
		end
		local grouped, raid = Read(IsInGroup), Read(IsInRaid)
		local instance = Read(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
		local count = Read(GetNumGroupMembers)
		if
			type(grouped) ~= "boolean"
			or type(raid) ~= "boolean"
			or type(instance) ~= "boolean"
			or type(count) ~= "number"
			or count ~= count
			or count < 0
			or count > 40
		then
			return nil
		end
		local canInvite = false
		if CanAccessForeignTable(C_PartyInfo) then
			canInvite = Read(C_PartyInfo.CanInvite) == true
		end
		return grouped,
			canInvite and not raid and not instance and count < 5,
			count,
			grouped and not raid and not instance and count >= 2 and count < 5
	end,
	IsPartyFocusUnitConnected = function(unit)
		if
			QuestTogether:IsRuntimeRestricted()
			or not CanAccessForeignValue(unit)
			or type(unit) ~= "string"
			or not CanAccessForeignValue(UnitIsConnected)
			or type(UnitIsConnected) ~= "function"
		then
			return nil
		end
		local ok, connected = pcall(UnitIsConnected, unit)
		return ok and CanAccessForeignValue(connected) and type(connected) == "boolean" and connected or false
	end,
	GetPartyVisualLeaderUnit = function()
		if
			QuestTogether:IsRuntimeRestricted()
			or not CanAccessForeignValue(UnitIsGroupLeader)
			or type(UnitIsGroupLeader) ~= "function"
			or not CanAccessForeignValue(IsInRaid)
			or type(IsInRaid) ~= "function"
		then
			return nil
		end
		local ok, raid = pcall(IsInRaid)
		if not ok or not CanAccessForeignValue(raid) or type(raid) ~= "boolean" then
			return nil
		end
		for index = 0, raid and 40 or 4 do
			local unit = index == 0 and "player" or (raid and "raid" or "party") .. index
			local valid, leader = pcall(UnitIsGroupLeader, unit)
			if not valid or not CanAccessForeignValue(leader) or type(leader) ~= "boolean" then
				return nil
			end
			if leader then
				return unit
			end
		end
	end,
	GetPartyJoinLeaderUnit = function()
		if
			QuestTogether:IsRuntimeRestricted()
			or not CanAccessForeignValue(UnitIsGroupLeader)
			or type(UnitIsGroupLeader) ~= "function"
		then
			return nil
		end
		for index = 1, 4 do
			local unit = "party" .. index
			local ok, leader = pcall(UnitIsGroupLeader, unit)
			if not ok or not CanAccessForeignValue(leader) or type(leader) ~= "boolean" then
				return nil
			end
			if leader then
				return unit
			end
		end
	end,
	IsPartyJoinFriend = function(name)
		-- Exact normalized character identity; never use display-name shortening
		-- or sender-provided friendship. This is the character friends list.
		if not CanAccessForeignValue(name) or type(name) ~= "string" then
			return false
		end
		if not CanAccessForeignTable(C_FriendList) then
			return false
		end
		local query = C_FriendList.GetFriendInfo
		if not CanAccessForeignValue(query) or type(query) ~= "function" then
			return false
		end
		local ok, info = pcall(query, name)
		if not ok or not CanAccessForeignTable(info) then
			return false
		end
		local friendName = info.name
		if not CanAccessForeignValue(friendName) or type(friendName) ~= "string" then
			return false
		end
		return QuestTogether:NormalizeMemberName(friendName) == QuestTogether:NormalizeMemberName(name)
	end,
	IsPlayerTooltipFriend = function(guid, name)
		if
			not CanAccessForeignValue(guid)
			or type(guid) ~= "string"
			or guid == ""
			or not CanAccessForeignValue(name)
			or type(name) ~= "string"
		then
			return false
		end
		-- Native GUID lookups cover character and Battle.net friendships without
		-- rescanning either list or retaining a second social roster for tooltips.
		local friend = Access.Call(C_FriendList, "IsFriend", guid)
		if CanAccessForeignValue(friend) and friend == true then
			return true
		end
		local account = Access.Call(C_BattleNet, "GetAccountInfoByGUID", guid)
		if CanAccessForeignTable(account) and CanAccessForeignValue(account.isFriend) and account.isFriend == true then
			return true
		end
		-- Older clients may expose only the exact character-name lookup.
		local info = Access.Call(C_FriendList, "GetFriendInfo", name)
		return CanAccessForeignTable(info)
			and CanAccessForeignValue(info.name)
			and type(info.name) == "string"
			and QuestTogether:NormalizeMemberName(info.name) == QuestTogether:NormalizeMemberName(name)
	end,
	InviteUnit = function(name)
		if
			QuestTogether:IsRuntimeRestricted()
			or not CanAccessForeignValue(name)
			or type(name) ~= "string"
			or name == ""
		then
			return false
		end
		if not CanAccessForeignTable(C_PartyInfo) then
			return false
		end
		local invite = C_PartyInfo.InviteUnit
		if not CanAccessForeignValue(invite) or type(invite) ~= "function" then
			return false
		end
		local ok, result = pcall(invite, name)
		-- The native API has no success return. This means attempted, not joined.
		return ok and CanAccessForeignValue(result) and result ~= false
	end,
	UnitInParty = function(unitToken)
		local ok, result = pcall(UnitInParty, unitToken)
		return ok and result and true or false
	end,
	UnitInRaid = function(unitToken)
		local ok, result = pcall(UnitInRaid, unitToken)
		return ok and result and true or false
	end,
	Ambiguate = function(name, context)
		local ok, result = pcall(Ambiguate, name, context)
		if not ok then
			return nil
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(result) then
			return nil
		end
		return result
	end,
	GetRealmName = function()
		local ok, realmName = pcall(GetRealmName)
		if not ok then
			return ""
		end
		if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(realmName) then
			return ""
		end
		return realmName
	end,
	GetFaction = function()
		local faction = UnitFactionGroup("player")
		return faction
	end,
	IsMounted = function()
		return IsMounted()
	end,
	DoEmote = function(emoteToken, target)
		local performEmote = C_ChatInfo and C_ChatInfo.PerformEmote
		if type(performEmote) ~= "function" then
			performEmote = DoEmote
		end
		if type(performEmote) ~= "function" then
			return false
		end
		local ok = pcall(performEmote, emoteToken, target)
		return ok
	end,
})
