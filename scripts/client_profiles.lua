-- Offline-only client contracts. No real game globals are changed by these checks.
return function(client)
	local profiles = { retail = "12.1.0", forever = "1.60.1", era = "1.15.9", tbc = "2.5.6", mists = "5.5.4", titan = "3.80.2" }
	assert(profiles[client], "unknown client profile")
	local classic = client ~= "retail" and client ~= "forever"
	local selected, pushable, secret = 7, true, {}
	local inaccessible = setmetatable({}, {
		__index = function() error("inaccessible fixture must not be indexed") end,
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
		return row.title, 20, nil, false, false, row.isComplete, nil, row.questID
	end or nil
	GetQuestLogSelection = function() return selected end
	GetQuestLogPushable = function() return pushable end
	SelectQuestLogEntry = function() error("addon must not move selected quest") end
	GetNumQuestLeaderBoards = function(index) assert(index == 7); return 1 end
	C_QuestLog = {
		GetQuestObjectives = function(id) assert(id == 12345); return { objective } end,
		GetInfo = not classic and Info or nil,
		GetNumQuestLogEntries = not classic and function() return 7 end or nil,
		IsPushableQuest = not classic and function(id) assert(id == 12345); return pushable end or nil,
	}
	GetQuestObjectiveInfo = not classic and function(id, index)
		assert(id == 12345 and index == 1)
		return objective.text, objective.type, objective.finished, objective.numFulfilled
	end or nil
	return function(addon)
		assert(addon.API.GetQuestLogInfo(7).questID == 12345)
		assert(addon.API.GetQuestLogIndexForQuestID(12345) == 7)
		local text, kind, done, count = addon.API.GetQuestObjectiveInfo(12345, 1, false)
		assert(text == "Wolves slain: 2/5" and kind == "monster" and done == false and count == 2)
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
		end }
		assert(waypointAddon:CreateTomTomWaypoint(84, 25, 50) == true and waypointCalls == 1)
		TomTom = nil
		assert(waypointAddon:CreateTomTomWaypoint(84, 25, 50) == false)
		QuestieLoader = { _modules = { QuestieTooltips = { GetTooltip = inaccessible } } }
		assert(addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000") == nil)
		QuestieLoader = inaccessible
		assert(addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000") == nil)
		QuestieLoader = { _modules = { QuestieTooltips = { GetTooltip = function(key)
			assert(key == "m_12345")
			return { "|cffffffffWolf Hunt|r", inaccessible, "must not read past inaccessible data" }
		end } } }
		local questieLines = addon:GetQuestieQuestObjectiveTooltipLines("Creature-0-0-0-0-12345-0000000000")
		assert(#questieLines == 1 and questieLines[1].leftText == "Wolf Hunt")
		print("Offline " .. client .. " quest API contract checks passed.")
	end
end
