local QT = _G.QuestTogether
local function Fixture()
	local a = setmetatable({ isEnabled = true, db = { profile = {} }, options = {}, runtimeStateStore = {} }, { __index = QT })
	local clock = QT:CreateTestClock(0)
	a.API = {
		Delay = function(delay, run)
			clock:After(delay, run)
		end,
	}
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	function a:IsMapTooltipSensitiveStateActive()
		return false
	end
	function a:GetOption(key)
		return self.options[key]
	end
	function a:CreateOwnedUICleanupFrame()
		return QT:CreateTestUIRegion(self)
	end
	function a:CreateRuntimeUIWorkFrame()
		-- This parentless observer has no protected geometry or feature UI.
		return QT:CreateTestUIRegion({})
	end
	function a:CreateLocationPinFrame(_, _, parent)
		return QT:CreateTestUIRegion(self, parent)
	end
	function a:CreateOwnedWindowFrame(_, _, parent)
		return QT:CreateTestUIRegion(self, parent)
	end
	local root = QT:CreateTestUIRegion(a)
	root:SetSize(1920, 1080)
	function a:GetOwnedUIParent()
		return root
	end
	function a:GetLocationPinTooltipParent()
		return root
	end
	return a, clock, root
end

QT:RegisterTest("runtime timing modes keep next-frame discovery separate and bound refresh deadlines", function()
	local a, clock = Fixture()
	local calls = {}
	a:ScheduleRuntimeWork("example", "inline", function()
		calls[#calls + 1] = "inline"
	end, { mode = "immediate" })
	a:ScheduleRuntimeWork("example", "next", function()
		calls[#calls + 1] = "next"
	end, { mode = "nextFrame" })
	assert(#calls == 1 and calls[1] == "inline")
	a:FlushDeferredWork("restriction release")
	assert(#calls == 1, "a flush cannot make the next frame due")
	clock:Advance(0)
	assert(#calls == 2 and calls[2] == "next")
	local count = 0
	local function Refresh()
		count = count + 1
	end
	a:ScheduleRuntimeWork("example", "bounded", Refresh, { mode = "bounded", delay = 1 })
	clock:Advance(0.75)
	a:ScheduleRuntimeWork("example", "bounded", Refresh, { mode = "bounded", delay = 1 })
	clock:Advance(0.25)
	assert(count == 1, "new events must not postpone the original deadline")
end)

QT:RegisterTest("runtime owner cancellation retires timers while cleanup has its own enablement lifetime", function()
	local a, clock = Fixture()
	local calls = 0
	local owner = a:NewRuntimeWorkOwner()
	a:ScheduleRuntimeWork("example", "owned", function()
		calls = calls + 1
	end, { owner = owner, mode = "nextFrame" })
	a:CancelRuntimeWorkOwner(owner)
	clock:Advance(0)
	assert(calls == 0 and not next(a:GetDeferredWorkStateStore().entries))
	assert(not a:ScheduleRuntimeWork("example", "owned", function() end, { owner = owner }))
	a.isEnabled, a.blocked = false, true
	a:ScheduleRuntimeWork("example", "cleanup", function()
		calls = calls + 1
	end, { lifetime = "cleanup", mode = "nextFrame" })
	clock:Advance(0)
	assert(calls == 0)
	a.blocked = false
	a:FlushDeferredWork("restriction ended while disabled")
	assert(calls == 1)
	a.isEnabled = true
	a:ScheduleRuntimeWork("example", "reset", function()
		error("retired runtime executed")
	end, { mode = "nextFrame" })
	a:ResetRuntimeWorkStateStore()
	clock:Advance(0)
end)

QT:RegisterTest("owned UI teardown survives disable and never hides a reused region", function()
	local a, _, root = Fixture()
	local child = QT:CreateTestUIRegion(a, root)
	root.forbidden, a.isEnabled = true, false
	assert(not a:HideOwnedUI(child))
	local cleanup = a:GetOwnedUICleanupState()
	assert(cleanup.pending[child])
	root.forbidden = false
	cleanup.driver.scripts.OnUpdate(cleanup.driver, 0.3)
	assert(not child:IsShown() and not next(cleanup.pending))
	a:CallOwnedUI(child, "Show")
	root.protected = true
	a:HideOwnedUI(child)
	local staleTick = cleanup.driver.scripts.OnUpdate
	root.protected = false
	a:CallOwnedUI(child, "Show")
	staleTick(cleanup.driver, 0.3)
	assert(child:IsShown() and not next(cleanup.pending))
	assert((a.invalidCalls or 0) == 0)
end)

QT:RegisterTest("managed windows distinguish inherited hiding explicit dismissal and request retirement", function()
	local a, _, root = Fixture()
	local frame = QT:CreateTestUIRegion(a, root)
	local dismissed, suspended, nativeHide = 0, 0, 0
	a:ConfigureWindowController(frame, {
		dismiss = function()
			dismissed = dismissed + 1
		end,
		suspend = function()
			suspended = suspended + 1
		end,
	})
	-- HookScript survives a later feature SetScript, as it does in the client.
	frame:SetScript("OnHide", function()
		nativeHide = nativeHide + 1
	end)
	root:Hide()
	assert(frame:IsShown() and not frame:IsVisible() and dismissed == 0 and suspended == 1 and nativeHide == 1)
	a:DismissManagedWindow(frame)
	assert(not frame:IsShown() and dismissed == 1)
	a:DismissManagedWindow(frame)
	assert(dismissed == 1)
	root:Show()
	frame:Show()
	frame:Hide()
	assert(dismissed == 2)
	local declined = 0
	a:ConfigureRequestPrompt(frame, function()
		declined = declined + 1
	end)
	frame.request = {}
	frame:Show()
	root:Hide()
	a:DismissManagedWindow(frame, "escape")
	assert(declined == 1)
	root:Show()
	frame:Show()
	frame.request = nil
	a:HideOwnedUI(frame)
	assert(declined == 1, "retiring a request must not acknowledge a different request")
end)

QT:RegisterTest("map overlay pools share surface reparenting and cancel stale marker cleanup", function()
	local a, _, root = Fixture()
	local state = { surfaces = {} }
	local geometry = { parent = root }
	local surface = a:AcquireMapOverlaySurface(state, "map", geometry, 50)
	local creations = 0
	local function Create(host)
		creations = creations + 1
		return { frame = a:CreateLocationPinFrame("Button", nil, host.frame) }
	end
	local pin = a:AcquireMapOverlayPin(surface, 1, Create)
	assert(a:AcquireMapOverlayPin(surface, 1, Create) == pin and creations == 1)
	root.protected = true
	a:ReleaseMapOverlayPins(surface, 0)
	assert(a:GetOwnedUICleanupState().pending[pin.frame])
	root.protected = false
	a:CallOwnedUI(pin.frame, "Show")
	a:FlushOwnedUICleanup()
	assert(pin.frame:IsShown())
	local newRoot = QT:CreateTestUIRegion(a)
	local same = a:AcquireMapOverlaySurface(state, "map", { parent = newRoot }, 55)
	assert(
		same == surface
			and surface.frame:GetParent() == newRoot
			and surface.frame:GetFrameLevel() == newRoot:GetFrameLevel() + 55
	)
end)

QT:RegisterTest("player tooltip presenter renders a prepared model without querying domain data", function()
	local a, _, root = Fixture()
	for _, method in ipairs({
		"GetPlayerDetailsTooltipRow",
		"GetPlayerPartyVisualInfo",
		"GetPlayerPhaseStatus",
		"RequestPlayerDetails",
		"RequestPartyVisualRoster",
		"GetPlayerTooltipIdentity",
	}) do
		a[method] = function()
			error("presenter queried domain data")
		end
	end
	local state = {}
	local anchor = { frame = QT:CreateTestUIRegion(a, root), name = "Friend-Realm" }
	a:RenderPlayerTooltip(
		state,
		anchor,
		{ title = "A player", text = "A prepared body", introText = "Level 80", color = { 1, 0.5, 0 }, members = {} }
	)
	assert(state.tooltip:IsShown() and state.tooltipTitle.text == "A player" and state.hovered == anchor)
	a:HidePlayerTooltipPresentation(state)
	assert(not state.tooltip:IsShown() and not state.hovered)
end)

QT:RegisterTest(
	"nameplate presenter cannot resolve tooltips inline and presentation does not retire discovery",
	function()
		local clock = QT:CreateTestClock()
		QT.isEnabled = true
		QT.API = {
			Delay = function(delay, run)
				clock:After(delay, run)
			end,
		}
		function QT:IsWorkBlocked()
			return false
		end
		function QT:IsNameplateUnitPlayer()
			return false
		end
		function QT:GetNameplateTooltipScanGuid()
			return "Creature-1"
		end
		function QT:TryResolveNameplateQuestObjectiveState()
			return false
		end
		function QT:HideNameplateIcon() end
		function QT:GetAccessibleNameplateFrameForUnit()
			return nil
		end
		function QT:MaybeScheduleNameplateTooltipRetry() end
		local scans = 0
		function QT:ResolveNameplateQuestStateForUnitToken()
			scans = scans + 1
		end
		local plate = { UnitFrame = { unit = "nameplate1" } }
		QT:RefreshNameplateIcon(plate)
		assert(scans == 0)
		QT:ScheduleNameplateRefresh("nameplate1")
		clock:Advance(0)
		assert(scans == 1, "presentation must not invalidate the queued resolver")
		QT:ScheduleNameplateTooltipResolution("nameplate1", "Creature-1", 0)
		local identities = QT:GetNameplateStateStore().identityGenerationByUnitToken
		identities.nameplate1 = (identities.nameplate1 or 0) + 1
		clock:Advance(0)
		assert(scans == 1, "a replaced identity must invalidate the queued resolver")
	end
)

QT:RegisterTest(
	"profile application repaints an already open focus dialog through the shared settings effect",
	function()
		local a, clock = Fixture()
		a.db.profile = QT:DeepCopy(QT.DEFAULTS.profile)
		a.db.global = {}
		a.GetOption = QT.GetOption
		a.hasLoggedIn = false
		-- Only unrelated domain effects are replaced; real profile transaction,
		-- work scheduler, chrome, controller, frame tree and theme refresh all run.
		for _, method in ipairs({
			"CancelDeveloperDiagnosticReplies",
			"RefreshPartyRoster",
			"QueuePartyNavigationUpdate",
			"RefreshPlayerLocationPins",
			"QueueReleaseNotesThemeRefresh",
			"QueuePartyQuestCompareRender",
			"UpdatePartyChatReminder",
			"BroadcastQuestPartnerStatus",
			"RefreshMinimapPartnerGlow",
			"OnPlayerLocationOptionsChanged",
			"RefreshMinimapButton",
			"EnsureQuestLogChatFrame",
			"CloseQuestLogChatFrame",
			"RefreshActiveAnnouncementBubbles",
			"RefreshPersonalBubbleAnchorVisualState",
			"RefreshPersonalBubbleEditModeDialog",
			"RefreshNameplateAugmentation",
			"RefreshOptionsWindow",
			"RefreshProfilesWindow",
		}) do
			a[method] = function() end
		end
		local choice = function() end
		assert(a:ShowPartyFocusChangeDialog("Friend-Realm", choice, false))
		local frame = a.partyFocusChangeDialog
		assert(frame.scrollPieces[1].vertexColor[1] == 0.14)
		a.db.profile = QT:DeepCopy(a.db.profile)
		a.db.profile.lightMode = true
		assert(a:ApplyActiveProfileState("switch"))
		clock:Advance(0)
		assert(frame:IsShown() and frame.scrollPieces[1].vertexColor[1] == 1)
		assert(frame.confirmAction == choice, "theme application must preserve the open request")
		assert(a:SetOption("lightMode", false))
		assert(frame.scrollPieces[1].vertexColor[1] == 0.14)
		assert((a.invalidCalls or 0) == 0)
	end
)

QT:RegisterTest("owned UI retirement batches retries and contains a failed completion callback", function()
	local a = Fixture()
	local checks = 0
	local regions = {}
	for index = 1, 64 do
		local region = QT:CreateTestUIRegion(a)
		regions[index] = region
		a:QueueOwnedUICleanup(
			region,
			function(r)
				r:Hide()
			end,
			nil,
			function()
				checks = checks + 1
				return false
			end
		)
	end
	assert(checks == 64, "queueing a batch must not rescan every pending marker")
	a:FlushOwnedUICleanup()
	assert(checks == 128)
	for _, region in ipairs(regions) do
		a:CancelOwnedUICleanup(region)
	end
	local frame = QT:CreateTestUIRegion(a)
	function a:RecordDiagnosticError()
		self.cleanupError = true
	end
	a:QueueOwnedUICleanup(frame, function(r)
		r:Hide()
	end, function()
		error("failed completion")
	end)
	assert(a.cleanupError and not a:GetOwnedUICleanupState().flushing and not next(a:GetOwnedUICleanupState().pending))
end)

QT:RegisterTest("settings and minimap tooltip retirement shares cleanup and fences reused hover sessions", function()
	for _, kind in ipairs({ "Settings", "Minimap" }) do
		local a, _, root = Fixture()
		function a:GetSettingsTooltipParent()
			return root
		end
		function a:CreateSettingsTooltipFrame(parent)
			return QT:CreateTestUIRegion(self, parent)
		end
		function a:GetMinimapTooltipParent()
			return root
		end
		function a:CreateMinimapUIFrame(_, _, parent)
			return QT:CreateTestUIRegion(self, parent)
		end
		function a:RefreshMinimapTooltipStatus() end
		local oldAnchor, newAnchor = QT:CreateTestUIRegion(a, root), QT:CreateTestUIRegion(a, root)
		local show, hide = a["Show" .. kind .. "Tooltip"], a["Hide" .. kind .. "Tooltip"]
		show(a, oldAnchor, "A setting", "Some help")
		local tooltip = a[kind == "Settings" and "settingsTooltip" or "minimapTooltip"]
		local staleTick = tooltip.scripts.OnUpdate
		tooltip.forbidden = true
		a.isEnabled = false
		hide(a)
		local cleanup = a:GetOwnedUICleanupState()
		assert(cleanup.pending[tooltip])
		tooltip.forbidden = false
		cleanup.driver.scripts.OnUpdate(cleanup.driver, 0.3)
		assert(not tooltip:IsShown() and not tooltip.scripts.OnUpdate)
		a.isEnabled = true
		show(a, oldAnchor, "A setting", "Some help")
		tooltip.protected = true
		hide(a)
		tooltip.protected = false
		show(a, newAnchor, "Another setting", "More help")
		oldAnchor.forbidden = true
		staleTick(tooltip, 1)
		a:FlushOwnedUICleanup()
		assert(tooltip:IsShown() and not cleanup.pending[tooltip])
		assert((a.invalidCalls or 0) == 0)
	end
end)

QT:RegisterTest("same-key synchronous successor retains its own work owner", function()
	local a, clock = Fixture()
	local first, successor = a:NewRuntimeWorkOwner(), a:NewRuntimeWorkOwner()
	local calls = 0
	a:ScheduleRuntimeWork("example", "same", function()
		a:ScheduleRuntimeWork("example", "same", function()
			calls = calls + 1
		end, { mode = "nextFrame", owner = successor })
	end, { owner = first })
	a:CancelRuntimeWorkOwner(first)
	clock:Advance(0)
	assert(calls == 1)
end)

QT:RegisterTest("nameplate startup work obeys restrictions and is retired with its lifecycle", function()
	local a, clock = Fixture()
	local quest, full = 0, 0
	function a:ScheduleDeferredNameplateQuestStateRefresh()
		quest = quest + 1
	end
	function a:FullRefreshVisibleNameplates()
		full = full + 1
	end
	assert(a:SchedulePlaterStartupNameplateRefreshes())
	clock:Advance(4.1)
	assert(quest == 1 and full == 0)
	a.blocked = true
	clock:Advance(1)
	assert(full == 0)
	a.blocked = false
	a:FlushDeferredWork("restriction ended")
	assert(full == 1)
	a:SchedulePlaterStartupNameplateRefreshes()
	a:ResetNameplateStateStore()
	clock:Advance(6)
	assert(quest == 1 and full == 1 and not next(a:GetDeferredWorkStateStore().entries))
end)

QT:RegisterTest("UI work survives disabled runtime resets and stops polling after completion or cancellation", function()
	local a, clock = Fixture()
	local featureCalls, uiCalls = 0, 0
	a.blocked = true
	a:ScheduleRuntimeWork("foreign_frame_mutation", "feature", function() featureCalls = featureCalls + 1 end)
	a:ScheduleRuntimeWork("foreign_frame_mutation", "window", function() uiCalls = uiCalls + 1 end,
		{ lifetime = "ui", delay = 0 })
	local owner = a:NewRuntimeWorkOwner()
	a:ScheduleRuntimeWork("foreign_frame_mutation", "retired-window", function()
		error("cancelled UI owner executed")
	end, { lifetime = "ui", mode = "nextFrame", owner = owner })
	a:CancelRuntimeWorkOwner(owner)
	local driver = a.runtimeUIWorkFrame
	assert(driver.scripts.OnUpdate and featureCalls == 0 and uiCalls == 0)
	a.isEnabled = false
	a:ResetRuntimeWorkStateStore()
	driver.scripts.OnUpdate(driver, 0.3)
	assert(uiCalls == 0, "UI lifetime must still obey restrictions")
	a.blocked = false
	driver.scripts.OnUpdate(driver, 0.3)
	assert(uiCalls == 1 and featureCalls == 0)
	assert(not driver.scripts.OnUpdate and not next(a:GetRuntimeUIWorkState().entries))
	clock:Advance(0)
	a.isEnabled = true
	a:FlushDeferredWork("enabled again")
	assert(featureCalls == 0, "disabled feature work must remain retired")
	local lastOwner = a:NewRuntimeWorkOwner()
	a.blocked = true
	a:ScheduleRuntimeWork("foreign_frame_mutation", "last-window", function()
		error("last cancelled UI owner executed")
	end, { lifetime = "ui", owner = lastOwner })
	assert(driver.scripts.OnUpdate)
	a:CancelRuntimeWorkOwner(lastOwner)
	assert(not driver.scripts.OnUpdate and not next(a:GetRuntimeUIWorkState().entries))
end)

QT:RegisterTest("visible support windows update themes and fit the display while the addon is disabled", function()
	for _, disableAfterQueue in ipairs({ false, true }) do
		local a, _, root = Fixture()
		a.GetReleaseNotesUIParent = a.GetOwnedUIParent
		a.CreateReleaseNotesUIFrame = a.CreateOwnedWindowFrame
		a.isEnabled = disableAfterQueue
		local dialog = a:CreateScrollDialog(520, 300, "Support")
		dialog:Show()
		assert(a:RenderReleaseNotesWindow({ version = "6.5.9", welcome = "Welcome",
			sections = { { title = "Features", items = { "A feature" } } } }, "6.5.9", false))
		local notes = a.releaseNotesWindow
		assert(dialog.scrollPieces[1].vertexColor[1] == 0.14 and notes.parchmentPieces[1].vertexColor[1] == 0.14)
		root:SetSize(500, 300)
		a.options.lightMode, a.blocked = true, true
		a:QueueScrollDialogThemeRefresh()
		a:QueueReleaseNotesThemeRefresh()
		a:RefreshManagedWindowLayouts()
		local driver = a.runtimeUIWorkFrame
		assert(driver.scripts.OnUpdate)
		if disableAfterQueue then
			a.isEnabled = false
			a:ResetRuntimeWorkStateStore()
		end
		a.blocked = false
		-- No enabled runtime event is needed to resume presentation maintenance.
		driver.scripts.OnUpdate(driver, 0.3)
		assert(dialog.scrollPieces[1].vertexColor[1] == 1 and notes.parchmentPieces[1].vertexColor[1] == 1)
		assert(dialog:IsShown() and notes:IsShown())
		for _, frame in ipairs({ dialog, notes }) do
			assert(frame:GetWidth() * frame:GetScale() <= root:GetWidth() * 0.94 + 0.01)
			assert(frame:GetHeight() * frame:GetScale() <= root:GetHeight() * 0.94 + 0.01)
		end
		assert(not driver.scripts.OnUpdate and (a.invalidCalls or 0) == 0)
		-- Ordinary, unrestricted changes while disabled run immediately too.
		a.options.lightMode = false
		a:QueueScrollDialogThemeRefresh()
		a:QueueReleaseNotesThemeRefresh()
		assert(dialog.scrollPieces[1].vertexColor[1] == 0.14 and notes.parchmentPieces[1].vertexColor[1] == 0.14)
		assert(not driver.scripts.OnUpdate)
	end
end)

QT:RegisterTest("temporary native Edit Mode settings visits preserve the bubble revert baseline", function()
	local a, _, root = Fixture()
	a.options.chatBubbleSize, a.options.chatBubbleDuration = 100, 3
	function a:GetPersonalBubbleAnchor() return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 } end
	function a:RefreshPersonalBubbleAnchorVisualState() end
	function a:RefreshPersonalBubbleEditModeDialog() end
	function a:DeselectPersonalBubbleAnchor() end
	function a:ApplyPersonalBubbleEditSnapshot(snapshot)
		self.options.chatBubbleSize, self.options.chatBubbleDuration = snapshot.chatBubbleSize, snapshot.chatBubbleDuration
	end
	local manager, revert = QT:CreateTestUIRegion(a, root), QT:CreateTestUIRegion(a, root)
	manager.editModeActive = true
	function manager:IsEditModeActive() return self.editModeActive end
	-- Native Settings/Quick Keybind transitions hide a locked manager without
	-- ending Edit Mode; ordinary exit clears editModeActive before OnHide hooks.
	manager:SetScript("OnHide", function()
		if not manager.locked then manager.editModeActive = false end
	end)
	manager:SetScript("OnShow", function() manager.editModeActive = true end)
	a:BindPersonalBubbleEditModeCallbacks(manager, revert, function() end)
	a:EnsurePersonalBubbleEditSession()
	a.options.chatBubbleSize = 140
	local session = a.personalBubbleEditSession
	manager.locked = true
	manager:Hide()
	assert(manager.editModeActive and a.personalBubbleEditSession == session)
	manager:Show()
	revert:Click()
	assert(a.options.chatBubbleSize == 100)
	-- An actual exit commits immediate edits and starts a fresh baseline.
	a.options.chatBubbleSize = 160
	manager.locked = false
	manager:Hide()
	assert(not manager.editModeActive and not a.personalBubbleEditSession)
	manager:Show()
	assert(a.personalBubbleEditSession.saved.chatBubbleSize == 160)
	a.options.chatBubbleSize = 180
	revert:Click()
	assert(a.options.chatBubbleSize == 160)
end)
