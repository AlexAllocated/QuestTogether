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
	QT.nameplateIconByUnitFrame[{}] = icon
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
