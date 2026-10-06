-- Offline-only client contracts. No real game globals are changed by these checks.
return function(client)
	local profiles = { retail = "12.1.0", forever = "1.60.1", era = "1.15.9", tbc = "2.5.6", mists = "5.5.4", titan = "3.80.2" }
	assert(profiles[client], "unknown client profile")
	local classic = client ~= "retail" and client ~= "forever"
	local selected, pushable, secret = 7, true, {}
	local inaccessibleReads = 0
	local inaccessible = setmetatable({}, {
		__index = function()
			inaccessibleReads = inaccessibleReads + 1
			error("inaccessible fixture must not be indexed")
		end,
		__tostring = function() error("inaccessible fixture must not be formatted") end,
	})
	local objective = { text = "Wolves slain: 2/5", type = "monster", finished = false, numFulfilled = 2, numRequired = 5 }
	issecretvalue = function(value) return value == secret end
	canaccessvalue = function(value) return value ~= inaccessible end
	canaccesstable = function(value) return value ~= inaccessible end
	GetBuildInfo = function() return profiles[client], "fixture", "", 0 end
	local function Info(index)
		if index == 7 then return { questID = 12345, title = "Wolf Hunt", isHeader = false, isComplete = false } end
		return { questID = 54321, title = "Another quest", isHeader = false, isComplete = false }
	end
	GetNumQuestLogEntries = classic and function() return 7 end or nil
	GetQuestLogTitle = classic and function(index)
		local row = Info(index)
		return row.title, 20, nil, false, false, nil, nil, row.questID
	end or nil
	GetQuestLogSelection = function() return selected end
	GetQuestLogPushable = function() return pushable end
	SelectQuestLogEntry = function() error("addon must not move selected quest") end
	GetNumQuestLeaderBoards = function(index) assert(index == 7)
