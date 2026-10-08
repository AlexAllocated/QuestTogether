local QT = _G.QuestTogether
local function Near(a, b)
	assert(math.abs(a - b) < 0.001, tostring(a) .. " ~= " .. tostring(b))
end
local function Fixture()
	local a = setmetatable(
		{ db = { profile = { windowScale = 100 } }, pending = {}, managedWindows = {} },
		{ __index = QT }
	)
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	function a:ScheduleRuntimeWork(_, key, callback, options)
		assert(options.lifetime == "ui")
		self.pending[key] = callback
	end
	function a:Print(text)
		self.printed = text
	end
	local function Frame(w, h, root)
		local f = { w = w, h = h, scale = 1, left = 0, bottom = 0, scripts = {}, shown = true }
		function f:IsForbidden()
			return self.forbidden == true
		end
		function f:IsProtected()
			return false
		end
		function f:GetWidth()
			return self.w
		end
		function f:GetHeight()
			return self.h
		end
		function f:GetEffectiveScale()
			return self.scale * (root and root.scale or 1)
		end
		function f:GetLeft()
			return self.left
		end
		function f:GetBottom()
			return self.bottom
		end
		function f:GetTop()
			return self.bottom + self.h
		end
		function f:SetSize(w2, h2)
			assert(not a.blocked)
			self.w, self.h = w2, h2
		end
		function f:SetScale(v)
			assert(not a.blocked)
			self.scale = v
		end
		function f:SetClampedToScreen(v)
			self.clamped = v
		end
		function f:ClearAllPoints() end
		function f:SetPoint(_, _, _, x, y)
			assert(not a.blocked)
			self.left, self.bottom = x - self.w / 2, y - self.h / 2
		end
		function f:SetScript(k, v)
			self.scripts[k] = v
		end
		function f:HookScript(k, v)
			local old = self.scripts[k]
			self.scripts[k] = function(...)
				if old then
					old(...)
				end
				v(...)
			end
		end
		function f:EnableKeyboard(v)
			self.keyboard = v
		end
		function f:SetPropagateKeyboardInput(v)
			self.propagate = v
		end
		function f:Hide()
			self.shown = false
		end
		return f
	end
	local root, frame = Frame(3440, 1440)
	frame = Frame(1250, 720, root)
	function a:GetOwnedUIParent()
		return root
	end
	function a:CanAccessForeignFrame(f)
		return not f.forbidden
	end
	a:RegisterManagedWindow(frame, "log", 700, 500)
	return a, frame, root
end
QT:RegisterTest("window layout survives ultrawide to tablet and UI scale changes inside screen", function()
	local a, f, root = Fixture()
	f.left, f.bottom = 2100, 600
	a:SaveWindowLayout(f)
	local saved = a.db.profile.windowLayouts.log
	assert(saved.x > 0.7)
	root.w, root.h, root.scale = 1024, 768, 0.7
	a:DISPLAY_SIZE_CHANGED()
	assert(f.scale < 1 and f.clamped)
	assert(f.left * f.scale >= 0 and (f.left + f.w) * f.scale <= root.w)
	assert(f.bottom * f.scale >= 0 and (f.bottom + f.h) * f.scale <= root.h)
	-- A screen-fit operation must not replace the user's preferred saved dimensions.
	Near(a.db.profile.windowLayouts.log.width, 1250)
	root.w, root.h = 3440, 1440
	a:UI_SCALE_CHANGED()
	Near(f.scale, 1)
	Near((f.left + f.w / 2) * f.scale / root.w, saved.x)
end)
QT:RegisterTest("window restoration sanitizes corrupt geometry and defers restricted mutations", function()
	local a, f, root = Fixture()
	a.db.profile.windowLayouts = { log = { width = 0 / 0, height = -999, x = math.huge, y = -1000 } }
	a.blocked = true
	assert(not a:ApplyWindowLayout(f, true))
	a:DISPLAY_SIZE_CHANGED()
	a.blocked = false
	a.pending.window_layouts()
	assert(f.w >= 700 and f.h >= 500 and f.bottom >= 0)
	a.blocked = true
	a:ResetWindowLayouts()
	-- A later display event may replace deferred work; the reset intent survives.
	a:DISPLAY_SIZE_CHANGED()
	a.blocked = false
	a.pending.window_layouts()
	a:ResetWindowLayouts()
	Near((f.left + f.w / 2) * f.scale, root.w / 2)
	Near((f.bottom + f.h / 2) * f.scale, root.h / 2)
	assert(next(a.db.profile.windowLayouts) == nil)
end)
QT:RegisterTest("QT window keyboard input propagates normal keys and uses dismissal action", function()
	local a, f = Fixture()
	local dismissals = 0
	f.escapeAction = function()
		dismissals = dismissals + 1
		f:Hide()
	end
	f.scripts.OnKeyDown(f, "W")
	assert(f.propagate and dismissals == 0)
	f.scripts.OnKeyDown(f, "ESCAPE")
	assert(not f.propagate and dismissals == 1 and not f.shown)
	f.scripts.OnShow()
	assert(f.propagate)
	a.blocked = true
	f.scripts.OnKeyDown(f, "ESCAPE")
	assert(dismissals == 1)
end)

