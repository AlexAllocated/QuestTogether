-- Offline-only client contracts. No real game globals are changed by these checks.
return function(client)
	local profiles = { retail = "12.1.0", forever = "1.60.1", era = "1.15.9", tbc = "2.5.6", mists = "5.5.4", titan = "3.80.2" }
	assert(profiles[client], "unknown client profile")
	local classic = client ~= "retail" and client ~= "forever"
	local selected, pushable, secret = 7, true, {}
	local objective = { text = "Wolves slain: 2/5", type = "monster", finished = false, numFulfilled = 2, numRequired = 5 }
	issecretvalue = function(value) return value == secret end
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
		print("Offline " .. client .. " quest API contract checks passed.")
	end
end
