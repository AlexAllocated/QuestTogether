-- Exercise nameplate events through the real resolver, scheduler and presenter.
-- All API replacements and UI stand-ins are QuestTogether-owned fixtures.
local QT = _G.QuestTogether
local function Equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function WithPlate(fn)
	local state = {
		guid = "Creature-0-0-0-0-12345-0000000000", combat = true,
		present = true, shown = true, fillReady = true, tooltipReady = true,
		reads = 0, callbacks = {}, now = 0, sequence = 0, creations = 0,
	}
	local function Region(parent, shown)
		local region = { parent = parent, shown = shown == true }
		function region:IsForbidden()
			return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
		end
		function region:IsProtected()
			return self.protected == true or (self.parent and self.parent:IsProtected()) or false
		end
		function region:IsShown() return self.shown end
		function region:IsVisible()
			return self:IsShown() and (not self.parent or self.parent:IsVisible())
		end
		function region:GetParent() return self.parent end
		local function CheckMutation(self)
			assert(not self:IsForbidden(), "forbidden visual mutated")
			assert(not (self:IsProtected() and (state.combat or state.restriction)), "protected visual mutated while restricted")
		end
		function region:Show() CheckMutation(self); self.shown = true end
		function region:Hide() CheckMutation(self); self.shown = false end
		function region:SetParent(newParent) CheckMutation(self); self.parent = newParent end
		function region:GetFrameStrata() return "LOW" end
		function region:GetFrameLevel() return 1 end
		for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetAllPoints", "SetVertexColor", "SetColorTexture", "SetAlpha", "SetFrameStrata", "SetFrameLevel", "SetTexture", "SetTexCoord", "SetAtlas", "SetBlendMode" }) do
			region[method] = CheckMutation
		end
		function region:CreateTexture(_, _, _, subLevel)
			CheckMutation(self)
			local texture = Region(self, true)
			if self == state.healthBar then
				if subLevel == 1 then state.highlight = texture else state.fill = texture end
			end
			return texture
		end
		return region
	end
	local plate = Region(nil, true)
	function plate:IsShown() return state.shown end
	local frame = Region(plate, true)
	function frame:IsProtected() return state.protected == true or self.parent:IsProtected() end
	frame.unit = "nameplate1"
	local healthBar = Region(frame, true)
	local liveFill = Region(healthBar, true)
	function liveFill:IsShown() return state.fillReady end
	function healthBar:GetStatusBarTexture() return liveFill end
	function healthBar:GetAlpha() return 1 end
	frame.healthBar, plate.UnitFrame = healthBar, frame
	state.frame, state.plate, state.healthBar = frame, plate, healthBar
	local icon, fill, highlight = Region(frame), Region(healthBar), Region(healthBar)
	icon.Icon = Region(icon, true)
	state.icon, state.fill, state.highlight = icon, fill, highlight
	local function SortCallbacks()
		table.sort(state.callbacks, function(a, b)
			return a.at < b.at or (a.at == b.at and a.sequence < b.sequence)
		end)
	end
	state.step = function()
		SortCallbacks()
		local entry = table.remove(state.callbacks, 1)
		if entry then state.now = entry.at; entry.callback() end
	end
	state.advance = function(seconds)
		local deadline, count = state.now + seconds, 0
		SortCallbacks()
		while state.callbacks[1] and state.callbacks[1].at <= deadline do
			count = count + 1
			assert(count < 100, "nameplate callbacks must not spin at the same deadline")
			state.step()
			SortCallbacks()
		end
		state.now = deadline
	end
	state.drain = function()
		local count = 0
		while #state.callbacks > 0 do
			count = count + 1
			assert(count < 40, "nameplate retries must be bounded")
			state.step()
		end
	end
	local canAccessTable = QT.CanAccessTable
	local wakeFrame = { SetScript = function(_, _, callback) state.onMapUpdate = callback end }
	local replacements = {
		mapWorkWakeFrame = wakeFrame,
		mapWorkWakeState = false,
		CreateMapWorkWakeFrame = function() return wakeFrame end,
		CanAccessTable = function(self, value)
			return value ~= state.inaccessible and canAccessTable(self, value)
		end,
		CreateNameplateQuestIconFrame = function(_, parent)
			Equal(parent, frame)
			assert(not (parent:IsProtected() and state.combat), "protected parent used for first-time creation")
			state.creations = state.creations + 1
			state.icon = Region(parent)
			return state.icon
		end,
		API = {
			GetNamePlateForUnit = function(token)
				Equal(token, "nameplate1")
				return state.present and plate or nil
			end,
			GetNamePlates = function() return state.present and { plate } or {} end,
			UnitGUID = function() return state.guid end,
			UnitExists = function() return state.present end,
			UnitIsPlayer = function() return false end,
			InCombatLockdown = function() return state.combat end,
			IsInInstance = function() return state.instance == true end,
			IsWorldMapVisible = function() return state.map == true end,
			Delay = function(seconds, callback)
				state.sequence = state.sequence + 1
				state.callbacks[#state.callbacks + 1] = { at = state.now + seconds, sequence = state.sequence, callback = callback }
			end,
			GetTooltipDataForUnit = function(token)
				Equal(token, "nameplate1")
				state.reads = state.reads + 1
				if not state.tooltipReady then return nil end
				if state.tooltipData then return state.tooltipData end
				return { lines = {
					{ type = "QuestTitle", leftText = "Wolf Hunt" },
					{ type = "QuestObjective", leftText = state.complete and "Wolf pelts: 8/8" or "Wolf pelts: 1/8" },
				} }
			end,
		},
		IsRuntimeRestrictionTypeActive = function(_, kind) return state.restriction == kind end,
		IsNameplateUnitTapDenied = function() return state.denied == true end,
		GetQuestieQuestObjectiveTooltipLines = function()
			assert(not state.combat, "combat discovery must not invoke Questie")
			return nil
		end,
		GetHiddenQuestObjectiveTooltipLines = function()
			assert(not state.combat, "combat discovery must not mutate a hidden tooltip")
			return nil
		end,
	}
	local originals = {}
	for key, value in pairs(replacements) do originals[key], QT[key] = QT[key], value end
	QT.isEnabled = true
	QT.db.profile.nameplateQuestIconEnabled = true
	QT.db.profile.nameplateQuestHealthColorEnabled = true
	QT.nameplateQuestTextCache["Wolf Hunt"] = true
	QT.nameplateIconByUnitFrame[frame] = icon
	QT.nameplateHealthOverlayByUnitFrame[frame] = { FillTexture = fill, Highlight = highlight }
	local ok, err = pcall(fn, state)
	for key in pairs(replacements) do QT[key] = originals[key] end
	assert(ok, err)
end
local function Decorated(state)
	Equal(state.icon:IsVisible(), true, "quest icon missing or under a hidden parent")
	Equal(state.fill:IsVisible(), true, "quest tint missing or under a hidden parent")
	Equal(state.highlight:IsVisible(), true, "quest highlight missing or under a hidden parent")
end

local function Undecorated(state)
	Equal(state.icon:IsShown(), false, "completed mob regained its quest icon")
	Equal(state.fill:IsShown(), false, "completed mob regained its quest tint")
	Equal(state.highlight:IsShown(), false, "completed mob regained its quest highlight")
end

local function WithInstanceQuestCache(fn)
	WithPlate(function(state)
		state.combat, state.questLogReads = false, 0
		QT.API.GetNumQuestLogEntries = function()
			assert(not state.combat and not state.map and not state.restriction, "restricted quest log read")
			state.questLogReads = state.questLogReads + 1
			return 1
		end
		QT.API.GetQuestLogInfo = function(index)
			Equal(index, 1)
			return { questID = 123, questLogIndex = 1, title = "Wolf Hunt", isTask = false,
				isWorldQuest = false, isHeader = false, isHidden = false, isComplete = false,
				isOnMap = false, hasLocalPOI = false }
		end
		QT.API.GetQuestLogIndexByID = function(id) Equal(id, 123); return 1 end
		QT.API.GetNumQuestLeaderBoards = function(index) Equal(index, 1); return 1 end
		QT.API.GetQuestObjectiveInfo = function(id, index)
			Equal(id, 123); Equal(index, 1)
			return "Wolf pelts: 1/8", "item", false, 1
		end
		QT.API.IsWorldQuest = function() return false end
		QT.API.GetTaskQuestInfoByQuestID = function() return { displayAsObjective = false } end
		local originalJoin = QT.EnsureAnnouncementChannelJoined
		QT.EnsureAnnouncementChannelJoined = function() return true end
		local ok, err = pcall(function()
			QT:RebuildQuestSnapshotStore()
			QT:RebuildNameplateQuestTextCache()
			Equal(QT:GetQuestSnapshotStateStore().lastUnreadableRow, nil)
			Equal(QT:GetQuestSnapshotByQuestID()[123].title, "Wolf Hunt")
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Decorated(state)
			state.instance = true
			QT:HandleNameplateEvent("QUEST_LOG_UPDATE")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestTextCache["Wolf Hunt"], nil)
			fn(state)
		end)
		QT.EnsureAnnouncementChannelJoined = originalJoin
		assert(ok, err)
	end)
