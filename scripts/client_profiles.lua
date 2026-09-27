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
		return row.title, 20, nil, false, false, nil, nil, row.questID
	end or nil
	GetQuestLogSelection = function() return selected end
	GetQuestLogPushable = function() return pushable end
	SelectQuestLogEntry = function() error("addon must not move selected quest") end
	GetNumQuestLeaderBoards = function(index) assert(index == 7); return 1 end
	C_QuestLog = {
		GetQuestObjectives = function(id) assert(id == 12345); return { objective } end,
		GetInfo = not classic and Info or nil,
		GetLogIndexForQuestID = not classic and function(id) assert(id == 12345); return 7 end or nil,
		SetSelectedQuest = function() error("addon must not move selected quest") end,
		GetNumQuestLogEntries = not classic and function() return 7 end or nil,
		IsPushableQuest = not classic and function(id) assert(id == 12345); return pushable end or nil,
	}
	GetQuestObjectiveInfo = not classic and function(id, index)
		assert(id == 12345 and index == 1)
		return objective.text, objective.type, objective.finished, objective.numFulfilled
	end or nil
	return function(addon)
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
				C_QuestLog.GetLogIndexForQuestID = function(id) assert(id == 12345); return rawIndex end
				C_QuestLog.GetInfo = function(index) assert(index == rawIndex); return rawRow end
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
		WorldMapFrame.IsShown = function() error("forbidden map must not be read") end
		assert(addon.API.IsWorldMapVisible() == true)
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
