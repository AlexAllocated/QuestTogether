-- Regression cases loaded after Tests.lua. Only QuestTogether-owned
-- methods/state are replaced; no client globals, Blizzard tables, or hooks.
local QT = _G.QuestTogether
local function Equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function Patch(replacements, fn)
	local original = {}
	for key, value in pairs(replacements) do
		original[key] = QT[key]
		QT[key] = value
	end
	local ok, err = pcall(fn)
	for key in pairs(replacements) do
		QT[key] = original[key]
	end
	assert(ok, err)
end

local function WithTapFixture(fn)
	local state = { denied = false, restricted = true, protected = false, forbidden = false, tapReads = 0 }
	local guid = "Creature-0-0-0-0-11111-0000000000"
	local function Visual()
		return {
			shown = true,
			IsProtected = function() return state.protected end,
			Show = function(self) self.shown = true end,
			Hide = function(self) self.shown = false end,
		}
	end
	local unitFrame = { unit = "nameplate1", healthBar = {} }
	local plate = {
		UnitFrame = unitFrame,
		IsShown = function() return true end,
		IsForbidden = function() return state.forbidden end,
	}
	local icon, fill, highlight = Visual(), Visual(), Visual()
	icon.Icon = Visual()
	function icon.Icon:SetTexture(value)
		assert(not (state.restricted and state.protected), "protected artwork must remain deferred")
		self.texture = value
	end
	function icon.Icon:SetTexCoord() end
	state.icon, state.fill, state.highlight = icon, fill, highlight
	state.drain = function()
		local count = 0
		while #state.callbacks > 0 do
			count = count + 1
			assert(count < 20, "tap refresh must not repeatedly reschedule itself")
			table.remove(state.callbacks, 1)()
		end
	end
	state.callbacks = {}
	QT.isEnabled = true
	QT.db.profile.nameplateQuestIconEnabled = true
	QT.db.profile.nameplateQuestHealthColorEnabled = true
	QT.nameplateIconByUnitFrame[unitFrame] = icon
	QT.nameplateHealthOverlayByUnitFrame[unitFrame] = { FillTexture = fill, Highlight = highlight }
	QT:StoreResolvedNameplateQuestState("nameplate1", guid, true)
	Patch({
		API = {
			GetNamePlates = function() return { plate } end,
			GetNamePlateForUnit = function(token)
				Equal(token, "nameplate1")
				return plate
			end,
			UnitGUID = function() return guid end,
			UnitExists = function() return true end,
			UnitIsPlayer = function() return false end,
			Delay = function(_, callback) state.callbacks[#state.callbacks + 1] = callback end,
		},
		IsRuntimeRestricted = function() return state.restricted end,
		IsRuntimeRestrictionTypeActive = function() return false end,
		IsNameplateUnitTapDenied = function(_, token)
			Equal(token, "nameplate1")
			state.tapReads = state.tapReads + 1
			return state.denied
		end,
		TryEvaluateQuestObjectiveViaTooltip = function() error("tap changes must reuse quest detection") end,
		ApplyNameplateQuestIconStyle = function()
			Equal(state.restricted and state.protected, false, "protected icon layout must remain deferred")
		end,
		ApplyQuestTintToNameplate = function()
			Equal(state.restricted and state.protected, false, "protected tint layout must remain deferred")
			fill:Show()
			highlight:Show()
			return true
		end,
	}, function()
		fn(state)
		Equal(QT.nameplateQuestStateByGuid[guid], true, "tap changes must preserve quest relevance")
	end)
end

QT:RegisterTest("tap denial clears the quest icon and both tint textures during combat", function()
	WithTapFixture(function(state)
		for _, event in ipairs({
			"UNIT_FACTION", "UNIT_FLAGS", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION",
			"UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
		}) do
			state.icon.shown, state.fill.shown, state.highlight.shown = true, true, true
			state.denied = true
			QT:HandleNameplateEvent(event, "nameplate1")
			Equal(state.icon.shown, false, event .. " must immediately hide the icon")
			Equal(state.fill.shown, false, event .. " must immediately hide the fill")
			Equal(state.highlight.shown, false, event .. " must immediately hide the highlight")
			state.drain()
		end
		state.restricted = false
		QT:FlushDeferredWork("tap regression")
		state.drain()
		Equal(state.icon.shown, false, "deferred refresh must not restore a denied tap")
		Equal(state.fill.shown, false)
		Equal(state.highlight.shown, false)
	end)
end)

QT:RegisterTest("eligible taps retain decorations and regain them when tap denial clears", function()
	WithTapFixture(function(state)
		-- Untapped, player-owned and shared group taps all report denial=false.
		QT:HandleNameplateEvent("UNIT_FACTION", "nameplate1")
		state.drain()
		Equal(state.icon.shown, true)
		Equal(state.fill.shown, true)
		Equal(state.highlight.shown, true)
		state.denied = true
		QT:HandleNameplateEvent("UNIT_FACTION", "nameplate1")
		Equal(state.icon.shown, false)
		state.denied, state.restricted = false, false
		QT:HandleNameplateEvent("UNIT_FLAGS", "nameplate1")
		state.drain()
		Equal(state.icon.shown, true)
		Equal(state.fill.shown, true)
		Equal(state.highlight.shown, true)
	end)
end)

QT:RegisterTest("tap cleanup respects protected visuals and retries after combat", function()
	WithTapFixture(function(state)
		state.denied, state.protected = true, true
		QT:HandleNameplateEvent("UNIT_FACTION", "nameplate1")
		state.drain()
		Equal(state.icon.shown, true)
		Equal(state.fill.shown, true)
		Equal(state.highlight.shown, true)
		state.restricted = false
		QT:HandleNameplateEvent("PLAYER_REGEN_ENABLED")
		QT:FlushDeferredWork("tap regression")
		state.drain()
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
		Equal(state.highlight.shown, false)
	end)
end)

QT:RegisterTest("tap cleanup leaves forbidden plates untouched", function()
	WithTapFixture(function(state)
		state.denied, state.forbidden = true, true
		QT:HandleNameplateEvent("UNIT_FACTION", "nameplate1")
		state.restricted = false
		QT:FlushDeferredWork("tap regression")
		state.drain()
		Equal(state.icon.shown, true)
		Equal(state.fill.shown, true)
		Equal(state.highlight.shown, true)
	end)
end)

QT:RegisterTest("tap events ignore units that are not nameplate tokens", function()
	WithTapFixture(function(state)
		for _, event in ipairs({ "UNIT_FACTION", "UNIT_FLAGS", "UNIT_HEALTH" }) do
			QT:HandleNameplateEvent(event, "target")
			QT:HandleNameplateEvent(event, "player")
			QT:HandleNameplateEvent(event, {})
			QT:HandleNameplateEvent(event)
		end
		Equal(state.tapReads, 0)
		Equal(#state.callbacks, 0)
	end)
end)

QT:RegisterTest("nameplate augmentation subscribes to tap ownership changes", function()
	local registered = {}
	Patch({
		nameplateEventFrame = { RegisterEvent = function(_, event) registered[event] = true end },
		nameplateRegisteredEvents = {},
		TryInstallNameplateHooks = function() end,
		ScheduleDeferredNameplateQuestStateRefresh = function() end,
		SchedulePlaterStartupNameplateRefreshes = function() end,
	}, function()
		QT:EnableNameplateAugmentation()
		Equal(registered.UNIT_FACTION, true)
		Equal(registered.UNIT_FLAGS, true)
		Equal(registered.NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED, true)
		Equal(registered.PLAYER_TARGET_CHANGED, true)
		Equal(registered.UPDATE_MOUSEOVER_UNIT, true)
	end)
end)

QT:RegisterTest("deferred tap refresh cannot decorate a removed nameplate", function()
	WithTapFixture(function(state)
		state.denied = true
		QT:HandleNameplateEvent("UNIT_FACTION", "nameplate1")
		state.drain()
		QT:OnNameplateRemoved("nameplate1")
		state.denied, state.restricted = false, false
		QT:FlushDeferredWork("tap regression")
		state.drain()
		Equal(state.icon.shown, false)
		Equal(state.fill.shown, false)
		Equal(state.highlight.shown, false)
	end)
end)

local function Bubble(playing)
	local bubble = { hidden = false, stops = 0 }
	bubble.SetAlpha = function(self, alpha)
		self.alpha = alpha
	end
	bubble.Hide = function(self)
		self.hidden = true
	end
	bubble.animationGroup = {
		IsPlaying = function()
			return playing
		end,
		Stop = function()
			playing = false
			bubble.stops = bubble.stops + 1
			QT:CompleteAnnouncementBubblePlayback(bubble)
		end,
	}
	return bubble
end
local function SeedBubble(unitToken, playing)
	local frame = {}
	local host = {
		UnitFrame = frame,
		IsShown = function()
			return true
		end,
	}
	local bubble = Bubble(playing)
	QT.nameplateBubbleByUnitFrame[frame] = bubble
	QT.nameplateBubbleStateByFrame[bubble] = {
		unitToken = unitToken,
		text = "80% Locations Photographed",
		eventType = "QUEST_PROGRESS",
		unitGUID = unitToken ~= "player" and "Player-1-OLD" or nil,
	}
	QT.isEnabled = true
	QT.db.profile.showChatBubbles = true
	QT.db.profile.hideMyOwnChatBubbles = false
	if unitToken == "player" then
		QT.announcementBubbleScreenHostFrame = host
	end
	return bubble, host, frame
end

QT:RegisterTest("audit hide-own stops an active personal bubble during restrictions", function()
	local bubble = SeedBubble("player", true)
	QT.db.profile.hideMyOwnChatBubbles = true
	Patch({
		IsRuntimeRestricted = function()
			return true
		end,
	}, function()
		QT:RefreshActiveAnnouncementBubbles()
	end)
	Equal(bubble.hidden, true)
	Equal(bubble.stops, 1)
	Equal(QT.nameplateBubbleStateByFrame[bubble], nil)
end)

QT:RegisterTest("audit stopped personal playback cannot be replayed by a refresh", function()
	local bubble, host = SeedBubble("player", false)
	local shows = 0
	Patch({
		GetAnnouncementBubbleHostFrameForUnit = function()
			return host
		end,
		ShowAnnouncementBubbleOnNameplate = function()
			shows = shows + 1
		end,
	}, function()
		QT:RefreshActiveAnnouncementBubbles()
	end)
	Equal(shows, 0)
	Equal(bubble.hidden, true)
	Equal(QT.nameplateBubbleStateByFrame[bubble], nil)
end)

QT:RegisterTest("audit recycled nameplate identity clears active playback", function()
	local bubble, host = SeedBubble("nameplate1", true)
	Patch({
		IsAnnouncementBubbleAugmentationBlockedInCurrentContext = function()
			return false
		end,
		GetAnnouncementBubbleHostFrameForUnit = function()
			return host
		end,
		GetNameplateUnitGuid = function()
			return "Player-1-NEW"
		end,
	}, function()
		QT:RefreshActiveAnnouncementBubbles()
	end)
	Equal(bubble.hidden, true)
	Equal(QT.nameplateBubbleStateByFrame[bubble], nil)
end)

QT:RegisterTest("audit active nearby bubble honors a changed sender scope", function()
	local bubble = SeedBubble("nameplate1", true)
	QT.nameplateBubbleStateByFrame[bubble].senderName = "Friend-Realm"
	QT.db.profile.showProgressFor = "party_only"
	Patch({
		IsAnnouncementBubbleAugmentationBlockedInCurrentContext = function()
			return false
		end,
		IsGroupedSender = function()
			return false
		end,
	}, function()
		QT:RefreshActiveAnnouncementBubbles()
	end)
	Equal(bubble.hidden, true)
end)

QT:RegisterTest("audit removed plate clears playback even after public lookup disappears", function()
	local bubble = SeedBubble("nameplate1", true)
	QT.nameplateRefreshGenerationByUnitToken.nameplate1 = 3
	Patch({
		API = {
			GetNamePlateForUnit = function()
				return nil
			end,
		},
		IsAnnouncementBubbleAugmentationBlockedInCurrentContext = function()
			return false
		end,
	}, function()
		QT:OnNameplateRemoved("nameplate1")
	end)
	Equal(bubble.hidden, true)
	Equal(QT.nameplateRefreshGenerationByUnitToken.nameplate1, 4)
end)

QT:RegisterTest("audit old scheduled plate update cannot match a reused unit generation", function()
	QT.isEnabled = true
	local callbacks, refreshed = {}, 0
	local frame = {}
	Patch({
		API = {
			Delay = function(_, fn)
				callbacks[#callbacks + 1] = fn
			end,
			GetNamePlateForUnit = function()
				return nil
			end,
		},
		GetAccessibleNameplateFrameForUnit = function()
			return frame
		end,
		RefreshNameplateIcon = function()
			refreshed = refreshed + 1
		end,
	}, function()
		QT:ScheduleNameplateRefresh("nameplate1")
		QT:OnNameplateRemoved("nameplate1")
		QT:ScheduleNameplateRefresh("nameplate1")
		callbacks[1]()
		Equal(refreshed, 0)
		callbacks[2]()
		Equal(refreshed, 1)
	end)
end)

QT:RegisterTest("audit quest icon cleanup does not cancel a player's announcement", function()
	local bubble, host = SeedBubble("nameplate1", true)
	QT:HideNameplateIcon(host)
	Equal(bubble.stops, 0)
	assert(QT.nameplateBubbleStateByFrame[bubble] ~= nil)
end)

QT:RegisterTest("audit live guid takes precedence over stale recycled frame hints", function()
	Patch({
		GetNameplateUnitGuid = function()
			return "Creature-0-NEW"
		end,
	}, function()
		Equal(QT:GetNameplateTooltipScanGuid("nameplate1", { namePlateUnitGUID = "Creature-0-OLD" }), "Creature-0-NEW")
	end)
end)

QT:RegisterTest("audit forbidden frame guid fallback is never inspected", function()
	local forbidden = setmetatable({
		IsForbidden = function()
			return true
		end,
	}, {
		__index = function()
			error("forbidden frame member inspected")
		end,
	})
	Patch({
		GetNameplateUnitGuid = function()
			return nil
		end,
	}, function()
		Equal(QT:GetNameplateTooltipScanGuid("nameplate1", forbidden), nil)
	end)
end)

QT:RegisterTest("audit inaccessible tooltip containers are not traversed", function()
	local inaccessible = setmetatable({}, {
		__index = function()
			error("inaccessible table read")
		end,
	})
	local canAccess = QT.CanAccessTable
	Patch({
		CanAccessTable = function(self, value)
			return value ~= inaccessible and canAccess(self, value)
		end,
	}, function()
		Equal(QT:ExtractQuestObjectiveTooltipLinesFromTooltipData(inaccessible), nil)
		Equal(QT:ExtractQuestObjectiveTooltipLinesFromTooltipData({ lines = inaccessible }), nil)
		Equal(QT:SanitizeTooltipLineForQuestDetection(inaccessible), nil)
		Equal(QT:EvaluateTooltipQuestObjectiveLines(inaccessible), false)
		Equal(QT:TooltipLineHasUnfinishedObjectiveEvidence({ args = inaccessible }), false)
	end)
end)

QT:RegisterTest("audit protected icon is not shown or restyled while restricted", function()
	local icon = {
		IsProtected = function()
			return true
		end,
		Show = function()
			error("protected icon shown")
		end,
		Hide = function()
			error("protected icon hidden")
		end,
		ClearAllPoints = function()
			error("protected icon relaid out")
		end,
	}
	local unit = {}
	QT.nameplateIconByUnitFrame[unit] = icon
	Patch({
		IsRuntimeRestricted = function()
			return true
		end,
		ShouldShowQuestNameplateIconForResolvedState = function()
			return true
		end,
		RefreshNameplateHealthTint = function() end,
		GetNameplateTooltipScanGuid = function()
			return nil
		end,
	}, function()
		QT:ApplyResolvedQuestStateToNameplate({}, "nameplate1", unit, true, false)
	end)
end)

QT:RegisterTest("audit protected health overlay does not mutate during restrictions", function()
	local texture = {
		IsProtected = function()
			return true
		end,
		Hide = function()
			error("protected texture hidden")
		end,
	}
	local healthBar = {
		IsProtected = function()
			return true
		end,
		CreateTexture = function()
			error("protected texture created")
		end,
	}
	local unit = { healthBar = healthBar }
	QT.nameplateHealthOverlayByUnitFrame[unit] = { FillTexture = texture, Highlight = texture }
	Patch({
		IsRuntimeRestricted = function()
			return true
		end,
	}, function()
		Equal(QT:ApplyQuestTintToNameplate(unit), false)
		Equal(QT:CreateNameplateHealthOverlayTexture(healthBar), nil)
		QT:RestoreNameplateHealthColor(unit)
	end)
end)

QT:RegisterTest("audit disabled cleanup hides cached offscreen visuals after restrictions end", function()
	local restricted, hidden = true, 0
	local icon = {
		IsProtected = function()
			return true
		end,
		Hide = function()
			hidden = hidden + 1
		end,
	}
	local unitFrame = {}
	QT.nameplateIconByUnitFrame[unitFrame] = icon
	local originalPending = QT.pendingNameplateVisualCleanup
	Patch({
		IsRuntimeRestricted = function()
			return restricted
		end,
	}, function()
		Equal(QT:HideAllNameplateVisuals(), false)
		Equal(hidden, 0)
		restricted = false
		QT.isEnabled = false
		QT.pendingNameplateVisualCleanup = true
		QT:HandleNameplateEvent("PLAYER_REGEN_ENABLED")
		Equal(hidden, 1)
		Equal(QT.pendingNameplateVisualCleanup, false)
	end)
	QT.pendingNameplateVisualCleanup = originalPending
end)

QT:RegisterTest("audit startup timers from a previous enable do not refresh current plates", function()
	local callbacks, questRefreshes, fullRefreshes = {}, 0, 0
	QT.isEnabled = true
	Patch({
		API = {
			Delay = function(_, fn)
				callbacks[#callbacks + 1] = fn
			end,
		},
		ScheduleDeferredNameplateQuestStateRefresh = function()
			questRefreshes = questRefreshes + 1
		end,
		FullRefreshVisibleNameplates = function()
			fullRefreshes = fullRefreshes + 1
		end,
	}, function()
		QT:SchedulePlaterStartupNameplateRefreshes()
		QT:ResetNameplateStateStore()
		QT:SchedulePlaterStartupNameplateRefreshes()
		callbacks[1]()
		callbacks[2]()
		Equal(questRefreshes, 0)
		Equal(fullRefreshes, 0)
		callbacks[3]()
		callbacks[4]()
		Equal(questRefreshes, 1)
		Equal(fullRefreshes, 1)
	end)
end)

local function WithRecycledBubble(fn)
	local state = { restricted = false, mutations = 0, reparents = 0 }
	local function Region(parent)
		local region = { parent = parent, shown = true }
		function region:IsForbidden() return self.forbidden == true end
		function region:IsProtected()
			return self.protected == true or (self.parent and self.parent:IsProtected()) or false
		end
		function region:IsShown() return self.shown end
		function region:IsVisible()
			return self.shown and (not self.parent or self.parent:IsVisible())
		end
		function region:GetParent() return self.parent end
		local function Mutate(self)
			assert(not self:IsForbidden(), "forbidden bubble mutated")
			assert(not (self:IsProtected() and state.restricted), "protected bubble mutated during restrictions")
			state.mutations = state.mutations + 1
		end
		function region:SetParent(newParent)
			Mutate(self)
			state.reparents = state.reparents + 1
			if state.rejectParent then error("client rejected reparent") end
			self.parent = newParent
		end
		function region:Show() Mutate(self); self.shown = true end
		function region:Hide() Mutate(self); self.shown = false end
		function region:GetFrameStrata() return "LOW" end
		function region:GetFrameLevel() return 1 end
		for _, name in ipairs({ "SetFrameStrata", "SetFrameLevel", "SetAlpha", "ClearAllPoints", "SetPoint", "SetSize", "SetClampRectInsets", "SetWidth", "SetText", "SetFont", "SetAtlas", "SetTexCoord" }) do
			region[name] = Mutate
		end
		return region
	end
	local oldBase, newBase = Region(), Region()
	oldBase.shown = false
	local unitFrame = Region(newBase)
	unitFrame.unit = "nameplate2"
	newBase.UnitFrame = unitFrame
	local bubble = Region(oldBase)
	bubble.String = Region(bubble)
	function bubble.String:GetFont() return "font", 14, "" end
	function bubble.String:GetUnboundedStringWidth() return 100 end
	function bubble.String:GetStringHeight() return 14 end
	bubble.animationGroup = { IsPlaying = function() return false end, Play = function() end }
	state.oldBase, state.newBase, state.unitFrame, state.bubble = oldBase, newBase, unitFrame, bubble
	QT.nameplateBubbleByUnitFrame[unitFrame] = bubble
	QT.isEnabled = true
	QT.db.profile.showChatBubbles = true
	Patch({
		API = { UnitGUID = function() return "Player-1-NEW" end },
		IsRuntimeRestricted = function() return state.restricted end,
	}, function() fn(state) end)
end

QT:RegisterTest("recycled unit frame reparents its cached bubble to the current visible base", function()
	WithRecycledBubble(function(state)
		Equal(state.bubble:IsShown(), true)
		Equal(state.bubble:IsVisible(), false, "shown is not sufficient under the old hidden base")
		Equal(QT:ShowAnnouncementBubbleOnNameplate(state.newBase, "New sender quest progress"), true)
		Equal(state.bubble:GetParent(), state.newBase)
		Equal(state.bubble:IsVisible(), true)
		Equal(state.reparents, 1)
		Equal(QT:ShowAnnouncementBubbleOnNameplate(state.newBase, "Another update"), true)
		Equal(state.reparents, 1, "unchanged bubble hosts should not be reparented")
	end)
end)

QT:RegisterTest("bubble reuse never reparents forbidden bubbles or during restricted playback", function()
	WithRecycledBubble(function(state)
		state.bubble.forbidden = true
		Equal(QT:ShowAnnouncementBubbleOnNameplate(state.newBase, "Forbidden"), false)
		Equal(state.mutations, 0)
		state.bubble.forbidden, state.restricted, state.oldBase.protected = false, true, true
		Equal(QT:ShowAnnouncementBubbleOnNameplate(state.newBase, "Restricted"), false)
		Equal(state.mutations, 0)
		Equal(state.reparents, 0)
	end)
end)

QT:RegisterTest("bubble reuse does not report success when the client rejects the new parent", function()
	WithRecycledBubble(function(state)
		state.rejectParent = true
		Equal(QT:ShowAnnouncementBubbleOnNameplate(state.newBase, "Rejected parent"), false)
		Equal(state.bubble:GetParent(), state.oldBase)
		Equal(state.bubble:IsVisible(), false)
		Equal(QT.nameplateBubbleStateByFrame[state.bubble], nil)
	end)
end)

QT:RegisterTest("new bubble playback supersedes protected cleanup from the disabled lifetime", function()
	WithRecycledBubble(function(state)
		state.restricted, state.oldBase.protected = true, true
		QT.isEnabled = false
		Equal(QT:HideAllNameplateVisuals(), false)
		Equal(state.mutations, 0, "restricted old playback must remain untouched")
		QT:ResetNameplateStateStore()
		Equal(QT:GetNameplateStateStore().pendingVisualCleanupByFrame[state.bubble], "bubble")
		state.restricted, state.oldBase.protected, QT.isEnabled = false, false, true
		Equal(QT:ShowAnnouncementBubbleOnNameplate(state.newBase, "New lifetime announcement"), true)
		Equal(QT.pendingNameplateVisualCleanup, false)
		Equal(QT:RetryPendingNameplateVisualCleanup(), true)
		Equal(state.bubble:IsVisible(), true)
		Equal(QT.nameplateBubbleStateByFrame[state.bubble].text, "New lifetime announcement")
	end)
end)