end

QT:RegisterTest("instance exit rebuilds quest evidence without an additional quest event", function()
	WithInstanceQuestCache(function(state)
		state.instance = false
		local taskGeneration = QT:GetTaskAreaSubsystemStateStore().generation
		QT:PLAYER_ENTERING_WORLD()
		Equal(QT:GetTaskAreaSubsystemStateStore().lastScanFailure, nil)
		assert(QT:GetTaskAreaSubsystemStateStore().generation > taskGeneration)
		Equal(QT:GetTaskAreaSubsystemStateStore().resolvedByQuestID[123].title, "Wolf Hunt")
		QT:HandleNameplateEvent("PLAYER_ENTERING_WORLD")
		QT:ZONE_CHANGED_NEW_AREA()
		QT:HandleNameplateEvent("ZONE_CHANGED_NEW_AREA")
		local snapshotGeneration = QT:GetQuestSnapshotStateStore().generation
		state.advance(1.1)
		Equal(QT:GetQuestSnapshotStateStore().generation, snapshotGeneration + 1,
			"exit events must coalesce one snapshot rebuild")
		QT:OnNameplateAdded("nameplate1")
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		state.drain()
		Decorated(state)
		Equal(QT.nameplateQuestTextCache["Wolf Hunt"], true)
		local tooltipReads = state.reads
		local logReads = state.questLogReads
		for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
			QT:HandleNameplateEvent(event)
		end
		state.drain()
		Equal(state.questLogReads, logReads, "ordinary outdoor zone events must not rebuild quest data")
		Equal(state.reads, tooltipReads, "unchanged outdoor relevance must reuse positive evidence")
	end)
end)

QT:RegisterTest("instance exit quest rebuild waits through combat encounter and map restrictions", function()
	WithInstanceQuestCache(function(state)
		state.instance, state.combat, state.map, state.protected, state.restriction = false, true, true, true, "encounter"
		local logReads, tooltipReads = state.questLogReads, state.reads
		QT:HandleNameplateEvent("ZONE_CHANGED_NEW_AREA")
		QT:HandleNameplateEvent("PLAYER_ENTERING_WORLD")
		state.drain()
		Equal(state.questLogReads, logReads)
		Equal(state.reads, tooltipReads)
		state.combat = false
		QT:PLAYER_REGEN_ENABLED()
		state.drain()
		Equal(state.questLogReads, logReads)
		state.restriction = nil
		QT:ADDON_RESTRICTION_STATE_CHANGED()
		state.drain()
		Equal(state.questLogReads, logReads)
		state.map = false
		assert(state.onMapUpdate, "map-blocked recovery must install the owned watcher")
		state.onMapUpdate(nil, 0.2)
		state.drain()
		Equal(state.questLogReads, logReads + 1)
		Decorated(state)
	end)
end)

QT:RegisterTest("disabled instance exit work cannot rebuild into the next enabled lifetime", function()
	WithInstanceQuestCache(function(state)
		state.instance = false
		QT:HandleNameplateEvent("PLAYER_ENTERING_WORLD")
		local logReads = state.questLogReads
		QT:Disable()
		state.advance(0.2)
		Equal(state.questLogReads, logReads, "disabled exit callback must be cancelled")
		QT.isEnabled = true
		QT:EnableNameplateAugmentation()
		state.advance(0.85)
		Equal(state.questLogReads, logReads, "old exit callback must not run after reenable")
		state.advance(0.2)
		Equal(state.questLogReads, logReads + 1, "new augmentation lifetime must rebuild independently")
		Decorated(state)
		state.drain()
	end)
end)

QT:RegisterTest("completed mob type overrides an older spawn's positive combat cache", function()
	WithPlate(function(state)
		local oldSpawn = "Creature-0-0-0-0-12345-0000000001"
		QT:StoreResolvedNameplateQuestState("nameplate2", oldSpawn, true)
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Undecorated(state)
		QT:OnNameplateRemoved("nameplate1")
		state.guid, state.tooltipReady = oldSpawn, false
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Undecorated(state)
		QT:HandleNameplateEvent("UNIT_HEALTH", "nameplate1")
		state.drain()
		Undecorated(state)
	end)
end)