QT:RegisterTest("managed layout reflows restored and deferred reset dimensions before screen fit", function()
	local a, f, root = Fixture()
	local calls = 0
	f.LayoutManagedWindow = function()
		calls = calls + 1
		assert(not a:ApplyWindowLayout(f), "reflow must not recursively fit the window")
		-- A measured dialog may be taller than its construction-time frame.
		f:SetSize(f.w, f.userHeight or 900)
	end
	a.db.profile.windowLayouts = { log = { width = 880, height = 610, x = 0.9, y = 0.9 } }
	a:RefreshManagedWindowLayouts()
	Near(f.w, 880)
	Near(f.h, 610)
	assert(calls == 1)
	f:Hide()
	a.blocked = true
	a:ResetWindowLayouts()
	assert(calls == 1)
	root.w, root.h = 1024, 768
	a:DISPLAY_SIZE_CHANGED()
	a.blocked = false
	a.pending.window_layouts()
	Near(f.w, 1250)
	Near(f.h, 900)
	assert(calls == 2 and not f.shown)
	assert(f.bottom * f.scale >= 0 and (f.bottom + f.h) * f.scale <= root.h)
	assert(next(a.db.profile.windowLayouts) == nil)
end)

QT:RegisterTest("failed managed layout callback releases its guard for a later recovery", function()
	local a, f = Fixture()
	f.LayoutManagedWindow = function() error("fixture measurement unavailable") end
	assert(not pcall(a.ApplyWindowLayout, a, f, true))
	assert(not a.managedWindows[f].applying)
	f.LayoutManagedWindow = function() f:SetSize(900, 550) end
	assert(a:ApplyWindowLayout(f, true))
	Near(f.w, 900)
	Near(f.h, 550)
end)

local function ProfileFixture()
	local a, frame, root = Fixture()
	a.activeProfileKey, a.activeCharacterKey = "A", "Me-Realm"
	a.db.profiles, a.db.profileKeys = { A = a.db.profile }, { ["Me-Realm"] = "A" }
	a.db.profiles.Blank = a:DeepCopy(QT.DEFAULTS.profile)
	a.hasLoggedIn, a.isEnabled = true, true
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:Enable() self.isEnabled = true end
	function a:Disable() self.isEnabled = false end
	-- Keep real profile validation/effect dispatch and the whole window path.
	-- Other services use private no-op adapters, never live UI/network state.
	for _, name in ipairs({ "CancelDeveloperDiagnosticReplies", "RefreshPartyRoster", "ResetPlayerPhases",
		"RefreshPlayerLocationPins", "RefreshWindowThemes", "UpdatePartyChatReminder", "BroadcastQuestPartnerStatus",
		"RefreshMinimapPartnerGlow", "OnPlayerLocationOptionsChanged", "RefreshMinimapButton", "EnsureQuestLogChatFrame",
		"CloseQuestLogChatFrame", "RefreshActiveAnnouncementBubbles", "RefreshPersonalBubbleAnchorVisualState",
		"RefreshPersonalBubbleEditModeDialog", "RefreshNameplateAugmentation", "RefreshOptionsWindow",
		"RefreshProfilesWindow", "Debugf", "QueuePartyNavigationUpdate" }) do
		a[name] = function() end
	end
	frame:SetSize(1600, 900)
	frame.userWidth, frame.userHeight = 1600, 900
	frame.left, frame.bottom = 1700, 420
	a:SaveWindowLayout(frame)
	return a, frame, root
