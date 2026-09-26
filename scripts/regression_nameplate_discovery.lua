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
		reads = 0, callbacks = {},
	}
	local function Region()
		local region = { shown = false }
		function region:IsForbidden() return false end
		function region:IsProtected() return state.protected == true end
		function region:IsShown() return self.shown end
		function region:Show()
			assert(not (state.protected and state.combat), "protected visual shown in combat")
			self.shown = true
		end
		function region:Hide()
			assert(not (state.protected and state.combat), "protected visual hidden in combat")
			self.shown = false
		end
		for _, method in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetAllPoints", "SetVertexColor", "SetColorTexture", "SetAlpha" }) do
			region[method] = function()
				assert(not (state.protected and state.combat), "protected visual restyled in combat")
			end
		end
		return region
	end
	local liveFill, healthBar = Region(), Region()
	function liveFill:IsShown() return state.fillReady end
	function healthBar:IsShown() return state.shown end
	function healthBar:GetStatusBarTexture() return liveFill end
	function healthBar:GetAlpha() return 1 end
	local frame = { unit = "nameplate1", healthBar = healthBar }
	state.frame = frame
	function frame:IsProtected() return state.protected == true end
	local plate = { UnitFrame = frame, IsShown = function() return state.shown end }
	local icon, fill, highlight = Region(), Region(), Region()
	state.icon, state.fill, state.highlight = icon, fill, highlight
	state.step = function()
		local callback = table.remove(state.callbacks, 1)
		if callback then callback() end
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
	local replacements = {
		CanAccessTable = function(self, value)
			return value ~= state.inaccessible and canAccessTable(self, value)
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
			Delay = function(_, callback) state.callbacks[#state.callbacks + 1] = callback end,
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
	Equal(state.icon.shown, true, "quest icon missing")
	Equal(state.fill.shown, true, "quest tint missing")
	Equal(state.highlight.shown, true, "quest highlight missing")
end

local function Undecorated(state)
	Equal(state.icon.shown, false, "completed mob regained its quest icon")
	Equal(state.fill.shown, false, "completed mob regained its quest tint")
	Equal(state.highlight.shown, false, "completed mob regained its quest highlight")
end

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
		QT:ClearNameplateQuestDetectionCache()
		QT:ClearNameplateResolvedQuestState()
		state.complete = false
		QT:RefreshVisibleNameplates("new quest")
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
		QT:FlushDeferredWork("discovery regression")
		state.drain()
		Equal(state.reads, 0)
		state.restriction = nil
		QT:FlushDeferredWork("discovery regression")
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