QT:RegisterTest("completed quest state survives spawn churn without a readable combat tooltip", function()
	WithPlate(function(state)
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(QT.nameplateQuestStateByGuid[state.guid], false)
		QT:OnNameplateRemoved("nameplate1")
		state.guid = "Creature-0-0-0-0-12345-0000000002"
		state.tooltipReady = false
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		local resolved, needed = QT:TryResolveNameplateQuestObjectiveState("nameplate1", state.frame, false)
		Equal(resolved, true, "new spawn should reuse confirmed completion by NPC ID")
		Equal(needed, false)
		Undecorated(state)
		QT:OnNameplateRemoved("nameplate1")
		state.guid = "Creature-0-0-0-0-54321-0000000002"
		state.tooltipReady, state.complete = true, false
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("readable unfinished party progress supersedes remembered mob completion", function()
	WithPlate(function(state)
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		QT:OnNameplateRemoved("nameplate1")
		state.tooltipData = { lines = {
			{ type = "QuestTitle", leftText = "Wolf Hunt" },
			{ type = "QuestObjective", leftText = "Wolf pelts: 8/8" },
			{ type = "QuestPlayer", leftText = "Friend-Realm" },
			{ type = "QuestObjective", leftText = "Wolf pelts: 7/8" },
		} }
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("quest state changes let a completed mob become needed again", function()
	WithPlate(function(state)
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		state.complete = false
		QT:HandleNameplateEvent("QUEST_ACCEPTED", 123)
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("partial tooltip data cannot record a mob type as completed", function()
	WithPlate(function(state)
		state.inaccessible = setmetatable({}, {
			__index = function() error("inaccessible objective traversed") end,
		})
		state.tooltipData = { lines = {
			{ type = "QuestTitle", leftText = "Wolf Hunt" },
			{ type = "QuestObjective", leftText = "Wolf pelts: 8/8" },
			state.inaccessible,
		} }
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		state.guid = "Creature-0-0-0-0-12345-0000000002"
		state.tooltipReady = false
		local resolved = QT:TryResolveNameplateQuestObjectiveState("nameplate1", state.frame, false)
		Equal(resolved, false, "incomplete tooltip is not proof everyone finished")
	end)
end)

QT:RegisterTest("an initially empty quest block can recover after negative state is cached", function()
	WithPlate(function(state)
		state.tooltipData = { lines = { { type = "QuestTitle", leftText = "Wolf Hunt" } } }
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Undecorated(state)
		state.tooltipData = nil
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("completed creature evidence does not transfer to pets or survive runtime reset", function()
	WithPlate(function(state)
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		local resolved, needed = QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-0000000002")
		Equal(resolved, true)
		Equal(needed, false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Pet-0-0-0-0-12345-0000000002"), false)
		QT:ResetNameplateStateStore()
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-0000000002"), false)
	end)
end)

QT:RegisterTest("first seen quest mob gains both decorations during open world combat", function()
	WithPlate(function(state)
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		Equal(state.combat, true)
		Equal(state.reads, 1)
	end)
end)

QT:RegisterTest("plate returning from behind the camera retries quest discovery", function()
	WithPlate(function(state)
		state.shown = false
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.reads, 0)
		state.shown = true
		QT:HandleNameplateEvent("NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", "nameplate1", false)
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("late tooltip data retries even when the mob already has a guid", function()
	WithPlate(function(state)
		state.tooltipReady = false
		QT:OnNameplateAdded("nameplate1")
		Equal(state.icon.shown, false)
		state.tooltipReady = true
		state.drain()
		Decorated(state)
		Equal(state.reads, 2)
	end)
end)

QT:RegisterTest("initial negative tooltip result receives a bounded follow up", function()
	WithPlate(function(state)
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		Equal(state.icon.shown, false)
		state.complete = false
		state.drain()
		Decorated(state)
		Equal(state.reads, 2)
	end)
end)

QT:RegisterTest("nameplate frame that arrives after the first callback is retried", function()
	WithPlate(function(state)
		state.present = false
		QT:OnNameplateAdded("nameplate1")
		state.step()
		state.present = true
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("health refresh restores icon and tint together from cached quest state", function()
	WithPlate(function(state)
		QT:StoreResolvedNameplateQuestState("nameplate1", state.guid, true)
		QT:HandleNameplateEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
		state.drain()
		Decorated(state)
		Equal(state.reads, 0, "cached combat presentation must not scan tooltips")
	end)
end)

QT:RegisterTest("nameplate discovery still defers map and encounter work", function()
	WithPlate(function(state)
		state.map = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.reads, 0)
		state.map, state.restriction = false, "encounter"
		Equal(type(state.onMapUpdate), "function", "map-blocked work must install its owned wakeup")
		state.onMapUpdate(nil, 0.2)
		state.drain()
		Equal(state.reads, 0)
		state.restriction = nil
		QT:ADDON_RESTRICTION_STATE_CHANGED()
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("quest discovery does not decorate instance mobs or denied taps", function()
	WithPlate(function(state)
		state.instance = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.reads, 0)
		state.instance, state.denied = false, true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
	end)
end)

QT:RegisterTest("missing tooltip data stops retrying and mouseover can restart discovery", function()
	WithPlate(function(state)
		state.tooltipReady = false
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		assert(state.reads > 1 and state.reads <= 5, "expected a bounded tooltip retry budget")
		Equal(#state.callbacks, 0)
		state.tooltipReady = true
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("delayed tooltip callback cannot resolve a removed or recycled plate", function()
	WithPlate(function(state)
		state.tooltipReady = false
		QT:OnNameplateAdded("nameplate1")
		QT:OnNameplateRemoved("nameplate1")
		state.guid = "Creature-0-0-0-0-54321-0000000000"
		state.tooltipReady = true
		state.drain()
		Equal(state.reads, 1)
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
	end)
end)

QT:RegisterTest("missing live guid never reuses a recycled combat frame identity or loops tint refreshes", function()
	WithPlate(function(state)
		local oldGuid = state.guid
		state.frame.unitGUID = oldGuid
		QT.nameplateQuestStateByGuid[oldGuid] = true
		state.guid = nil
		Equal(QT:GetNameplateTooltipScanGuid("nameplate1", state.frame), nil)
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		assert(state.reads > 1 and state.reads <= 5, "missing guid must use bounded discovery retries")
		Equal(QT.nameplateQuestGuidByUnitToken.nameplate1, nil)
		state.guid = "Creature-0-0-0-0-67890-0000000000"
		QT:HandleNameplateEvent("PLAYER_TARGET_CHANGED")
		state.drain()
		Equal(QT.nameplateQuestGuidByUnitToken.nameplate1, state.guid)
		Decorated(state)
	end)
end)

QT:RegisterTest("combat discovery leaves protected visuals untouched until combat ends", function()
	WithPlate(function(state)
		state.protected = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
		state.combat = false
		QT:HandleNameplateEvent("PLAYER_REGEN_ENABLED")
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("late health fill can recover tint without another tooltip scan", function()
	WithPlate(function(state)
		state.fillReady = false
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.icon.shown, true)
		Equal(state.fill.shown, false)
		state.fillReady = true
		QT:HandleNameplateEvent("UNIT_HEALTH", "nameplate1")
		state.drain()
		Decorated(state)
		Equal(state.reads, 1)
	end)
end)

QT:RegisterTest("combat nameplate work keeps noncombat restrictions and unrelated work blocked", function()
	WithPlate(function(state)
		Equal(QT:IsWorkBlocked("nameplate_tooltip_resolve"), false)
		Equal(QT:IsWorkBlocked("nameplate_refresh"), false)
		Equal(QT:IsWorkBlocked("foreign_frame_mutation"), true)
		Equal(QT:IsWorkBlocked("quest_snapshot_refresh"), true)
		for _, restriction in ipairs({ "encounter", "challenge", "pvp", "map" }) do
			state.restriction = restriction
			Equal(QT:IsWorkBlocked("nameplate_tooltip_resolve"), true)
			Equal(QT:IsWorkBlocked("nameplate_refresh"), true)
			Equal(QT:IsWorkBlocked("nameplate_tint_refresh"), true)
		end
	end)
end)

QT:RegisterTest("combat quest discovery never traverses inaccessible tooltip containers", function()
	WithPlate(function(state)
		state.inaccessible = setmetatable({}, {
			__index = function() error("inaccessible tooltip traversed") end,
			__tostring = function() error("inaccessible tooltip formatted") end,
		})
		state.tooltipData = state.inaccessible
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
		state.tooltipData = { lines = state.inaccessible }
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		state.drain()
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
	end)
end)

QT:RegisterTest("completed objective updates an existing positive plate through combat quest events", function()
	WithPlate(function(state)
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		local initialReads = state.reads
		state.complete = true
		QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
		QT:HandleNameplateEvent("QUEST_LOG_UPDATE")
		Equal(QT.nameplateQuestStateByGuid[state.guid], nil, "quest events must retire old GUID evidence immediately")
		state.advance(0.9)
		Equal(state.reads, initialReads, "quest-data refresh must honor its delay")
		state.advance(0.11)
		Undecorated(state)
		Equal(state.reads, initialReads + 1, "coalesced events should read the current tooltip once")
		Equal(state.combat, true)
		Equal(QT:IsWorkBlocked("quest_snapshot_refresh"), true, "combat fix must not relax the quest-log restriction")
	end)
end)

QT:RegisterTest("quest event invalidation cannot reuse old positive evidence when fresh tooltip data is unavailable", function()
	WithPlate(function(state)
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		state.tooltipReady = false
		QT:HandleNameplateEvent("QUEST_REMOVED", 123)
		state.drain()
		Undecorated(state)
		Equal(QT.nameplateQuestStateByGuid[state.guid], nil)
	end)
end)

QT:RegisterTest("combat quest refresh still waits for encounter challenge pvp and map restrictions", function()
	WithPlate(function(state)
		for _, restriction in ipairs({ "encounter", "challenge", "pvp", "map" }) do
			state.complete = false
			QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
			state.drain()
			Decorated(state)
			local readsBefore = state.reads
			state.complete, state.restriction = true, restriction
			QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
			state.drain()
			Equal(state.reads, readsBefore, restriction .. " must keep live tooltip work deferred")
			state.restriction = nil
			QT:ADDON_RESTRICTION_STATE_CHANGED()
			state.drain()
			Undecorated(state)
		end
	end)
end)

QT:RegisterTest("first-time combat decoration creates an icon and textures under the current visible hierarchy", function()
	WithPlate(function(state)
		QT.nameplateIconByUnitFrame[state.frame] = nil
		QT.nameplateHealthOverlayByUnitFrame[state.frame] = nil
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.creations, 1)
		Equal(state.icon:GetParent(), state.frame)
		Equal(state.fill:GetParent(), state.healthBar)
		Equal(state.highlight:GetParent(), state.healthBar)
		Decorated(state)
		state.shown = false
		Equal(state.icon:IsShown(), true)
		Equal(state.icon:IsVisible(), false, "a shown child is not visible under a hidden base")
	end)
end)

QT:RegisterTest("first-time decoration creates no children under protected combat frames", function()
	WithPlate(function(state)
		QT.nameplateIconByUnitFrame[state.frame] = nil
		QT.nameplateHealthOverlayByUnitFrame[state.frame] = nil
		state.protected = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Equal(state.creations, 0)
		Equal(QT.nameplateHealthOverlayByUnitFrame[state.frame], nil)
		state.combat = false
		QT:HandleNameplateEvent("PLAYER_REGEN_ENABLED")
		state.drain()
		Equal(state.creations, 1)
		Decorated(state)
	end)
end)

QT:RegisterTest("unowned quest progress cannot extend a preceding completed known quest block", function()
	QT.nameplateQuestTextCache["Known Quest"] = true
	local lines = QT:ExtractQuestObjectiveTooltipLinesFromTooltipData({ lines = {
		{ type = "QuestTitle", leftText = "Known Quest" },
		{ type = "QuestObjective", leftText = "Wolf pelts: 8/8" },
		{ type = "QuestTitle", leftText = "Unowned Other Quest" },
		{ type = "QuestObjective", leftText = "Wolf teeth: 0/4" },
	} })
	Equal(QT:EvaluateTooltipQuestObjectiveLines(lines), false)
end)

QT:RegisterTest("party progress remains relevant within a completed local quest block", function()
	QT.nameplateQuestTextCache["Known Quest"] = true
	local lines = QT:ExtractQuestObjectiveTooltipLinesFromTooltipData({ lines = {
		{ type = "QuestTitle", leftText = "Known Quest" },
		{ type = "QuestObjective", leftText = "Wolf pelts: 8/8" },
		{ type = "QuestPlayer", leftText = "Friend-Realm" },
		{ type = "QuestObjective", leftText = "Wolf pelts: 7/8" },
	} })
	Equal(QT:EvaluateTooltipQuestObjectiveLines(lines), true)
end)

QT:RegisterTest("delayed quest refresh discards positives repopulated before new tooltip data arrives", function()
	WithPlate(function(state)
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
		QT:HandleNameplateEvent("UNIT_HEALTH", "nameplate1")
		state.advance(0.1)
		Equal(QT.nameplateQuestStateByGuid[state.guid], true, "intervening health refresh still saw the old tooltip")
		state.complete = true
		state.advance(1)
		Undecorated(state)
		Equal(QT.nameplateQuestStateByGuid[state.guid], false)
	end)
end)

-- Keep the production adapters: live test isolation deliberately stubs Questie
-- and hidden tooltip access. Only the addon-owned foreign-access seams below
-- are replaced; no shared client globals or actual UI objects are changed.
local ReadQuestieLines = QT.GetQuestieQuestObjectiveTooltipLines
local ReadHiddenLines = QT.GetHiddenQuestObjectiveTooltipLines
local function WithFallbackSources(fn)
	WithPlate(function(state)
		state.combat, state.tooltipReady = false, false
		state.hiddenLines, state.hiddenReads, state.questieReads = {}, 0, 0
		local tooltip = {
			Hide = function() end, ClearLines = function() end,
			SetUnit = function(_, unitToken)
				Equal(unitToken, "nameplate1")
				assert(not state.combat and not state.map, "restricted hidden tooltip read")
				state.hiddenReads = state.hiddenReads + 1
			end,
			NumLines = function()
				if state.countUnavailable then error("unreadable line count") end
				return state.hiddenCount or #state.hiddenLines
			end,
		}
		local canAccessValue = QT.CanAccessValue
		local replacements = {
			GetQuestieQuestObjectiveTooltipLines = ReadQuestieLines,
			GetHiddenQuestObjectiveTooltipLines = ReadHiddenLines,
			GetQuestieTooltipDataForNpc = function(_, npcId)
				Equal(npcId, 12345)
				assert(not state.combat and not state.map, "restricted Questie read")
				state.questieReads = state.questieReads + 1
				return state.questieLines
			end,
			GetOrCreateNameplateScanTooltip = function() return tooltip end,
			GetNameplateScanTooltipFontString = function(_, scanTooltip, index)
				Equal(scanTooltip, tooltip)
				return { GetText = function()
					if index == state.errorRow then error("unreadable fontstring") end
					return state.hiddenLines[index]
				end }
			end,
			CanAccessValue = function(self, value)
				if state.inaccessibleValue and value == state.inaccessibleValue then return false end
				return canAccessValue(self, value)
			end,
		}
		local originals = {}
		for key, value in pairs(replacements) do originals[key], QT[key] = QT[key], value end
		QT.nameplateQuestTextCache["Known Quest"] = true
		local ok, err = pcall(fn, state)
		for key in pairs(replacements) do QT[key] = originals[key] end
		assert(ok, err)
	end)
end

QT:RegisterTest("real fallback adapters cannot attach another quest's progress to a completed known quest", function()
	WithFallbackSources(function(state)
		state.tooltipReady = true
		state.tooltipData = { lines = {
			{ type = "QuestTitle", leftText = "Known Quest" },
			{ type = "QuestObjective", leftText = "Wolf pelts: 8/8" },
			{ type = "QuestTitle", leftText = "Unowned Other Quest" },
			{ type = "QuestObjective", leftText = "Wolf teeth: 0/4" },
		} }
		for _, source in ipairs({ "hiddenLines", "questieLines" }) do
			state[source] = { "Known Quest", "Wolf pelts: 8/8", "Unowned Other Quest", "Wolf teeth: 0/4" }
			local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
			Equal(resolved, true)
			Equal(needed, false, source .. " overrode the structured rejection")
			state[source] = {}
		end
		assert(state.hiddenReads > 0 and state.questieReads > 0, "production fallback sources were not traversed")
	end)
end)

QT:RegisterTest("real fallback adapters retain known quest objectives and roster backed party progress", function()
	WithFallbackSources(function(state)
		QT.partyMembers = {
			["Friend-Realm"] = { displayName = "Friend" },
			["First Surname"] = { displayName = "First Surname" },
		}
		for _, source in ipairs({ "hiddenLines", "questieLines" }) do
			state[source] = { "Known Quest", "Wolf pelts: 1/8" }
			local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
			Equal(resolved, true)
			Equal(needed, true, source .. " lost the simple objective block")
			for _, name in ipairs({ "Friend", "Friend-Realm", "First Surname" }) do
				state[source] = { "Known Quest", "Wolf pelts: 8/8", "|cff00ff00" .. name .. "|r", "Wolf pelts: 7/8" }
				resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
				Equal(resolved, true)
				Equal(needed, true, source .. " lost recognized party progress for " .. name)
			end
			state[source] = { "Known Quest", "Wolf pelts: 8/8", "Unrelated label", "Other progress: 0/4" }
			resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
			Equal(needed, false, "unknown raw text must terminate quest association")
			state[source] = {}
		end
		state.questieLines = { "|cffffff00[12] Known Quest|r", "Wolf pelts: 1/8" }
		local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(resolved, true)
		Equal(needed, true, "Questie title normalization must remain supported")
	end)
end)

QT:RegisterTest("generic structured filtering preserves boundaries and recognized party labels", function()
	QT.nameplateQuestTextCache["Known Quest"] = true
	QT.partyMembers = { ["Friend-Realm"] = { displayName = "Friend" } }
	local raw = { lines = {
		{ type = "None", leftText = "Known Quest" },
		{ type = "None", leftText = "Wolf pelts: 8/8" },
		{ type = "None", leftText = "Unowned Other Quest" },
		{ type = "None", leftText = "Wolf teeth: 0/4" },
	} }
	Equal(QT:EvaluateTooltipQuestObjectiveLines(QT:ExtractQuestObjectiveTooltipLinesFromTooltipData(raw)), false)
	raw.lines[3].leftText = "|cff00ff00Friend-Realm|r"
	raw.lines[4].leftText = "Wolf pelts: 7/8"
	Equal(QT:EvaluateTooltipQuestObjectiveLines(QT:ExtractQuestObjectiveTooltipLinesFromTooltipData(raw)), true)
end)

local function WithSharedObjectiveSource(source, fn)
	WithFallbackSources(function(state)
		QT:GetPlayerTracker()[123] = {
			title = "Known Quest", isComplete = false, isReadyForTurnIn = false,
			objectives = { "Defeat enemies: 8/8", "Collect insignias: 0/1" },
		}
		QT:GetPlayerTracker()[124] = {
			title = "Later Quest", isComplete = false, isReadyForTurnIn = false,
			objectives = { "Collect seals: 1/1", "Other goal: 0/1" },
		}
		QT:RebuildNameplateQuestTextCache()
		Equal(QT.nameplateQuestTextCache["Defeat enemies"], true,
			"use production objective normalization, not a title-only cache")
		local function SetLines(lines)
			if source == "generic structured" then
				state.tooltipReady, state.tooltipData = true, { lines = {} }
				for index, text in ipairs(lines) do
					state.tooltipData.lines[index] = { type = "None", leftText = text }
				end
			else
				state[source] = lines
			end
		end
		fn(state, SetLines)
	end)
end

for _, provider in ipairs({ "generic structured", "hiddenLines", "questieLines" }) do
	local source = provider
	QT:RegisterTest(source .. " closed quest blocks cannot reclaim shared objective plate evidence", function()
		WithSharedObjectiveSource(source, function(state, SetLines)
			SetLines({ "Known Quest", "Defeat enemies: 8/8", "Unowned Other Quest", "Defeat enemies: 0/4" })
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], false)
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], true,
				"the readable owned objective is complete")
			QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
			state.drain()
			Undecorated(state)

			-- A shared label without counters is objective text, not permission to
			-- reopen the unowned block as if another known title had been read.
			for _, lines in ipairs({
				{ "Known Quest", "Unowned Other Quest", "Defeat enemies", "0/4" },
				{ "Known Quest", "Unowned Other Quest", "Defeat enemies: 4/4" },
			}) do
				SetLines(lines)
				QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
				state.drain()
				Undecorated(state)
				Equal(QT.nameplateQuestStateByGuid[state.guid], false)
				Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil,
					"the unowned block cannot establish completion for other spawns")
			end
			state.inaccessibleValue = setmetatable({}, { __tostring = function() error("inaccessible title stringified") end })
			SetLines({ "Known Quest", "Defeat enemies: 8/8", state.inaccessibleValue, "Defeat enemies: 0/4" })
			QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], nil,
				"an unavailable boundary leaves ownership unresolved")
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil)
		end)
	end)

	QT:RegisterTest(source .. " retains later owned party blocks and genuine titleless objectives", function()
		WithSharedObjectiveSource(source, function(state, SetLines)
			QT.partyMembers = { ["Friend-Realm"] = { displayName = "Friend" } }
			SetLines({ "Known Quest", "Defeat enemies: 8/8", "Unowned Other Quest", "Defeat enemies: 0/4",
				"Later Quest", "Collect seals: 1/1", "Friend-Realm", "Collect seals: 0/1" })
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Decorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], true)
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil)
			-- Snapshot-only quests must reopen a later block too. These are owned
			-- records, as they would be after a successful quest-log rebuild.
			QT:GetQuestSnapshotByQuestID()[124] = QT:GetPlayerTracker()[124]
			QT:GetQuestSnapshotOrder()[1] = 124
			QT:GetPlayerTracker()[124] = nil
			QT:RebuildNameplateQuestTextCache()
			QT:ClearNameplateQuestDetectionCache()
			QT:ClearNameplateResolvedQuestState()
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Decorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], true)
			SetLines({ "Defeat enemies: 0/4" })
			QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
			state.drain()
			Decorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], true,
				"a genuinely titleless source still carries independent objective evidence")
		end)
	end)

	QT:RegisterTest(source .. " leading unavailable rows cannot create shared objective plate evidence", function()
		WithSharedObjectiveSource(source, function(state, SetLines)
			local unavailableReads = 0
			state.inaccessibleValue = setmetatable({}, {
				__tostring = function() unavailableReads = unavailableReads + 1; error("unavailable text formatted") end,
			})
			SetLines({ state.inaccessibleValue, "Defeat enemies: 0/4" })
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], nil, "missing ownership must not create a positive cache")
			SetLines({ state.inaccessibleValue, "Defeat enemies: 4/4" })
			QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], nil)
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil, "partial ownership cannot prove NPC completion")

			QT.partyMembers = { ["Friend-Realm"] = { displayName = "Friend" } }
			SetLines({ state.inaccessibleValue, "Defeat enemies: 0/4", "Later Quest",
				"Collect seals: 1/1", "Friend-Realm", "Collect seals: 0/1" })
			QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
			state.drain()
			Decorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], true, "a later readable owned party block may resolve")

			-- Raw unit headers cannot be identified as quest titles. Preserve the
			-- existing readable-header and true titleless provider compatibility.
			for _, lines in ipairs({
				{ "Defeat enemies: 0/4" },
				{ "   ", "Defeat enemies: 0/4" },
				{ "Ordinary Creature", "Defeat enemies: 0/4" },
			}) do
				SetLines(lines)
				QT:HandleNameplateEvent("UNIT_QUEST_LOG_CHANGED", "player")
				state.drain()
				Decorated(state)
			end
			Equal(unavailableReads, 0, "unavailable text must never be inspected or formatted")
		end)
	end)
