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
	function a:ScheduleDeferredWork(_, key, callback)
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
	function a:GetPartyQuestUIParent()
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