end

local function AssertDefaultLayout(frame, root)
	Near(frame.w, 1250)
	Near(frame.h, 720)
	Near((frame.left + frame.w / 2) * frame.scale / root.w, 0.5)
	Near((frame.bottom + frame.h / 2) * frame.scale / root.h, 0.5)
	assert(frame.userWidth == nil and frame.userHeight == nil)
end

QT:RegisterTest("profile reset switch and copy restore defaults when window geometry is absent", function()
	for _, operation in ipairs({ "reset", "switch", "copy" }) do
		local a, frame, root = ProfileFixture()
		local previous = a.db.profile
		if operation == "reset" then assert(a:ResetActiveProfile())
		elseif operation == "switch" then assert(a:SetActiveProfile("Blank"))
		else assert(a:CopyProfileIntoActiveProfile("Blank")) end
		AssertDefaultLayout(frame, root)
		assert(a.db.profile.windowLayouts == nil)
		Near(previous.windowLayouts.log.width, 1600)
	end
end)

QT:RegisterTest("profile saved window geometry survives display and scale changes", function()
	local a, frame, root = ProfileFixture()
	local saved = { width = 880, height = 610, x = 0.7, y = 0.6 }
	a.db.profiles.Blank.windowLayouts = { log = saved }
	assert(a:SetActiveProfile("Blank"))
	Near(frame.w, 880)
	Near(frame.h, 610)
	Near((frame.left + frame.w / 2) / root.w, 0.7)
	root.w, root.h, root.scale = 1024, 768, 0.7
	a:DISPLAY_SIZE_CHANGED()
	assert(a:SetOption("windowScale", 130))
	Near(frame.w, 880)
	Near(frame.h, 610)
	assert(frame.left * frame.scale >= 0 and (frame.left + frame.w) * frame.scale <= root.w)
	assert(frame.bottom * frame.scale >= 0 and (frame.bottom + frame.h) * frame.scale <= root.h)
	assert(a.db.profile.windowLayouts.log == saved)
	Near(saved.x, 0.7)
	root.w, root.h, root.scale = 3440, 1440, 1
	a:UI_SCALE_CHANGED()
	Near((frame.left + frame.w / 2) * frame.scale / root.w, 0.7)
	frame.left, frame.bottom = 800, 250
	a:SaveWindowLayout(frame)
	assert(a.db.profile.windowLayouts.log ~= saved, "ordinary saves still belong to the active profile")
end)

QT:RegisterTest("deferred profile geometry survives display events on hidden disabled windows", function()
	local a, frame, root = ProfileFixture()
	frame:Hide()
	a.blocked, a.db.profiles.Blank.enabled = true, false
	assert(a:SetActiveProfile("Blank"))
	Near(frame.w, 1600)
	root.w, root.h, root.scale = 1024, 768, 0.7
	a:DISPLAY_SIZE_CHANGED() -- Replaces the pending callback without losing the profile transition.
	a.blocked = false
	a:SaveWindowLayout(frame) -- A gesture ending before restoration cannot pollute the new profile.
	assert(a.db.profile.windowLayouts == nil)
	a.pending.window_layouts()
	AssertDefaultLayout(frame, root)
	assert(not frame.shown and not a.isEnabled)
	assert(frame.scale < 1 and frame.left * frame.scale >= 0)
	assert((frame.left + frame.w) * frame.scale <= root.w)
end)

QT:RegisterTest("quarantined window keeps its profile transition until a later show can restore it", function()
	local a, frame, root = ProfileFixture()
	frame.forbidden = true
	assert(a:SetActiveProfile("Blank"))
	Near(frame.w, 1600)
	frame.forbidden = false
	frame.scripts.OnShow() -- Uses ApplyWindowLayout without an explicit restore argument.
	AssertDefaultLayout(frame, root)
end)