end

QT:RegisterTest("unavailable first structured rows retain ownership boundaries before typed objectives", function()
	WithFallbackSources(function(state)
		QT:GetPlayerTracker()[123] = { title = "Known Quest", objectives = { "Defeat enemies: 1/8" } }
		QT:RebuildNameplateQuestTextCache()
		Equal(QT.nameplateQuestTextCache["Defeat enemies"], true)
		local unavailableReads = 0
		state.inaccessibleValue = setmetatable({}, {
			__index = function() unavailableReads = unavailableReads + 1; error("unavailable row indexed") end,
			__tostring = function() unavailableReads = unavailableReads + 1; error("unavailable value formatted") end,
		})
		state.inaccessible = state.inaccessibleValue
		state.combat, state.tooltipReady = true, true
		for _, row in ipairs({
			state.inaccessible,
			{ type = state.inaccessibleValue, leftText = "Unowned Other Quest" },
			{ type = "None", args = state.inaccessibleValue },
			{ type = "None", args = { { field = "leftText", stringVal = state.inaccessibleValue } } },
		}) do
			state.tooltipData = { lines = { row, { type = "QuestObjective", leftText = "Defeat enemies: 0/4" } } }
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], nil)
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil)
		end
		state.tooltipData.lines[1] = { type = "UnitName", leftText = "Ordinary Creature" }
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		state.drain()
		Decorated(state)
		Equal(unavailableReads, 0)
		Equal(state.hiddenReads, 0)
		Equal(state.questieReads, 0)
	end)