return 1 end
	C_QuestLog = {
		GetQuestObjectives = function(id) assert(id == 12345)
return { objective } end,
		GetInfo = not classic and Info or nil,
		GetLogIndexForQuestID = not classic and function(id) assert(id == 12345)
return 7 end or nil,
		SetSelectedQuest = function() error("addon must not move selected quest") end,
		GetNumQuestLogEntries = not classic and function() return 7 end or nil,
		IsPushableQuest = not classic and function(id) assert(id == 12345)
return pushable end or nil,
	}
	GetQuestObjectiveInfo = not classic and function(id, index)
		assert(id == 12345 and index == 1)
		return objective.text, objective.type, objective.finished, objective.numFulfilled
	end or nil
	return function(addon)
		do
			-- Offline only: exercise native visibility/phase access failures without
			-- replacing any globals during the live /qt test suite.
			local keys = { "UnitExists", "UnitIsPlayer", "UnitIsVisible", "UnitPhaseReason", "UnitInPhase" }
			local saved = {}
			for _, key in ipairs(keys) do saved[key] = _G[key] end
			local function Visible()
				UnitExists = function() return true end
				UnitIsPlayer = function() return true end
				UnitIsVisible = function() return true end
				UnitPhaseReason = function() return nil end
				UnitInPhase = nil
			end
			Visible()
			for _, unit in ipairs({ "target", "focus", "mouseover", "nameplate1" }) do
				assert(addon.API.CanTargetUnitForEmote(unit))
			end
			for _, unit in ipairs({ "Friend-Realm", "player", "", secret, inaccessible }) do
				assert(not addon.API.CanTargetUnitForEmote(unit))
			end
			for _, key in ipairs({ "UnitExists", "UnitIsPlayer", "UnitIsVisible" }) do
				for _, result in ipairs({ false, 1, secret, inaccessible }) do
					Visible(); _G[key] = function() return result end
					assert(not addon.API.CanTargetUnitForEmote("target"))
				end
				Visible(); _G[key] = nil
				assert(not addon.API.CanTargetUnitForEmote("target"))
				Visible(); _G[key] = function() error("restricted unit query") end
				assert(not addon.API.CanTargetUnitForEmote("target"))
			end
			for _, reason in ipairs({ 0, 1, secret, inaccessible }) do
				Visible(); UnitPhaseReason = function() return reason end
				assert(not addon.API.CanTargetUnitForEmote("target"))
			end
			Visible(); UnitPhaseReason = function() error("restricted phase query") end
			assert(not addon.API.CanTargetUnitForEmote("target"))
			Visible(); UnitPhaseReason = nil
			assert(addon.API.CanTargetUnitForEmote("target"))
			UnitInPhase = function() return true end
			assert(addon.API.CanTargetUnitForEmote("target"))
			for _, result in ipairs({ false, secret, inaccessible }) do
				UnitInPhase = function() return result end
				assert(not addon.API.CanTargetUnitForEmote("target"))
			end
			UnitInPhase = function() error("restricted legacy phase query") end
			assert(not addon.API.CanTargetUnitForEmote("target"))
			for _, key in ipairs(keys) do _G[key] = saved[key] end
		end
		do
			local original = GetServerTime
			GetServerTime = function() return 1791086400 end
			assert(addon.API.GetServerTime() == 1791086400)
			GetServerTime = function() return secret end
			assert(addon.API.GetServerTime() == nil)
			GetServerTime = function() error("unavailable") end
			assert(addon.API.GetServerTime() == nil)
			GetServerTime = nil
			assert(addon.API.GetServerTime() == nil)
			GetServerTime = original
		end
		do
			local oldUtil, oldLegacy, oldRestricted = ChatFrameUtil, ChatFrame_OpenChat, addon.IsRuntimeRestricted
			local calls, restricted = 0, false
			addon.IsRuntimeRestricted = function() return restricted end
			local function OpenChat(text, preferred)
				assert(text == "/qt " and preferred == nil)
				calls = calls + 1
			end
			for _, legacy in ipairs({ false, true }) do
				ChatFrameUtil = not legacy and { OpenChat = OpenChat } or nil
				ChatFrame_OpenChat = legacy and OpenChat or nil
				assert(addon.API.OpenQTChatComposer() == true)
				local before = calls
				restricted = true
				assert(addon.API.OpenQTChatComposer() == false and calls == before)
				restricted = false
			end
			for _, value in ipairs({ secret, inaccessible, function() error("unavailable") end, function() return false end }) do
				ChatFrameUtil, ChatFrame_OpenChat = { OpenChat = value }, nil
				assert(addon.API.OpenQTChatComposer() == false)
			end
			ChatFrameUtil, ChatFrame_OpenChat = inaccessible, nil
			local before = inaccessibleReads
			assert(addon.API.OpenQTChatComposer() == false and inaccessibleReads == before)
			ChatFrameUtil, ChatFrame_OpenChat = nil, nil
			assert(addon.API.OpenQTChatComposer() == false)
			ChatFrameUtil, ChatFrame_OpenChat, addon.IsRuntimeRestricted = oldUtil, oldLegacy, oldRestricted
		end
		do
			local oldMap, oldTrack, oldQuest, oldBlocked = C_Map, C_SuperTrack, C_QuestLog, addon.IsRuntimeRestricted
			local blocked, active, id, owns, writes = false, true, 123, true, 0
			local waypoint = { uiMapID = 37, position = { GetXY = function() return 0.4, 0.5 end } }
			addon.IsRuntimeRestricted = function() return blocked end
			C_Map = { GetUserWaypoint = function() return waypoint end }
			C_QuestLog = { IsOnQuest = function() return owns end }
			C_SuperTrack = {
				IsSuperTrackingQuest = function() return active end,
				GetSuperTrackedQuestID = function() return id end,
				SetSuperTrackedQuestID = function(value) writes = writes + 1; id = value; active = true end,
			}
			local p = addon.API.GetPartyNavigationNativeState()
			assert(p.questID == 123 and p.mapID == 37 and p.x == 0.4 and p.y == 0.5)
			assert(addon.API.SetPartyNavigationQuest(456) == true and writes == 1)
			owns = false; assert(addon.API.SetPartyNavigationQuest(789) == false and writes == 1)
			owns = true; C_SuperTrack.SetSuperTrackedQuestID = function() writes = writes + 1 end
			assert(addon.API.SetPartyNavigationQuest(789) == false and writes == 2)
			active, waypoint = false, nil
			p = addon.API.GetPartyNavigationNativeState(); assert(p.questID == 0 and p.mapID == 0)
			for _, value in ipairs({ secret, inaccessible }) do
				waypoint = value; assert(addon.API.GetPartyNavigationNativeState() == nil)
				waypoint = { uiMapID = value, position = { GetXY = function() return 0.4, 0.5 end } }
				assert(addon.API.GetPartyNavigationNativeState() == nil)
				waypoint = { uiMapID = 37, position = value }
				assert(addon.API.GetPartyNavigationNativeState() == nil)
				waypoint = { uiMapID = 37, position = { GetXY = value } }
				assert(addon.API.GetPartyNavigationNativeState() == nil)
				C_SuperTrack.SetSuperTrackedQuestID = value
				assert(addon.API.SetPartyNavigationQuest(123) == false)
			end
			blocked = true
			C_Map.GetUserWaypoint = function() error("restricted read") end
			assert(addon.API.GetPartyNavigationNativeState() == nil and addon.API.SetPartyNavigationQuest(123) == false)
			blocked = false; C_Map, C_SuperTrack = {}, {}
			p = addon.API.GetPartyNavigationNativeState(); assert(p.questID == -1 and p.mapID == -1)
			C_Map, C_SuperTrack, C_QuestLog, addon.IsRuntimeRestricted = oldMap, oldTrack, oldQuest, oldBlocked
			assert(inaccessibleReads == 0)
		end
		-- Native tracking is read-only: a waypoint is not a quest, even if a
		-- previously tracked quest ID remains cached by the engine.
		do
			local oldTrack, oldBlocked, oldSensitive = C_SuperTrack, addon.IsRuntimeRestricted, addon.IsMapTooltipSensitiveStateActive
			local blocked, active, id, reads = false, true, 12345, 0
			addon.IsRuntimeRestricted = function() return blocked end
			C_SuperTrack = {
				IsSuperTrackingQuest = function() return active end,
				GetSuperTrackedQuestID = function() reads = reads + 1; return id end,
			}
			addon.IsMapTooltipSensitiveStateActive = function() return true end
			assert(addon.API.GetActiveTrackedQuestID() == 12345 and reads == 1)
			for _, value in ipairs({ false, secret, inaccessible }) do
				active = value; assert(addon.API.GetActiveTrackedQuestID() == nil and reads == 1)
			end
			active, blocked = true, true
			assert(addon.API.GetActiveTrackedQuestID() == nil and reads == 1)
			blocked = false
			for _, value in ipairs({ 0, -1, 1.5, 1000000001, secret, inaccessible }) do
				id = value; assert(addon.API.GetActiveTrackedQuestID() == nil)
			end
			C_SuperTrack.GetSuperTrackedQuestID = function() error("unavailable") end
			assert(addon.API.GetActiveTrackedQuestID() == nil)
			C_SuperTrack.IsSuperTrackingQuest = function() error("unavailable") end
			assert(addon.API.GetActiveTrackedQuestID() == nil)
			for _, value in ipairs({ {}, secret, inaccessible }) do
				C_SuperTrack = value; assert(addon.API.GetActiveTrackedQuestID() == nil)
			end
			C_SuperTrack = nil; assert(addon.API.GetActiveTrackedQuestID() == nil)
			C_SuperTrack, addon.IsRuntimeRestricted, addon.IsMapTooltipSensitiveStateActive = oldTrack, oldBlocked, oldSensitive
			assert(inaccessibleReads == 0)
		end
		do
			local oldMap, oldVector, oldBlocked = C_Map, CreateVector2D, addon.IsRuntimeRestricted
			local blocked, width, height = false, 4000, 2000
			addon.IsRuntimeRestricted = function() return blocked end
			CreateVector2D = function(x, y) return { x = x, y = y } end
			C_Map = {
				GetMapWorldSize = function(id) assert(id == 37); return width, height end,
				GetWorldPosFromMapPos = function(id, pos)
					assert(id == 37)
					return 0, { GetXY = function() return 1000 - pos.y * 2000, 2000 - pos.x * 4000 end }
				end,
			}
			local w, h = addon:GetLocationPinMapWorldSize(37)
			assert(w == 4000 and h == 2000)
			C_Map.GetMapWorldSize = nil -- Classic capability fallback
			w, h = addon:GetLocationPinMapWorldSize(37)
			assert(w == 4000 and h == 2000)
			blocked = true
			assert(addon:GetLocationPinMapWorldSize(37) == nil)
			blocked = false
			for _, value in ipairs({ secret, inaccessible, 0, -1, 1.5 }) do
				assert(addon:GetLocationPinMapWorldSize(value) == nil)
			end
			C_Map.GetWorldPosFromMapPos = function() return secret, inaccessible end
			assert(addon:GetLocationPinMapWorldSize(37) == nil)
			C_Map, CreateVector2D, addon.IsRuntimeRestricted = oldMap, oldVector, oldBlocked
		end

		-- Quest-title lookups never select quests and copy only public strings.
		do
			local oldLog, oldBlocked = C_QuestLog, addon.IsWorkBlocked
			local blocked, calls, loads, title = false, 0, 0, "Localized title"
			addon.IsWorkBlocked = function(_, kind) assert(kind == "quest_snapshot_refresh"); return blocked end
			C_QuestLog = {
				GetTitleForQuestID = function(id) assert(id == 12345); calls = calls + 1; return title end,
				RequestLoadQuestByID = function(id) assert(id == 12345); loads = loads + 1 end,
			}
			assert(addon.API.GetLocalizedQuestTitle(12345) == title and calls == 1)
			assert(addon.API.RequestLocalizedQuestTitle(12345) == true and loads == 1)
			blocked = true
			assert(addon.API.GetLocalizedQuestTitle(12345) == nil and calls == 1)
			assert(addon.API.RequestLocalizedQuestTitle(12345) == false and loads == 1)
			blocked = false
			local before = inaccessibleReads
			for _, value in ipairs({ secret, inaccessible, {}, 123 }) do
				title = value; assert(addon.API.GetLocalizedQuestTitle(12345) == nil)
			end
			for _, value in ipairs({ secret, inaccessible }) do
				C_QuestLog = value
				assert(addon.API.GetLocalizedQuestTitle(12345) == nil)
				assert(addon.API.RequestLocalizedQuestTitle(12345) == false)
			end
			assert(inaccessibleReads == before, "inaccessible title API must not be inspected")
			C_QuestLog = nil
			assert(addon.API.GetLocalizedQuestTitle(12345) == nil)
			assert(addon.API.RequestLocalizedQuestTitle(12345) == false)
			C_QuestLog, addon.IsWorkBlocked = oldLog, oldBlocked
		end
		-- Native party contracts are simulated offline only. Nil InviteUnit return
		-- means invocation, not confirmed delivery; inaccessible data fails closed.
		do
			local oldCategory = LE_PARTY_CATEGORY_INSTANCE
			LE_PARTY_CATEGORY_INSTANCE = 2
			local oldParty, oldFriends = C_PartyInfo, C_FriendList
			local oldGroup, oldRaid, oldCount = IsInGroup, IsInRaid, GetNumGroupMembers
			local oldLeader = UnitIsGroupLeader
			local oldRestricted = addon.IsRuntimeRestricted
			local blocked, grouped, raid, instance, count, permitted = false, true, false, false, 2, true
			local calls, invited, friendInfo, result = 0, nil, nil, nil
			addon.IsRuntimeRestricted = function() return blocked end
			IsInGroup = function(category) if category == LE_PARTY_CATEGORY_INSTANCE then return instance end; return grouped end
			IsInRaid = function() return raid end
			GetNumGroupMembers = function() return count end
			C_PartyInfo = {
				CanInvite = function() return permitted end,
				InviteUnit = function(name) calls, invited = calls + 1, name; return result end,
			}
			C_FriendList = { GetFriendInfo = function() return friendInfo end }
			local g, allowed, _, relay = addon.API.GetPartyJoinInfo()
			assert(g == true and allowed == true and relay == true)
			UnitIsGroupLeader = function(unit) return unit == "player" end
			assert(addon.API.GetPartyVisualLeaderUnit() == "player")
			UnitIsGroupLeader = function(unit) return unit == "party3" end
			assert(addon.API.GetPartyVisualLeaderUnit() == "party3")
			raid = true; UnitIsGroupLeader = function(unit) return unit == "raid40" end
			assert(addon.API.GetPartyVisualLeaderUnit() == "raid40")
			blocked = true; assert(addon.API.GetPartyVisualLeaderUnit() == nil); blocked = false
			for _, value in ipairs({ secret, inaccessible }) do
				UnitIsGroupLeader = value; assert(addon.API.GetPartyVisualLeaderUnit() == nil)
				UnitIsGroupLeader = function() return value end; assert(addon.API.GetPartyVisualLeaderUnit() == nil)
				IsInRaid = function() return value end; assert(addon.API.GetPartyVisualLeaderUnit() == nil)
			end
			IsInRaid = function() return raid end
			UnitIsGroupLeader = function() error("unavailable") end; assert(addon.API.GetPartyVisualLeaderUnit() == nil)
			raid = false
			local leaderCalls = 0
			UnitIsGroupLeader = function(unit) leaderCalls = leaderCalls + 1; return unit == "party2" end
			assert(addon.API.GetPartyJoinLeaderUnit() == "party2" and leaderCalls == 2)
			blocked = true; assert(addon.API.GetPartyJoinLeaderUnit() == nil and leaderCalls == 2); blocked = false
			for _, value in ipairs({ secret, inaccessible }) do
				UnitIsGroupLeader = value; assert(addon.API.GetPartyJoinLeaderUnit() == nil)
				UnitIsGroupLeader = function() return value end; assert(addon.API.GetPartyJoinLeaderUnit() == nil)
			end
			UnitIsGroupLeader = function() error("unavailable") end; assert(addon.API.GetPartyJoinLeaderUnit() == nil)
			UnitIsGroupLeader = function() return false end; assert(addon.API.GetPartyJoinLeaderUnit() == nil)
			for _, case in ipairs({ "full", "raid", "instance", "solo" }) do
				count = case == "full" and 5 or 2
				raid, instance, grouped = case == "raid", case == "instance", case ~= "solo"
				local _, _, _, mayRelay = addon.API.GetPartyJoinInfo(); assert(mayRelay == false)
			end
			count, raid, instance, grouped = 2, false, false, true
			count = 5; g, allowed = addon.API.GetPartyJoinInfo(); assert(allowed == false)
			count, raid = 2, true; g, allowed = addon.API.GetPartyJoinInfo(); assert(allowed == false)
			raid, instance = false, true; g, allowed = addon.API.GetPartyJoinInfo(); assert(allowed == false)
			instance, permitted = false, secret; g, allowed = addon.API.GetPartyJoinInfo(); assert(allowed == false)
			count = secret; assert(addon.API.GetPartyJoinInfo() == nil)
			assert(addon.API.InviteUnit("Friend-Realm") == true and calls == 1 and invited == "Friend-Realm")
			blocked = true; assert(addon.API.InviteUnit("Friend-Realm") == false and calls == 1); blocked = false
			for _, value in ipairs({ false, secret, inaccessible }) do result = value; assert(addon.API.InviteUnit("Friend-Realm") == false) end
			friendInfo = { name = "Friend-Realm" }; assert(addon.API.IsPartyJoinFriend("Friend-Realm") == true)
			friendInfo = { name = "Friend-OtherRealm" }; assert(addon.API.IsPartyJoinFriend("Friend-Realm") == false)
			local before = inaccessibleReads
			for _, value in ipairs({ secret, inaccessible }) do
				friendInfo = value; assert(addon.API.IsPartyJoinFriend("Friend-Realm") == false)
				friendInfo = { name = value }; assert(addon.API.IsPartyJoinFriend("Friend-Realm") == false)
				C_PartyInfo, C_FriendList = value, value
				assert(addon.API.InviteUnit("Friend-Realm") == false and addon.API.IsPartyJoinFriend("Friend-Realm") == false)
			end
			assert(inaccessibleReads == before)
			C_PartyInfo, C_FriendList = oldParty, oldFriends
			IsInGroup, IsInRaid, GetNumGroupMembers = oldGroup, oldRaid, oldCount
			UnitIsGroupLeader = oldLeader
			addon.IsRuntimeRestricted = oldRestricted
			LE_PARTY_CATEGORY_INSTANCE = oldCategory
		end
		local originalChat, originalLegacyChat = C_ChatInfo, SendChatMessage
		local calls = {}
		local function send(text, channel) calls[#calls + 1] = {text, channel} end
		C_ChatInfo = { SendChatMessage = send }
		SendChatMessage = function() error("modern API should win") end
		assert(addon.API.SendPartyChatMessage("hello", "PARTY"))
		assert(calls[1][1] == "hello" and calls[1][2] == "PARTY")
		assert(not addon.API.SendPartyChatMessage("hello", "RAID") and #calls == 1)
		C_ChatInfo, SendChatMessage = {}, send
		assert(addon.API.SendPartyChatMessage("hello", "INSTANCE_CHAT"))
		assert(calls[2][2] == "INSTANCE_CHAT")
		SendChatMessage = function() error("blocked") end
		assert(not addon.API.SendPartyChatMessage("hello", "PARTY"))
		SendChatMessage = nil
		assert(not addon.API.SendPartyChatMessage("hello", "PARTY"))
		C_ChatInfo, SendChatMessage = originalChat, originalLegacyChat
		-- Native contracts stay offline; the live suite uses private adapters.
		do
			local oldChat, oldSend, oldList = C_ChatInfo, SendChatMessage, GetChannelList
			local channelCalls = {}
			local function sendChannel(text, route, language, target)
				channelCalls[#channelCalls + 1] = { text, route, language, target }
			end
			C_ChatInfo = { SendChatMessage = sendChannel, SwapChatChannelsByChannelIndex = function(a, b)
				assert(a == 2 and b == 4)
			end }
			assert(addon.API.SendChannelChatMessage("hello", 7))
			assert(channelCalls[1][2] == "CHANNEL" and channelCalls[1][3] == nil and channelCalls[1][4] == 7)
			assert(addon.API.SwapChatChannelIndices(2, 4))
			GetChannelList = function() return 1, "General", false, 2, "QuestTogether", false end
			local channels = addon.API.GetChatChannelList()
			assert(#channels == 6 and channels[2] == "General" and channels[5] == "QuestTogether")
			C_ChatInfo, SendChatMessage = {}, sendChannel
			assert(addon.API.SendChannelChatMessage("legacy", 9))
			assert(channelCalls[2][4] == 9)
			assert(not addon.API.SwapChatChannelIndices(2, 4))
			SendChatMessage = function() error("blocked") end
			assert(not addon.API.SendChannelChatMessage("blocked", 9))
			SendChatMessage, GetChannelList = nil, nil
			assert(not addon.API.SendChannelChatMessage("missing", 9))
			assert(addon.API.GetChatChannelList() == nil)
			C_ChatInfo, SendChatMessage, GetChannelList = oldChat, oldSend, oldList
		end

		-- Shared Mainline exports do not imply that Forever has War Mode.
		-- Keep native API probes in this offline process, not the live test suite.
		do
			local originalPvP, originalRegional = C_PvP, RegionalUniqueNamesEnabled
			local active, enabled, capabilityCalls, desiredCalls = false, not classic, 0, 0
			RegionalUniqueNamesEnabled = function() return client == "forever" end
			C_PvP = {
				IsWarModeFeatureEnabled = function() capabilityCalls = capabilityCalls + 1
return enabled end,
				IsWarModeActive = function() return active end,
				IsWarModeDesired = function() desiredCalls = desiredCalls + 1
return not active end,
			}
			assert(addon:SupportsWarMode() == (client == "retail"))
			assert(capabilityCalls == (client == "forever" and 0 or 1))
			for _, value in ipairs({ true, false, secret, inaccessible, "true", 1 }) do
				active, enabled = value, value
				local expected
				if type(value) == "boolean" then expected = value end
				assert(addon.API.IsWarModeFeatureEnabled() == expected)
				assert(addon.API.IsWarModeActive() == expected)
			end
			active, enabled = nil, nil
			assert(addon.API.IsWarModeFeatureEnabled() == nil)
			assert(addon.API.IsWarModeActive() == nil)
			C_PvP.IsWarModeActive = nil
			assert(addon.API.IsWarModeActive() == nil)
			assert(desiredCalls == 0, "actual mode must not be replaced with the desired preference")
			C_PvP.IsWarModeActive = function() error("unavailable active mode") end
			C_PvP.IsWarModeFeatureEnabled = function() error("unavailable feature") end
			assert(addon.API.IsWarModeActive() == nil)
			assert(addon.API.IsWarModeFeatureEnabled() == nil)
			local before = inaccessibleReads
			for _, unavailable in ipairs({ secret, inaccessible }) do
				C_PvP = unavailable
				assert(addon.API.IsWarModeActive() == nil)
				assert(addon.API.IsWarModeFeatureEnabled() == nil)
			end
			assert(inaccessibleReads == before, "inaccessible C_PvP tables must not be indexed")
			C_PvP = nil
			assert(addon.API.IsWarModeActive() == nil)
			assert(addon.API.IsWarModeFeatureEnabled() == nil)
			C_PvP, RegionalUniqueNamesEnabled = originalPvP, originalRegional
		end
		-- A successful missing modern CVar permits the legacy alias; an unreadable
		-- native boundary must fail closed instead of enabling friendly overlays.
		do
			local originalCVar = C_CVar
			local modern, legacy = "nameplateShowFriendlyPlayers", "nameplateShowFriends"
			local values, calls, failure = {}, {}, nil
			C_CVar = {
				GetCVar = function(key)
					calls[#calls + 1] = key
					if key == failure then
						error("CVar unavailable")
					end
					return values[key]
				end,
			}
			local value, readable = addon.API.GetCVar(modern)
			assert(value == nil and readable == true, "an absent CVar is a successful read")
			for _, case in ipairs({
				{ modern = "1", legacy = "0", expected = true, reads = 1 },
				{ modern = "0", legacy = "1", expected = false, reads = 1 },
				{ legacy = "1", expected = true, reads = 2 },
				{ legacy = "0", expected = false, reads = 2 },
				{ reads = 2 },
			}) do
				values, calls = { [modern] = case.modern, [legacy] = case.legacy }, {}
				assert(addon:GetFriendlyPlayerNameplateVisibility() == case.expected)
				assert(#calls == case.reads and calls[1] == modern)
				if case.reads == 2 then
					assert(calls[2] == legacy)
				end
			end
			for _, unavailable in ipairs({ secret, inaccessible, "", "invalid", 1, true }) do
				values, calls = { [modern] = unavailable, [legacy] = "1" }, {}
				assert(addon:GetFriendlyPlayerNameplateVisibility() == nil)
				assert(#calls == 1, "invalid modern data must not enable legacy fallback")
				if unavailable == secret or unavailable == inaccessible then
					value, readable = addon.API.GetCVar(modern)
					assert(value == nil and readable == false)
				end
			end
			for _, key in ipairs({ modern, legacy }) do
				values, calls, failure = { [legacy] = "1" }, {}, key
				assert(addon:GetFriendlyPlayerNameplateVisibility() == nil)
				assert(#calls == (key == modern and 1 or 2))
				value, readable = addon.API.GetCVar(key)
				assert(value == nil and readable == false)
			end
			failure = nil
			local before = inaccessibleReads
			for _, unavailable in ipairs({ secret, inaccessible, false }) do
				C_CVar = unavailable
				value, readable = addon.API.GetCVar(modern)
				assert(value == nil and readable == false)
				assert(addon:GetFriendlyPlayerNameplateVisibility() == nil)
				C_CVar = { GetCVar = unavailable }
				value, readable = addon.API.GetCVar(modern)
				assert(value == nil and readable == false)
			end
			C_CVar = nil
			value, readable = addon.API.GetCVar(modern)
			assert(value == nil and readable == false)
			C_CVar = {}
			value, readable = addon.API.GetCVar(modern)
			assert(value == nil and readable == false)
			assert(inaccessibleReads == before, "inaccessible CVar namespace must not be read")
			C_CVar = originalCVar
		end
		-- Foreign native map returns are checked before any field access. This
		-- standalone fixture never replaces C_Map inside a live client.
		do
			local originalMap = C_Map
			local result
			C_Map = { GetMapInfo = function() return result end, GetPlayerMapPosition = function() return result end }
			local before = inaccessibleReads
			for _, unavailable in ipairs({ secret, inaccessible, false, "bad return", 42 }) do
				result = unavailable
				assert(addon.API.GetMapInfo(84) == nil)
				assert(addon.API.GetPlayerMapPosition(84, "player") == nil)
			end
			assert(inaccessibleReads == before, "pcall must not hide inaccessible native map reads")
			result = { mapID = 84, name = "Stormwind", mapType = 3, parentMapID = 13 }
			local info = addon.API.GetMapInfo(84)
			assert(info ~= result and info.mapID == 84 and info.name == "Stormwind" and info.mapType == 3 and info.parentMapID == 13)
			result = { mapID = secret, name = inaccessible, mapType = secret, parentMapID = inaccessible }
			info = addon.API.GetMapInfo(84)
			assert(info.mapID == 84 and info.name == nil and info.mapType == nil and info.parentMapID == nil)
			for _, position in ipairs({ { x = 0, y = 1 }, { GetXY = function() return 0, 1 end } }) do
				result = position
				local copy = addon.API.GetPlayerMapPosition(84, "player")
				assert(copy ~= position and copy.x == 0 and copy.y == 1)
			end
			for _, position in ipairs({ { x = secret, y = 0 }, { x = 0, y = inaccessible },
				{ GetXY = secret }, { GetXY = function() return inaccessible, 0 end } }) do
				result = position
				assert(addon.API.GetPlayerMapPosition(84, "player") == nil)
			end
			assert(inaccessibleReads == before)
			C_Map = originalMap
		end
		-- Native chat-frame contracts remain offline. Retail/Forever's IM-mode
		-- ChooseBoxForSend uses a visible preferred frame's editBox directly.
		do
			local originalUtil, originalLegacy = ChatFrameUtil, ChatFrame_SendTell
			local style, parsed, calls, lastPreferred = "im", 0, 0, nil
			local editBox = { ParseText = function() parsed = parsed + 1 end }
			local chat = { editBox = editBox, IsShown = function() return true end }
			local pin = { IsShown = function() return true end }
			local function SendTell(name, preferred)
				calls, lastPreferred = calls + 1, preferred
				assert(name == "Friend-Realm")
				local box
				if style == "classic" then box = editBox
				elseif preferred and preferred:IsShown() then box = preferred.editBox
				else box = editBox end
				box:ParseText(0)
			end
			local forbiddenReads = 0
			local forbidden = setmetatable({ IsForbidden = function() return true end }, {
				__index = function()
					forbiddenReads = forbiddenReads + 1
					error("forbidden chat owner read")
				end,
			})
			for _, legacy in ipairs({ false, true }) do
				ChatFrameUtil = not legacy and { SendTell = SendTell } or nil
				ChatFrame_SendTell = legacy and SendTell or nil
				for _, chatStyle in ipairs({ "im", "classic" }) do
					style = chatStyle
					assert(addon.API.SendTell("Friend-Realm", chat) == true)
					assert(lastPreferred == chat, "a real chat owner should retain its destination")
					for _, owner in ipairs({ pin, forbidden, { editBox = forbidden }, secret, inaccessible }) do
						local before = parsed
						assert(addon.API.SendTell("Friend-Realm", owner) == true)
						assert(lastPreferred == nil and parsed == before + 1)
					end
					local callback
					addon:PopulateChatLogSpeakerMenu({
						CreateTitle = function() end,
						CreateButton = function(_, title, run) if title == "Whisper" then callback = run end end,
					}, pin, "Friend-Realm")
					local before = parsed
					assert(callback)
					callback()
					assert(lastPreferred == nil and parsed == before + 1, "dot menu must open a whisper")
				end
			end
			assert(forbiddenReads == 0, "pcall must not hide forbidden owner reads")
			assert(parsed == calls)
			for _, legacy in ipairs({ false, true }) do
				local function Failure() error("native whisper failed") end
				ChatFrameUtil = not legacy and { SendTell = Failure } or nil
				ChatFrame_SendTell = legacy and Failure or nil
				assert(addon:WhisperChatLogSpeaker("Friend-Realm", pin) == false)
				for _, result in ipairs({ false, secret, inaccessible }) do
					local function Unavailable() return result end
					ChatFrameUtil = not legacy and { SendTell = Unavailable } or nil
					ChatFrame_SendTell = legacy and Unavailable or nil
					assert(addon:WhisperChatLogSpeaker("Friend-Realm", pin) == false)
				end
			end
			ChatFrameUtil, ChatFrame_SendTell = nil, nil
			assert(addon:WhisperChatLogSpeaker("Friend-Realm", pin) == false)
			ChatFrameUtil, ChatFrame_SendTell = originalUtil, originalLegacy
		end
		-- Identity flags must be readable booleans before plate code branches.
		do
			local oldExists, oldPlayer, oldFriend = UnitExists, UnitIsPlayer, UnitIsFriend
			for _, value in ipairs({ true, false, secret, inaccessible, "true", 1 }) do
				UnitExists = function() return value end
				UnitIsPlayer = function() return value end
				UnitIsFriend = function() return value end
				assert(addon.API.UnitExists("nameplate1") == (value == true))
				assert(addon.API.UnitIsPlayer("nameplate1") == (value == true))
				local result = addon.API.UnitIsFriend("player", "nameplate1")
				if type(value) == "boolean" then assert(result == value)
				else assert(result == nil) end
			end
			UnitIsFriend = function() error("unavailable unit") end
			assert(addon.API.UnitIsFriend("player", "nameplate1") == nil)
			UnitIsFriend = nil
			assert(addon.API.UnitIsFriend("player", "nameplate1") == nil)
			UnitExists, UnitIsPlayer, UnitIsFriend = oldExists, oldPlayer, oldFriend
		end
		-- Native sharing/menu contracts stay offline: these are fake globals in
		-- this process, never monkeypatches in /qt test.
		do
			local rawIndex, rawRow = 7, { questID = 12345, isHeader = false }
			local sends, throws = {}, false
			QuestLogPushQuest = function(...)
				assert(select("#", ...) == 1 and (...) == rawIndex, "share must pass an explicit live index")
				if throws then error("native sharing unavailable") end
				sends[#sends + 1] = (...)
				-- The native API has no acknowledgement return value.
			end
			assert(addon.API.CanShareQuests() == not classic)
			local originalIndex, originalInfo = C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetInfo
			if classic then
				assert(addon.API.GetQuestLogIndexForSharing(12345) == nil)
				assert(addon.API.PushQuestToParty(7) == false, "legacy sharing must not change selection")
			else
				C_QuestLog.GetLogIndexForQuestID = function(id) assert(id == 12345)
return rawIndex end
				C_QuestLog.GetInfo = function(index) assert(index == rawIndex)
return rawRow end
				assert(addon.API.GetQuestLogIndexForSharing("12345") == 7)
				assert(addon.API.PushQuestToParty(7) == true, "no native return still means the call was attempted")
				rawIndex = 9
				assert(addon.API.GetQuestLogIndexForSharing(12345) == 9, "must resolve the current index")
				for _, invalid in ipairs({ 0, -1, 0.5, math.huge, secret, inaccessible }) do
					rawIndex = invalid
					assert(addon.API.GetQuestLogIndexForSharing(12345) == nil)
					assert(addon.API.PushQuestToParty(invalid) == false)
				end
				rawIndex = nil
				assert(addon.API.GetQuestLogIndexForSharing(12345) == nil)
				assert(addon.API.PushQuestToParty(nil) == false, "nil must not share the selected quest")
				rawIndex = 7
				for _, row in ipairs({ secret, inaccessible, {}, { questID = 54321 },
					{ questID = 12345, isHeader = true }, { questID = 12345, isHeader = secret }, { questID = secret } }) do
					rawRow = row
					assert(addon.API.GetQuestLogIndexForSharing(12345) == nil)
				end
				for _, invalid in ipairs({ 0, -1, 12345.5, math.huge, secret, inaccessible }) do
					assert(addon.API.GetQuestLogIndexForSharing(invalid) == nil)
				end
				C_QuestLog.GetInfo = function() error("native row unavailable") end
				assert(addon.API.GetQuestLogIndexForSharing(12345) == nil)
				C_QuestLog.GetLogIndexForQuestID = function() error("native index unavailable") end
				assert(addon.API.GetQuestLogIndexForSharing(12345) == nil)
				throws = true
				assert(addon.API.PushQuestToParty(7) == false)
				assert(#sends == 1)
			end
			C_QuestLog.GetLogIndexForQuestID, C_QuestLog.GetInfo = originalIndex, originalInfo
			QuestLogPushQuest = nil
			assert(addon.API.CanShareQuests() == false)
			local grouped
			IsInGroup = function() return grouped end
			for _, value in ipairs({ false, secret, inaccessible, "true", 1 }) do
				grouped = value
				assert(addon.API.IsInGroup() == false)
			end
			grouped = true
			assert(addon.API.IsInGroup() == true)
			IsInGroup = nil
			assert(addon.API.IsInGroup() == false)
			local opens = 0
			MenuUtil = { CreateContextMenu = function(owner, generator)
				opens = opens + 1
				generator(owner, {})
				return {}
			end }
			local owner = {}
			assert(addon.API.CreateContextMenu(owner, function(actual) assert(actual == owner) end))
			local forbidden = setmetatable({ IsForbidden = function() return true end }, {
				__index = function() error("forbidden owner must not be inspected further") end,
			})
			assert(addon.API.CreateContextMenu(forbidden, function() error("must not open") end) == false)
			assert(addon.API.CreateContextMenu(inaccessible, function() error("must not open") end) == false)
			assert(opens == 1)
			MenuUtil = nil
			assert(addon.API.CreateContextMenu(owner, function() end) == false)
		end
		-- Journal navigation uses Blizzard's quest-ID entry point and verifies
		-- visible details. All native frames/functions here exist only offline.
		do
			assert(addon.API.CanOpenQuestJournal() == false)
			if not classic then
				local shown, selectedID, opens, restricted, throws, wrongQuest, keepHidden = false, nil, 0, false, false, false, false
				local originalRestricted = addon.IsRuntimeRestricted
				addon.IsRuntimeRestricted = function() return restricted end
				local details = {}
				local map = { IsShown = function() return shown end }
				QuestMapFrame = { DetailsFrame = details, IsShown = function() return shown end }
				QuestMapFrame_GetDetailQuestID = function() return selectedID end
				QuestMapFrame_OpenToQuestDetails = function(id)
					assert(id == 12345, "journal requires quest ID, not log index")
					opens = opens + 1
					if throws then error("journal unavailable") end
					WorldMapFrame = map -- The native entry point may load the map lazily.
					shown, selectedID = not keepHidden, wrongQuest and 54321 or id
				end
				assert(addon.API.CanOpenQuestJournal() == true)
				assert(addon.API.OpenQuestJournal("12345") == true)
				assert(opens == 1)
				for _, id in ipairs({ 0, -1, 12345.5, math.huge, secret, inaccessible }) do
					assert(addon.API.OpenQuestJournal(id) == false)
				end
				assert(addon.API.OpenQuestJournal(nil) == false)
				restricted = true
				assert(addon.API.OpenQuestJournal(12345) == false)
				restricted = false
				local forbidden = setmetatable({ IsForbidden = function() return true end }, {
					__index = function() error("forbidden journal must not be inspected") end,
				})
				local questMap = QuestMapFrame
				for _, frame in ipairs({ forbidden, inaccessible }) do
					QuestMapFrame = frame
					assert(addon.API.OpenQuestJournal(12345) == false)
					QuestMapFrame = questMap
					QuestMapFrame.DetailsFrame = frame
					assert(addon.API.OpenQuestJournal(12345) == false)
					QuestMapFrame.DetailsFrame = details
					WorldMapFrame = frame
					assert(addon.API.OpenQuestJournal(12345) == false)
					WorldMapFrame = map
				end
				assert(opens == 1, "invalid or restricted opens must stop before the native call")
				wrongQuest = true
				assert(addon.API.OpenQuestJournal(12345) == false)
				wrongQuest, keepHidden = false, true
				assert(addon.API.OpenQuestJournal(12345) == false)
				keepHidden, throws = false, true
				assert(addon.API.OpenQuestJournal(12345) == false)
				addon.IsRuntimeRestricted = originalRestricted
			end
			QuestMapFrame, WorldMapFrame = nil, nil
			QuestMapFrame_OpenToQuestDetails, QuestMapFrame_GetDetailQuestID = nil, nil
			assert(addon.API.CanOpenQuestJournal() == false)
		end
		-- Generic journal navigation uses the public opener, which returns no
		-- acknowledgement and never toggles an already-open journal closed.
		-- Only Retail/Forever exports are sourced; other profiles stay unavailable.
		do
			assert(addon.API.CanOpenQuestJournalWindow() == false)
			assert(addon.API.OpenQuestJournalWindow() == false)
			if not classic then
				local originalRestricted = addon.IsRuntimeRestricted
				local restricted, throws, disabled, calls = false, false, false, 0
				local mapShown, journalShown, mapResult, journalResult = false, false, true, true
				addon.IsRuntimeRestricted = function() return restricted end
				local readOnly = {
					__index = function(_, key) error("generic journal must not inspect " .. key) end,
					__newindex = function() error("addon must not store state on journal frames") end,
				}
				local map = setmetatable({
					IsForbidden = function() return false end,
					IsShown = function() return mapShown end,
				}, readOnly)
				local journal = setmetatable({
					IsForbidden = function() return false end,
					IsShown = function() return journalShown end,
				}, readOnly)
				WorldMapFrame, QuestMapFrame = map, journal
				local function OpenNativeJournal(...)
					assert(select("#", ...) == 0, "generic opener must not select a quest or map")
					calls = calls + 1
					if throws then error("native journal unavailable") end
					if disabled then return end -- Native WorldMapDisabled guard.
					mapShown, journalShown = mapResult, journalResult
					-- Native OpenQuestLog returns nil even after opening successfully.
				end
				OpenQuestLog = OpenNativeJournal
				assert(addon.API.CanOpenQuestJournalWindow() == true, "generic journal needs no DetailsFrame")
				assert(addon.API.OpenQuestJournalWindow() == true)
				assert(addon.API.OpenQuestJournalWindow() == true, "reopening must not toggle the journal closed")
				assert(calls == 2 and selected == 7, "opening must preserve quest selection")
				restricted = true
				assert(addon.API.OpenQuestJournalWindow() == false)
				restricted = false
				local forbidden = setmetatable({ IsForbidden = function() return true end }, readOnly)
				for _, frame in ipairs({ forbidden, inaccessible, secret }) do
					WorldMapFrame = frame
					assert(addon.API.CanOpenQuestJournalWindow() == false)
					assert(addon.API.OpenQuestJournalWindow() == false)
					WorldMapFrame, QuestMapFrame = map, frame
					assert(addon.API.CanOpenQuestJournalWindow() == false)
					assert(addon.API.OpenQuestJournalWindow() == false)
					QuestMapFrame = journal
				end
				WorldMapFrame = nil
				assert(addon.API.OpenQuestJournalWindow() == false)
				WorldMapFrame, QuestMapFrame = map, nil
				assert(addon.API.OpenQuestJournalWindow() == false)
				QuestMapFrame, OpenQuestLog = journal, nil
				assert(addon.API.CanOpenQuestJournalWindow() == false)
				assert(addon.API.OpenQuestJournalWindow() == false)
				assert(calls == 2, "restricted/unavailable frames must stop before the native call")
				OpenQuestLog, throws = OpenNativeJournal, true
				assert(addon.API.OpenQuestJournalWindow() == false)
				throws, disabled, mapShown, journalShown = false, true, false, false
				assert(addon.API.OpenQuestJournalWindow() == false, "a silent native decline is not an opened journal")
				disabled = false
				for _, visibility in ipairs({ false, secret, inaccessible }) do
					mapResult, journalResult = visibility, true
					assert(addon.API.OpenQuestJournalWindow() == false)
					mapResult, journalResult = true, visibility
					assert(addon.API.OpenQuestJournalWindow() == false)
				end
				mapResult, journalResult = nil, true
				assert(addon.API.OpenQuestJournalWindow() == false)
				mapResult, journalResult = true, nil
				assert(addon.API.OpenQuestJournalWindow() == false)
				mapResult, journalResult = true, true
				OpenQuestLog = function()
					OpenNativeJournal()
					QuestMapFrame = forbidden
				end
				assert(addon.API.OpenQuestJournalWindow() == false, "post-open frame access must also be guarded")
				QuestMapFrame, OpenQuestLog = journal, OpenNativeJournal
				assert(addon.API.OpenQuestJournalWindow() == true, "a later safe click can recover")
				addon.IsRuntimeRestricted = originalRestricted
			end
			WorldMapFrame, QuestMapFrame, OpenQuestLog = nil, nil, nil
			assert(addon.API.CanOpenQuestJournalWindow() == false)
			assert(addon.API.OpenQuestJournalWindow() == false)
		end
		-- Standalone Lua can construct NaN; Forever's arithmetic raises instead.
		-- Keep this boundary check offline so /qt test never attempts 0 / 0.
		local notANumber = 0 / 0
		assert(addon:SafeToNumber(notANumber) == nil, "NaN must not pass number sanitization")
		local levelFixture = setmetatable({ isEnabled = true }, { __index = addon })
		function levelFixture:PublishAnnouncementEvent() error("invalid level must not publish") end
		function levelFixture:PlayLocalCelebrationEmote() error("invalid level must not celebrate") end
		assert(levelFixture:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", notANumber) == false)
		assert(addon.API.GetQuestLogInfo(7).questID == 12345)
		assert(addon.API.GetQuestLogInfo(7).isComplete == false)
		assert(addon.API.GetQuestLogIndexForQuestID(12345) == 7)
		local originalTitleGetter, originalInfoGetter = GetQuestLogTitle, C_QuestLog.GetInfo
		local completion
		GetQuestLogTitle = function(index)
			assert(index == 7)
			return "Legacy Wolf Hunt", 20, nil, false, false, completion, nil, 12345, nil, nil, true, true, true
		end
		C_QuestLog.GetInfo = nil
		for _, case in ipairs({ { expected = false }, { value = 1, expected = true }, { value = -1, expected = false } }) do
			completion = case.value
			assert(addon.API.GetQuestLogInfo(7).isComplete == case.expected,
				"legacy completion must distinguish incomplete, completed and failed quests")
		end
		local modernInfo = { title = "Modern Wolf Hunt", questID = 12345, isComplete = false }
		C_QuestLog.GetInfo = function() return modernInfo end
		for _, legacyCompletion in ipairs({ -1, 1 }) do
			completion = legacyCompletion
			local merged = addon.API.GetQuestLogInfo(7)
			assert(merged.isComplete == false, "explicit modern false must remain authoritative")
			assert(merged.title == modernInfo.title and merged.questID == modernInfo.questID)
			assert(merged.isTask == true and merged.isOnMap == true and merged.hasLocalPOI == true,
				"optional legacy quest metadata must remain available")
		end
		modernInfo.isComplete, completion = nil, 1
		assert(addon.API.GetQuestLogInfo(7).isComplete == true, "missing modern completion must allow legacy completion")
		modernInfo.isComplete, completion = true, -1
		assert(addon.API.GetQuestLogInfo(7).isComplete == true, "explicit modern completion must remain authoritative")
		-- Location flags are tri-state, including after modern/legacy merging.
		-- These native tables exist only in this offline process, never /qt test.
		modernInfo.isOnMap, modernInfo.hasLocalPOI = false, false
		local location = addon.API.GetQuestLogInfo(7)
		assert(location.isOnMap == false and location.hasLocalPOI == false,
			"explicit modern location false must override legacy true")
		GetQuestLogTitle = nil
		for _, field in ipairs({ "isOnMap", "hasLocalPOI" }) do
			for _, shape in ipairs({ "missing", "secret", "inaccessible", "invalid", "false", "true" }) do
				local value
				if shape == "secret" then value = secret
				elseif shape == "inaccessible" then value = inaccessible
				elseif shape == "invalid" then value = "unavailable"
				elseif shape == "false" then value = false
				elseif shape == "true" then value = true end
				modernInfo[field] = value
				local row = addon.API.GetQuestLogInfo(7)
				assert(row.questID == 12345 and row.title == "Modern Wolf Hunt")
				local expected
				if shape == "false" then expected = false elseif shape == "true" then expected = true end
				assert(row[field] == expected, "modern location availability: " .. field .. "/" .. shape)
			end
		end
		C_QuestLog.GetInfo = nil
		local legacyOnMap, legacyPOI
		GetQuestLogTitle = function()
			return "Legacy Wolf Hunt", 20, nil, false, false, nil, nil, 12345, nil, nil, legacyOnMap, legacyPOI, true
		end
		for _, shape in ipairs({ "missing", "secret", "inaccessible", "false", "true" }) do
			if shape == "missing" then legacyOnMap = nil
			elseif shape == "secret" then legacyOnMap = secret
			elseif shape == "inaccessible" then legacyOnMap = inaccessible
			else legacyOnMap = shape == "true" end
			legacyPOI = legacyOnMap
			location = addon.API.GetQuestLogInfo(7)
			local expected
			if shape == "false" then expected = false elseif shape == "true" then expected = true end
			assert(location.isOnMap == expected and location.hasLocalPOI == expected,
				"legacy location availability: " .. shape)
		end
		GetQuestLogTitle, C_QuestLog.GetInfo = originalTitleGetter, originalInfoGetter
		local text, kind, done, count, required = addon.API.GetQuestObjectiveInfo(12345, 1, false)
		assert(text == "Wolves slain: 2/5" and kind == "monster" and done == false and count == 2 and required == 5)
		objective.numRequired = secret
		local _, _, _, _, hiddenRequired = addon.API.GetQuestObjectiveInfo(12345, 1, false)
		assert(hiddenRequired == nil, "secret required count must be dropped")
		objective.numRequired = 5
		if not classic then
			local originalObjectives = C_QuestLog.GetQuestObjectives
			C_QuestLog.GetQuestObjectives = function() return {{ text = "Another stage: 2/8", type = "monster", numFulfilled = 2, numRequired = 8 }} end
			local _, _, _, ownCount, wrongRequired = addon.API.GetQuestObjectiveInfo(12345, 1, false)
			assert(ownCount == 2 and wrongRequired == nil, "mismatched rows cannot supplement counters")
			C_QuestLog.GetQuestObjectives = originalObjectives
		end
		assert(addon.API.IsPushableQuest(12345) == true)
		pushable = false
		assert(addon.API.IsPushableQuest(12345) == false)
		pushable = secret
		assert(addon.API.IsPushableQuest(12345) == nil)
		selected, pushable = 1, true
		if classic then assert(addon.API.IsPushableQuest(12345) == nil) end
		objective.numFulfilled = secret
		local _, _, _, hidden = addon.API.GetQuestObjectiveInfo(12345, 1, false)
		assert(hidden == nil, "secret objective count must be dropped")
		local pending = setmetatable({ pendingQuestRemovals = {}, questsCompleted = {}, pendingQuestAcceptances = {}, QueueQuestLogTask = function() end, Debugf = function() end }, { __index = addon })
		if classic then pending:QUEST_ACCEPTED("QUEST_ACCEPTED", 7, 12345) else pending:QUEST_ACCEPTED("QUEST_ACCEPTED", 12345) end
		assert(pending.pendingQuestAcceptances[12345] and not pending.pendingQuestAcceptances[7])

		-- Exercise the real adapters, not injected addon.API replacements. These
		-- globals exist only in this standalone Lua process, never in live tests.
		local taskCalls = 0
		local taskRows = { { questID = 12345 }, { questID = secret }, { questID = -1 }, {} }
		C_TaskQuest = {
			GetQuestsOnMap = function(mapID)
				assert(mapID == 84)
				taskCalls = taskCalls + 1
				return taskRows
			end,
			GetQuestsForPlayerByMapID = function()
				error("modern task API must take precedence")
			end,
		}
		local ids = addon.API.GetTaskQuestsOnMap(84)
		assert(#ids == 1 and ids[1] == 12345, "modern questID rows must survive")
		assert(addon.API.GetTaskQuestsOnMap(secret) == nil)
		assert(addon.API.GetTaskQuestsOnMap(-1) == nil and taskCalls == 1)
		taskRows = secret
		assert(addon.API.GetTaskQuestsOnMap(84) == nil, "secret task table must be rejected")
		taskRows = { secret, { questID = 54321 } }
		ids = addon.API.GetTaskQuestsOnMap(84)
		assert(#ids == 1 and ids[1] == 54321, "secret rows must be skipped")
		C_TaskQuest.GetQuestsOnMap = function() error("task API unavailable") end
		assert(addon.API.GetTaskQuestsOnMap(84) == nil)
		C_TaskQuest = {
			GetQuestsForPlayerByMapID = function(mapID)
				assert(mapID == 84)
				return { { questId = 12345 }, { questId = secret }, { questId = 0 } }
			end,
		}
		ids = addon.API.GetTaskQuestsOnMap(84)
		assert(#ids == 1 and ids[1] == 12345, "legacy questId rows must still work")
		C_TaskQuest = {}
		assert(addon.API.GetTaskQuestsOnMap(84) == nil)
		C_TaskQuest = nil
		assert(addon.API.GetTaskQuestsOnMap(84) == nil)

		local modernEmotes, legacyEmotes = 0, 0
		C_ChatInfo = { PerformEmote = function(token, target)
			assert(token == "CHEER" and target == "MyPlayer")
			modernEmotes = modernEmotes + 1
		end }
		DoEmote = nil -- Current clients can disable deprecated compatibility globals.
		assert(addon.API.DoEmote("CHEER", "MyPlayer") == true and modernEmotes == 1)
		DoEmote = function(token, target)
			assert(token == "CHEER" and target == "MyPlayer")
			legacyEmotes = legacyEmotes + 1
		end
		assert(addon.API.DoEmote("CHEER", "MyPlayer") == true)
		assert(modernEmotes == 2 and legacyEmotes == 0, "prefer modern emotes")
		C_ChatInfo.PerformEmote = function() error("emote unavailable") end
		assert(addon.API.DoEmote("CHEER", "MyPlayer") == false and legacyEmotes == 0)
		C_ChatInfo = nil
		assert(addon.API.DoEmote("CHEER", "MyPlayer") == true and legacyEmotes == 1)
		DoEmote = nil
		assert(addon.API.DoEmote("CHEER", "MyPlayer") == false)

		do
			local oldRace, oldInfo, oldClasses = UnitRace, C_CreatureInfo, LOCALIZED_CLASS_NAMES_MALE
			UnitRace = function() return "Zwerg", "Dwarf", 3 end
			assert(addon.API.GetPlayerRaceID() == 3)
			C_CreatureInfo = { GetRaceInfo = function(id) assert(id == 3) return { raceName = "Dwarf" } end }
			LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage" }
			assert(addon.API.GetLocalizedRaceName(3) == "Dwarf")
			assert(addon.API.GetLocalizedClassName("MAGE") == "Mage")
			for _, value in ipairs({ secret, inaccessible, false, 0, -1, 1.5, 100001 }) do
				UnitRace = function() return "Zwerg", "Dwarf", value end
				assert(addon.API.GetPlayerRaceID() == nil)
				assert(addon.API.GetLocalizedRaceName(value) == nil)
			end
			for _, value in ipairs({ secret, inaccessible, false, 42 }) do
				C_CreatureInfo = { GetRaceInfo = function() return value end }
				assert(addon.API.GetLocalizedRaceName(3) == nil)
				C_CreatureInfo = { GetRaceInfo = function() return { raceName = value } end }
				LOCALIZED_CLASS_NAMES_MALE = { MAGE = value }
				assert(addon.API.GetLocalizedRaceName(3) == nil)
				assert(addon.API.GetLocalizedClassName("MAGE") == nil)
			end
			C_CreatureInfo, LOCALIZED_CLASS_NAMES_MALE = inaccessible, inaccessible
			assert(addon.API.GetLocalizedRaceName(3) == nil)
			assert(addon.API.GetLocalizedClassName("MAGE") == nil)
			C_CreatureInfo, LOCALIZED_CLASS_NAMES_MALE = nil, nil
			assert(addon.API.GetLocalizedRaceName(3) == nil)
			assert(addon.API.GetLocalizedClassName("MAGE") == nil)
			UnitRace = function() error("unavailable") end
			assert(addon.API.GetPlayerRaceID() == nil)
			assert(inaccessibleReads == 0)
			UnitRace, C_CreatureInfo, LOCALIZED_CLASS_NAMES_MALE = oldRace, oldInfo, oldClasses
		end
		local className, classFile = "Priest", "PRIEST"
		UnitClass = function() return className, classFile end
		local safeName, safeFile = addon.API.UnitClass("player")
		assert(safeName == "Priest" and safeFile == "PRIEST")
		className, classFile = secret, inaccessible
		safeName, safeFile = addon.API.UnitClass("player")
		assert(safeName == nil and safeFile == nil)
		className, classFile = 42, false
		safeName, safeFile = addon.API.UnitClass("player")
		assert(safeName == nil and safeFile == nil)
		UnitFullName = function() return className, classFile end
		safeName, safeFile = addon.API.UnitFullName("player")
		assert(safeName == nil and safeFile == nil, "names must be strings")
		className, classFile = secret, inaccessible
		safeName, safeFile = addon.API.UnitFullName("player")
		assert(safeName == nil and safeFile == nil)
		className, classFile = "Torres Sky", "Realm"
		safeName, safeFile = addon.API.UnitFullName("player")
		assert(safeName == "Torres Sky" and safeFile == "Realm")
		local taskTitle = "World Quest"
		C_TaskQuest = { GetQuestInfoByQuestID = function() return taskTitle end }
		assert(addon.API.GetTaskQuestInfoByQuestID(12345).questTitle == "World Quest")
		for _, value in ipairs({ secret, inaccessible, 42, "" }) do
			taskTitle = value
			assert(addon.API.GetTaskQuestInfoByQuestID(12345).questTitle == nil)
		end

		RAID_CLASS_COLORS = { PRIEST = { colorStr = "ffffffff" } }
		CUSTOM_CLASS_COLORS = { PRIEST = { colorStr = "ff123456" } }
		assert(addon:GetClassColorCode("PRIEST") == "|cff123456")
		CUSTOM_CLASS_COLORS = inaccessible
		assert(addon:GetClassColorCode("PRIEST") == "|cffffffff")
		CUSTOM_CLASS_COLORS = { PRIEST = inaccessible }
		assert(addon:GetClassColorCode("PRIEST") == "|cffffffff")
		CUSTOM_CLASS_COLORS = { PRIEST = { colorStr = inaccessible } }
		assert(addon:GetClassColorCode("PRIEST") == "|cffffffff")
		CUSTOM_CLASS_COLORS.PRIEST.colorStr = "not a color"
		assert(addon:GetClassColorCode("PRIEST") == "|cffffffff")
		assert(addon:GetClassColorCode(secret) == "|cffffffff")
		assert(addon:GetClassColorCode(inaccessible) == "|cffffffff")

		local waypointAddon = setmetatable({ API = { IsAddOnLoaded = function() return true end } }, { __index = addon })
		TomTom = inaccessible
		assert(waypointAddon:CreateTomTomWaypoint(84, 25, 50) == false)
		TomTom = { AddWaypoint = inaccessible }
		assert(waypointAddon:CreateTomTomWaypoint(84, 25, 50) == false)
		local waypointCalls = 0
		TomTom = { AddWaypoint = function(owner, mapID, x, y, options)
			assert(owner == TomTom and mapID == 84 and x == 0.25 and y == 0.5)
			assert(options.from == "QuestTogether/ping")
				waypointCalls = waypointCalls + 1
				return { mapID, x, y }
		end }
		assert(waypointAddon:CreateTomTomWaypoint(84, 25, 50) == true and waypointCalls == 1)
		TomTom = nil
		assert(waypointAddon:CreateTomTomWaypoint(84, 25, 50) == false)
		QuestieLoader = { _modules = { QuestieTooltips = { GetTooltip = inaccessible } } }
		assert(addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000") == nil)
		QuestieLoader = inaccessible
		assert(addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000") == nil)
			local questieRows = { "|cffffffffWolf Hunt|r", "8/8 Wolves slain", inaccessible, "0/4 Eggs collected" }
			QuestieLoader = { _modules = { QuestieTooltips = { GetTooltip = function(key)
				assert(key == "m_12345")
				return questieRows
			end } } }
			local questieLines = addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000")
			assert(questieLines[1].leftText == "Wolf Hunt" and questieLines.hasIncompleteQuestData == true,
				"Questie must retain the incomplete-data signal after copying readable text")
			local questTextCache = addon.nameplateQuestTextCache
			local originalQuestTextCache = addon:DeepCopy(questTextCache)
			local tracker = addon:GetPlayerTracker()
			local originalTrackedQuest = tracker[12345]
			-- A shared objective label is not a title. Model the owned quest whose
			-- readable title may reopen the later raw block after unavailable data.
			tracker[12345] = { title = "Wolf Hunt" }
			wipe(questTextCache)
			questTextCache["Wolf Hunt"] = true
			local relevant, complete, readable = addon:EvaluateTooltipQuestObjectiveLines(questieLines)
			assert(relevant == false and complete == false and readable == false,
				"unreadable Questie rows must break quest blocks and cannot certify completion")
			questieRows = { "|cffffffffWolf Hunt|r", "8/8 Wolves slain", inaccessible, "Wolf Hunt", "2/8 Wolves slain" }
			questieLines = addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000")
			assert(addon:EvaluateTooltipQuestObjectiveLines(questieLines) == true,
				"a separately identified readable quest block may still establish positive evidence")
			tracker[12345] = originalTrackedQuest
			wipe(questTextCache)
			for text, known in pairs(originalQuestTextCache) do questTextCache[text] = known end
		-- Offline-only foreign-frame contracts: never modify WorldMapFrame in live tests.
		WorldMapFrame = nil
		assert(addon.API.IsWorldMapVisible() == false)
		WorldMapFrame = { IsShown = function() return true end }
		assert(addon.API.IsWorldMapVisible() == true)
		WorldMapFrame.IsShown = function() return false end
		assert(addon.API.IsWorldMapVisible() == false)
			WorldMapFrame.IsForbidden = function() return true end
			local forbiddenVisibilityReads = 0
			WorldMapFrame.IsShown = function()
				forbiddenVisibilityReads = forbiddenVisibilityReads + 1
				error("forbidden map must not be read")
			end
			assert(addon.API.IsWorldMapVisible() == true)
			assert(forbiddenVisibilityReads == 0, "pcall must not hide forbidden map reads")
		WorldMapFrame = inaccessible
		assert(addon.API.IsWorldMapVisible() == true)
		WorldMapFrame = { IsShown = function() return secret end }
		assert(addon.API.IsWorldMapVisible() == true)
		WorldMapFrame = { IsShown = function() error("visibility unavailable") end }
		assert(addon.API.IsWorldMapVisible() == true)
		WorldMapFrame = nil
		-- Exercise real HUD adapters only in this standalone process. Live tests
		-- inject addon-owned wrappers and never replace these client globals.
		local originalAddOns, originalLoader, originalPanel, originalManager = C_AddOns, LoadAddOn, ShowUIPanel, EditModeManagerFrame
		local loads, legacyLoads, shows = 0, 0, 0
		local manager = {
			IsForbidden = function() return false end,
			IsProtected = function() return false, false end,
			IsShown = function(self) return self.shown == true end,
			CanEnterEditMode = function() return true end,
			EnterEditMode = function() error("internal entry must be owned by native OnShow") end,
		}
		local loadedValue = true
		C_AddOns = { LoadAddOn = function(name)
			assert(name == "Blizzard_EditMode")
			loads = loads + 1
			EditModeManagerFrame = manager
			return loadedValue
		end }
		LoadAddOn = function(name)
			assert(name == "Blizzard_EditMode")
			legacyLoads = legacyLoads + 1
			return true
		end
		ShowUIPanel = function(frame)
			assert(frame == manager)
			shows = shows + 1
			frame.shown = true -- Native ShowUIPanel returns no success boolean.
		end
		EditModeManagerFrame = nil
		local hud = setmetatable({ IsRuntimeRestrictionTypeActive = function() return false end }, { __index = addon })
		assert(hud:OpenHudEditMode() and manager.shown and loads == 1 and shows == 1 and legacyLoads == 0)
		loadedValue = secret
		assert(addon.API.LoadEditMode() == false, "secret load results must not become success")
		C_AddOns.LoadAddOn = function() error("load unavailable") end
		assert(addon.API.LoadEditMode() == false and legacyLoads == 0, "failed modern load must not invoke another loader")
		C_AddOns = nil
		assert(addon.API.LoadEditMode() and legacyLoads == 1)
		LoadAddOn = nil
		assert(addon.API.LoadEditMode() == false)
		ShowUIPanel = function() error("panel unavailable") end
		assert(addon.API.ShowUIPanel(manager) == false)
		manager.IsForbidden = function() return true end
		ShowUIPanel = function() shows = shows + 1 end
		assert(addon.API.ShowUIPanel(manager) == false and shows == 1,
			"forbidden manager must not reach ShowUIPanel")
		EditModeManagerFrame = inaccessible
		assert(hud:OpenHudEditMode() == false, "inaccessible manager must not reach its methods")
		C_AddOns, LoadAddOn, ShowUIPanel, EditModeManagerFrame = originalAddOns, originalLoader, originalPanel, originalManager
		-- Native Retail/Forever enums: Chat=5, Inactive=0, Activating=1, Active=2.
		-- Exercise the real reader and report only in this standalone process;
		-- live tests must never replace the restriction API or Blizzard enums.
		local originalRestrictionTypes, originalRestrictedActions = Enum.AddOnRestrictionType, C_RestrictedActions
		Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
		local diagnostic = setmetatable({
			runtimeStateStore = {}, debugLogLines = {}, db = { profile = {}, global = {} },
			API = { InCombatLockdown = function() return false end, IsWorldMapVisible = function() return false end },
			GetOption = function() return false end,
			GetPlayerTracker = function() return {} end,
		}, { __index = addon })
		local chatQueries = 0
		for _, case in ipairs({
			{ state = 0, expected = false }, { state = 1, expected = true }, { state = 2, expected = true },
			{ expected = true }, { throws = true, expected = true },
			{ state = secret, expected = true }, { state = inaccessible, expected = true },
		}) do
			C_RestrictedActions = { GetAddOnRestrictionState = function(kind)
				if kind == 5 then
					chatQueries = chatQueries + 1
					if case.throws then error("chat restriction unavailable") end
					return case.state
				end
				return 0
			end }
			chatQueries = 0
			assert(diagnostic:IsRuntimeRestrictionTypeActive("CHAT") == case.expected)
			assert(chatQueries == 1, "Chat must query its native enum instead of returning the unsupported-type fallback")
			assert(diagnostic.runtimeRestrictionTypes.chat == nil and diagnostic:IsRuntimeRestricted() == false,
				"Chat restriction reporting must not block unrelated UI or quest work")
			chatQueries = 0
			local report = diagnostic:BuildDiagnosticReport()
			assert(report:find("restriction.chat=" .. tostring(case.expected), 1, true))
			assert(chatQueries == 1, "the actual diagnostic report must read Chat state")
		end
		chatQueries = 0
		Enum.AddOnRestrictionType.Chat = nil
		assert(diagnostic:IsRuntimeRestrictionTypeActive("chat") == false and chatQueries == 0)
		Enum.AddOnRestrictionType.Chat = 5
		C_RestrictedActions = {}
		assert(diagnostic:IsRuntimeRestrictionTypeActive("chat") == false)
		C_RestrictedActions = nil
		assert(diagnostic:IsRuntimeRestrictionTypeActive("chat") == false)
		Enum.AddOnRestrictionType, C_RestrictedActions = originalRestrictionTypes, originalRestrictedActions
		-- SetUserWaypoint returns boolean wasSet (Retail/Forever generated API).
		-- Exercise the real adapter without replacing any global in live tests.
		local originalMap, originalPoint, originalTrack = C_Map, UiMapPoint, C_SuperTrack
		local native = { mode = "accept", point = { uiMapID = 7 }, tracks = 0, writes = 0, canSet = true }
		UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, x = x, y = y } end }
		C_Map = {
			CanSetUserWaypointOnMap = function() return native.canSet end,
			SetUserWaypoint = function(point)
				native.writes = native.writes + 1
				if native.mode == "throw" then error("native waypoint rejected") end
				if native.mode == "secret" then return secret end
				if native.mode == "inaccessible" then return inaccessible end
				if native.mode == "missing" then return nil end
				if native.mode == "reject" then return false end
				native.point = point
				return true
			end,
		}
		C_SuperTrack = { SetSuperTrackedUserWaypoint = function() native.tracks = native.tracks + 1 end }
		local waypoint = setmetatable({ runtimeStateStore = {}, isEnabled = true, IsWorkBlocked = function() return false end }, { __index = addon })
		for _, mode in ipairs({ "accept", "reject", "throw", "secret", "inaccessible", "missing" }) do
			native.mode, native.point, native.tracks, native.writes = mode, { uiMapID = 7 }, 0, 0
			assert(waypoint:CreateBlizzardWaypoint(84, 25, 50) == (mode == "accept"), mode)
			assert(native.writes == 1 and native.tracks == (mode == "accept" and 1 or 0), mode)
			assert(native.point.uiMapID == (mode == "accept" and 84 or 7), "rejection must retain but never track the old pin")
			assert(waypoint:GetRuntimeWorkStateStore().pendingWaypointIntent == nil)
		end
		native.canSet, native.writes = secret, 0
		assert(waypoint:CreateBlizzardWaypoint(84, 25, 50) == false and native.writes == 0)
		native.canSet, C_Map.SetUserWaypoint = true, nil
		assert(waypoint:CreateBlizzardWaypoint(84, 25, 50) == false and native.tracks == 0)
		C_Map, UiMapPoint, C_SuperTrack = originalMap, originalPoint, originalTrack
		print("Offline " .. client .. " quest API contract checks passed.")
	end
end