end)

QT:RegisterTest("hidden fontstring failures and missing rows cannot establish NPC completion", function()
	WithFallbackSources(function(state)
		state.hiddenCount = 3
		state.hiddenLines = { "Known Quest", "Wolf pelts: 8/8", "Wolf teeth: 0/4" }
		state.errorRow = 3
		local resolved = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(resolved, false, "partial fontstring reads are unresolved")
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
		state.errorRow, state.hiddenLines[3] = nil, nil
		Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
		state.hiddenLines[3] = "Wolf teeth: 0/4"
		local _, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(needed, true, "readable data must recover after a partial scan")
	end)
end)

QT:RegisterTest("readable fallback spacers permit completion but inaccessible Questie rows do not", function()
	WithFallbackSources(function(state)
		state.inaccessibleValue = setmetatable({}, { __tostring = function() error("secret string conversion") end })
		for _, source in ipairs({ "hiddenLines", "questieLines" }) do
			state[source] = { "Known Quest", "Wolf pelts: 8/8", state.inaccessibleValue }
			Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
			Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
			state[source][3] = "   "
			local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
			Equal(resolved, true)
			Equal(needed, false)
			local cached, cachedNeeded = QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2")
			Equal(cached, true, "readable blank spacers must not invalidate completion")
			Equal(cachedNeeded, false)
			QT:ClearNameplateQuestDetectionCache()
			state[source] = {}
		end
	end)
end)

QT:RegisterTest("partial fallback evidence vetoes completion from another readable tooltip source", function()
	WithFallbackSources(function(state)
		state.tooltipReady = true
		state.tooltipData = { lines = {
			{ type = "QuestTitle", leftText = "Known Quest" },
			{ type = "QuestObjective", leftText = "Wolf pelts: 8/8" },
		} }
		state.inaccessibleValue = {}
		state.questieLines = { state.inaccessibleValue }
		Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
		state.questieLines = { "Known Quest", "Wolf pelts: 8/8" }
		state.hiddenCount, state.errorRow = 1, 1
		Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
		state.errorRow, state.countUnavailable = nil, true
		Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
		state.countUnavailable, state.hiddenCount = false, 0
		local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(resolved, true)
		Equal(needed, false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), true)
	end)
end)

QT:RegisterTest("real fallback adapters stay unused during combat and map restrictions", function()
	WithFallbackSources(function(state)
		state.combat, state.tooltipReady = true, true
		local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(resolved, true)
		Equal(needed, true, "readable combat structured data still resolves")
		Equal(state.hiddenReads, 0)
		Equal(state.questieReads, 0)
		state.combat, state.map = false, true
		Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
		Equal(state.hiddenReads, 0)
		Equal(state.questieReads, 0)
	end)
end)

QT:RegisterTest("unavailable generic structured text cannot join quests or prove completion", function()
	WithFallbackSources(function(state)
		state.tooltipReady = true
		state.inaccessibleValue = setmetatable({}, { __tostring = function() error("inaccessible generic text") end })
		local unreadableRows = {
			{ type = "None", leftText = state.inaccessibleValue },
			{ type = "None", args = state.inaccessibleValue },
			{ type = "None", args = { { field = "leftText", stringVal = state.inaccessibleValue } } },
		}
		for _, unavailableRow in ipairs(unreadableRows) do
			state.tooltipData = { lines = {
				{ type = "None", leftText = "Known Quest" },
				{ type = "None", leftText = "Wolf pelts: 8/8" },
				unavailableRow,
				{ type = "None", leftText = "Wolf teeth: 0/4" },
			} }
			local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
			Equal(resolved, false, "unreadable generic title must terminate the preceding quest block")
			Equal(needed, false)
			state.tooltipData.lines[4] = nil
			Equal(QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid), false)
			Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false)
		end
		state.tooltipData.lines[3] = { type = "None", leftText = "   " }
		local resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(resolved, true, "readable generic blank rows are harmless spacers")
		Equal(needed, false)
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), true)
		QT:ClearNameplateQuestDetectionCache()
		state.questieLines = { state.inaccessibleValue }
		state.tooltipData.lines[2].leftText = "Wolf pelts: 1/8"
		resolved, needed = QT:TryEvaluateQuestObjectiveViaTooltip("nameplate1", state.frame, state.guid)
		Equal(resolved, true)
		Equal(needed, true, "readable positive evidence remains valid after an incomplete earlier source")
	end)
end)

QT:RegisterTest("recycled frame hints cannot reuse another creature's cache before the live guid is readable", function()
	WithPlate(function(state)
		state.combat = false
		local previousGuid = "Creature-0-0-0-0-99999-0000000001"
		QT:StoreResolvedNameplateQuestState("nameplate2", previousGuid, true)
		state.frame.unitGUID = previousGuid
		state.guid = nil
		state.complete = true
		QT:OnNameplateAdded("nameplate1")
		Undecorated(state)
		Equal(QT.nameplateQuestGuidByUnitToken.nameplate1, nil)
		Equal(QT.nameplateQuestStateByGuid[previousGuid], true)
		state.guid = "Creature-0-0-0-0-12345-0000000002"
		state.drain()
		Undecorated(state)
		assert(state.reads > 0, "the readable current unit must be scanned")
		Equal(QT.nameplateQuestGuidByUnitToken.nameplate1, state.guid)
		Equal(QT.nameplateQuestStateByGuid[state.guid], false)
	end)
end)

QT:RegisterTest("explicit unowned quest titles cannot borrow another quest's normalized objective", function()
	WithPlate(function()
		QT:GetPlayerTracker()[123] = { title = "Known Quest", objectives = { "Defeat enemies: 1/8" } }
		QT:RebuildNameplateQuestTextCache()
		Equal(QT.nameplateQuestTextCache["Defeat enemies"], true)
		local function Evaluate(lines)
			return QT:EvaluateTooltipQuestObjectiveLines(QT:ExtractQuestObjectiveTooltipLinesFromTooltipData({ lines = lines }))
		end
		local unknown = { type = "QuestTitle", leftText = "Unowned Other Quest" }
		local unfinished = { type = "QuestObjective", leftText = "Defeat enemies: 0/4" }
		local completed = { type = "QuestObjective", leftText = "Defeat enemies: 4/4" }
		Equal(Evaluate({ unknown, unfinished }), false)
		local relevant, complete = Evaluate({ unknown, completed })
		Equal(relevant, false)
		Equal(complete, false, "an unrelated quest cannot establish NPC completion either")
		Equal(Evaluate({ unfinished }), true, "titleless objective evidence remains supported")
		Equal(Evaluate({ { leftText = "Known Quest" }, { leftText = "Defeat enemies: 0/4" } }), true)
		Equal(Evaluate({ unknown, unfinished,
			{ type = "QuestTitle", leftText = "Known Quest" }, completed,
			{ type = "QuestPlayer", leftText = "Friend-Realm" }, unfinished,
		}), true, "the following owned quest must still include party progress")
	end)
end)

for _, provider in ipairs({ "unit", "hyperlink" }) do
	local source = provider
	QT:RegisterTest("unreadable leading " .. source .. " quest titles cannot cache shared objective plate positives", function()
		WithFallbackSources(function(state)
			QT:GetPlayerTracker()[123] = { title = "Known Quest", objectives = { "Defeat enemies: 1/8" } }
			QT:RebuildNameplateQuestTextCache()
			Equal(QT.nameplateQuestTextCache["Defeat enemies"], true)
			state.inaccessibleValue = setmetatable({}, { __tostring = function() error("inaccessible title stringified") end })
			local titleType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or "QuestTitle"
			local objectiveType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or "QuestObjective"
			local title = { type = titleType, leftText = state.inaccessibleValue }
			state.combat, state.tooltipReady = source == "unit", source == "unit"
			if source == "hyperlink" then
				-- Nested structured arguments must retain the same title boundary.
				title = { type = titleType, args = { { field = "leftText", stringVal = state.inaccessibleValue } } }
				QT.API.GetTooltipDataForHyperlink = function(link)
					Equal(link, "unit:" .. state.guid)
					state.reads = state.reads + 1
					return state.tooltipData
				end
			end
			state.tooltipData = { lines = { title, { type = objectiveType, leftText = "Defeat enemies: 0/4" } } }
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], nil, "an unreadable title cannot resolve shared objective ownership")
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil)
			local reads = state.reads
			state.tooltipData.lines[1] = { type = titleType, leftText = "Unowned Other Quest" }
			QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
			state.drain()
			assert(state.reads > reads, "a repaired title must be read instead of reusing a false positive")
			Undecorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], false)
			Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil)
			state.tooltipData.lines[1].leftText = "Known Quest"
			QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
			state.drain()
			Decorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], true, "readable owned title must recover through the real resolver")
		end)
	end)
end

QT:RegisterTest("unreadable typed title completion stays unresolved while later owned party evidence remains positive", function()
	WithFallbackSources(function(state)
		QT:GetPlayerTracker()[123] = { title = "Known Quest", objectives = { "Defeat enemies: 1/8" } }
		QT:RebuildNameplateQuestTextCache()
		state.combat, state.tooltipReady = true, true
		state.inaccessibleValue = setmetatable({}, { __tostring = function() error("inaccessible title stringified") end })
		state.tooltipData = { lines = {
			{ type = "QuestTitle", leftText = state.inaccessibleValue },
			{ type = "QuestObjective", leftText = "Defeat enemies: 4/4" },
		} }
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Undecorated(state)
		Equal(QT.nameplateQuestStateByGuid[state.guid], nil, "partial data must not install a negative spawn cache")
		Equal(QT:TryGetCachedQuestObjectiveStateForGuid("Creature-0-0-0-0-12345-2"), false,
			"an unreadable title must not mark other spawns of this NPC complete")
		state.tooltipData.lines[3] = { type = "QuestTitle", leftText = "Known Quest" }
		state.tooltipData.lines[4] = { type = "QuestObjective", leftText = "Defeat enemies: 8/8" }
		state.tooltipData.lines[5] = { type = "QuestPlayer", leftText = "Friend-Realm" }
		state.tooltipData.lines[6] = { type = "QuestObjective", leftText = "Defeat enemies: 7/8" }
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		state.drain()
		Decorated(state)
		Equal(QT.nameplateQuestStateByGuid[state.guid], true)
		Equal(QT:GetNameplateStateStore().completedByNpcID[12345], nil)
	end)
end)

QT:RegisterTest("titleless providers remain positive beside an independent unreadable structured title", function()
	WithFallbackSources(function(state)
		QT:GetPlayerTracker()[123] = { title = "Known Quest", objectives = { "Defeat enemies: 1/8" } }
		QT:RebuildNameplateQuestTextCache()
		state.inaccessibleValue = setmetatable({}, { __tostring = function() error("inaccessible title stringified") end })
		state.tooltipReady = true
		for _, source in ipairs({ "structured", "questieLines", "hiddenLines" }) do
			QT:ClearNameplateQuestDetectionCache()
			QT:ClearNameplateResolvedQuestState()
			state.tooltipData = { lines = { { type = "QuestObjective", leftText = "Defeat enemies: 0/4" } } }
			if source ~= "structured" then
				state.tooltipData.lines[1] = { type = "QuestTitle", leftText = state.inaccessibleValue }
				state[source] = { "Defeat enemies: 0/4" }
			end
			QT:OnNameplateAdded("nameplate1")
			state.drain()
			Decorated(state)
			Equal(QT.nameplateQuestStateByGuid[state.guid], true, source .. " lost independent titleless objective evidence")
			if source ~= "structured" then state[source] = {} end
		end
	end)
end)

QT:RegisterTest("party roster changes retire cached relevance while unchanged rosters do not rescan", function()
	WithPlate(function(state)
		local grouped = true
		QT.API.UnitExists = function(unit) return unit == "player" or unit == "nameplate1" or (unit == "party1" and grouped) end
		QT.API.UnitFullName = function(unit) return unit == "party1" and "Friend" or "MyPlayer", "Realm" end
		QT.API.GetRealmName = function() return "Realm" end
		QT.API.UnitClass = function() return "Mage", "MAGE" end
		QT.API.IsInRaid = function() return false end
		local title = { type = "QuestTitle", leftText = "Wolf Hunt" }
		local complete = { type = "QuestObjective", leftText = "Wolf pelts: 8/8" }
		local player = { type = "QuestPlayer", leftText = "Friend-Realm" }
		local unfinished = { type = "QuestObjective", leftText = "Wolf pelts: 7/8" }
		state.tooltipData = { lines = { title, complete, player, unfinished } }
		QT:GROUP_ROSTER_UPDATE()
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		grouped = false
		state.tooltipData = { lines = { title, complete } }
		QT:GROUP_ROSTER_UPDATE()
		state.drain()
		Undecorated(state)
		grouped = true
		state.tooltipData = { lines = { title, complete, player, unfinished } }
		QT:GROUP_ROSTER_UPDATE()
		state.drain()
		Decorated(state)
		local reads = state.reads
		QT:GROUP_ROSTER_UPDATE()
		state.drain()
		Equal(state.reads, reads, "unchanged roster must not invalidate positive relevance")
	end)
end)

QT:RegisterTest("deferred disabled cleanup cannot hide current quest visuals after reenable", function()
	WithPlate(function(state)
		local staleIcon = {
			IsForbidden = function() return true end,
			Hide = function() error("forbidden old icon must never be touched") end,
		}
		local staleUnitFrame = {}
		QT.nameplateIconByUnitFrame[staleUnitFrame] = staleIcon
		QT.isEnabled = false
		QT:DisableNameplateAugmentation()
		Equal(QT.pendingNameplateVisualCleanup, true)
		QT.isEnabled = true
		QT:EnableNameplateAugmentation()
		QT.nameplateQuestTextCache["Wolf Hunt"] = true
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		QT:HandleNameplateEvent("UPDATE_MOUSEOVER_UNIT")
		Decorated(state)
		state.drain()
		Decorated(state)
	end)
end)

QT:RegisterTest("reused icons and tints leave old cleanup while quarantined handles remain guarded", function()
	WithPlate(function(state)
		local forbidden, oldHides = true, 0
		local staleIcon = {
			IsForbidden = function() return forbidden end,
			Hide = function()
				assert(not forbidden, "quarantined icon must not be hidden")
				oldHides = oldHides + 1
			end,
		}
		local staleUnitFrame = {}
		QT.nameplateIconByUnitFrame[staleUnitFrame] = staleIcon
		QT:OnNameplateAdded("nameplate1")
		state.drain()
		Decorated(state)
		state.protected, QT.isEnabled = true, false
		QT:DisableNameplateAugmentation()
		Equal(QT.pendingNameplateVisualCleanup, true)
		local pending = QT:GetNameplateStateStore().pendingVisualCleanupByFrame
		assert(pending[state.icon] and pending[state.fill] and pending[state.highlight], "restricted handles must remain pending")
		QT.isEnabled, state.protected = true, false
		QT:EnableNameplateAugmentation()
		-- A deferred presenter or option refresh can reuse handles before the
		-- next cleanup event. That new presentation supersedes their old teardown.
		QT:ApplyResolvedQuestStateToNameplate(state.plate, "nameplate1", state.frame, true, false, state.guid)
		Decorated(state)
		Equal(pending[state.icon], nil)
		Equal(pending[state.fill], nil)
		Equal(pending[state.highlight], nil)
		Equal(QT:RetryPendingNameplateVisualCleanup(), false)
		Equal(oldHides, 0)
		Decorated(state)
		forbidden = false
		Equal(QT:RetryPendingNameplateVisualCleanup(), true)
		Equal(oldHides, 1)
		Decorated(state)
	end)
end)
