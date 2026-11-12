-- Private buttons only. Never execute a macro or touch secure client globals.
local QT = _G.QuestTogether
local function Equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function Fixture()
	local a = setmetatable({ isEnabled = true, valid = true }, { __index = QT })
	a.API = { CanCallProtectedFunctions = function() return not a.combat and not a.denied end }
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:IsIgnoredPlayerName(name) return self.ignored == name end
	function a:NormalizeMemberName(name) return name end
	function a:CanAccessForeignFrame(frame, shown) return frame and not frame.forbidden and (not shown or frame.shown) end
	function a:IsLocationTargetOwnerVisible(owner) return owner.shown and not owner.parentHidden end
	function a:GetLocationTargetButtonRect(owner) return owner.x or 10, 20, 12, 12 end
	function a:PositionLocationTargetButton(button, x, y, w, h)
		assert(not self.blocked, "restricted positioning")
		button.rect = { x, y, w, h }
	end
	function a:CreateLocationTargetButton()
		local b = { scripts = {}, attrs = {}, shown = false }
		function b:SetScript(event, fn) self.scripts[event] = fn end
		function b:SetAttribute(key, value)
			assert(not a.combat and not a.denied, "protected attribute write")
			assert(type(value) ~= "table", "secure payload must stay primitive")
			self.attrs[key] = value
		end
		function b:Hide() assert(not a.combat and not a.denied); self.shown = false end
		function b:Show() assert(not a.blocked); self.shown = true end
		function b:SetFrameStrata(value) assert(not a.blocked); self.strata = value end
		function b:SetFrameLevel(value) assert(not a.blocked); self.level = value end
		return b
	end
	a.owner = { shown = true, strata = "LOW", level = 12 }
	function a.owner:GetFrameStrata() return self.strata end
	function a.owner:GetFrameLevel() return self.level end
	function a:Open(name)
		return self:ShowLocationTargetButton(self.owner, name or "Friend-Realm", function() return self.valid end,
			nil, nil, function(button) self.clicked = button end)
	end
	return a
end

QT:RegisterTest("minimap target buttons keep hardware actions separate and invalidate stale clicks", function()
	local a = Fixture()
	assert(a:Open())
	local b = a.locationTargetState.button
	Equal(b.scripts.OnClick, nil) -- The template's protected handler is never replaced.
	Equal(b.attrs.macrotext1, "/targetexact [nocombat] Friend-Realm")
	a.valid = false
	b.scripts.PreClick()
	Equal(b.attrs.macrotext1, nil)
	b.scripts.PostClick(nil, "LeftButton")
	Equal(a.clicked, nil)
	Equal(b.shown, false)
	a.valid = true
	assert(a:Open("Another Person"))
	Equal(a.locationTargetState.button, b)
	Equal(b.attrs.macrotext1, "/targetexact [nocombat] Another Person")
	b.scripts.PreClick()
	b.scripts.PostClick(nil, "RightButton")
	Equal(a.clicked, "RightButton")
	Equal(b.attrs.macrotext1, nil)
end)

QT:RegisterTest("target overlays follow minimap and menu layers without covering unrelated windows", function()
	local a = Fixture()
	assert(a:Open())
	local b = a.locationTargetState.button
	Equal(b.strata, "LOW")
	Equal(b.level, 13)
	-- Menu rows still need a clickable overlay above their own layer. The
	-- same pooled secure button must return to the minimap's layer afterward.
	a.owner.strata, a.owner.level = "FULLSCREEN_DIALOG", 50
	assert(a:Open())
	Equal(b.strata, "FULLSCREEN_DIALOG")
	Equal(b.level, 51)
	a.owner.strata, a.owner.level = "MEDIUM", 20
	b.scripts.OnUpdate(nil, 0.1)
	Equal(b.strata, "MEDIUM")
	Equal(b.level, 21)
	a.owner.strata = nil
	b.scripts.OnUpdate(nil, 0.1)
	Equal(b.shown, false)
	Equal(b.attrs.macrotext1, nil)
end)

QT:RegisterTest("target hover tracks screen position and drops hidden ignored disabled or restricted owners", function()
	for _, reason in ipairs({ "hidden", "parentHidden", "ignored", "disabled", "restricted", "forbidden", "stale" }) do
		local a = Fixture(); assert(a:Open())
		local b = a.locationTargetState.button
		a.owner.x = 42
		b.scripts.OnUpdate(nil, 0.1)
		Equal(b.rect[1], 42)
		if reason == "hidden" then a.owner.shown = false
		elseif reason == "parentHidden" then a.owner.parentHidden = true
		elseif reason == "ignored" then a.ignored = "Friend-Realm"
		elseif reason == "disabled" then a.isEnabled = false
		elseif reason == "restricted" then a.blocked, a.combat = true, true; b.shown = false -- Combat visibility driver only.
		elseif reason == "forbidden" then a.owner.forbidden = true
		else a.valid = false end
		b.scripts.OnUpdate(nil, 0.1)
		Equal(a.locationTargetState.current, nil)
		Equal(b.shown, false)
		a.blocked, a.combat = false, false
		b.scripts.PostClick(nil, "LeftButton")
		Equal(a.clicked, nil)
	end
end)

QT:RegisterTest("noncombat target restrictions retire the secure overlay before a stale hardware click", function()
	for _, trigger in ipairs({ "update", "click", "leave", "restrictionEvent" }) do
		local a = Fixture(); assert(a:Open())
		local b = a.locationTargetState.button
		a.blocked = true -- No combat visibility driver fires for this policy.
		if trigger == "update" then b.scripts.OnUpdate(nil, 0.1)
		elseif trigger == "click" then b.scripts.PreClick()
		elseif trigger == "leave" then b.scripts.OnLeave()
		else
			function a:FlushDeferredWork() end
			a:ADDON_RESTRICTION_STATE_CHANGED()
		end
		Equal(a.locationTargetState.current, nil)
		Equal(b.attrs.macrotext1, nil)
		Equal(b.shown, false)
		b.scripts.PostClick(nil, "LeftButton")
		Equal(a.clicked, nil)
		Equal(a:Open(), false)
	end
end)

QT:RegisterTest("target cleanup waits for real object permission and never revives the retired action", function()
	local a = Fixture(); assert(a:Open())
	local b = a.locationTargetState.button
	a.blocked, a.denied = true, true
	b.scripts.OnUpdate(nil, 0.1)
	b.scripts.PreClick()
	Equal(a.locationTargetState.current, nil)
	Equal(b.shown, true) -- A protected mutation must not be attempted.
	a.denied = false -- Policy remains blocked while native cleanup becomes legal.
	b.scripts.OnUpdate(nil, 0.1)
	Equal(b.shown, false)
	Equal(b.attrs.macrotext1, nil)
	a.blocked = false
	b.scripts.OnUpdate(nil, 0.1)
	Equal(b.shown, false)
	for _, value in ipairs({ "true", 1, {} }) do
		a.API.CanCallProtectedFunctions = function() return value end
		Equal(a:CanMutateLocationTargetButton(b), false)
	end
	a.API.CanCallProtectedFunctions = function() error("unavailable") end
	Equal(a:CanMutateLocationTargetButton(b), false)
	a.API.CanCallProtectedFunctions = nil
	Equal(a:CanMutateLocationTargetButton(b), false)
end)

QT:RegisterTest("target cleanup does not hide a new hover acquired by an attribute callback", function()
	local a = Fixture(); assert(a:Open())
	local b = a.locationTargetState.button
	local write = b.SetAttribute
	function b:SetAttribute(key, value)
		write(self, key, value)
		if key == "macrotext1" and value == nil and not a.reentered then
			a.reentered = true
			assert(a:Open("New-Realm"))
		end
	end
	a:HideLocationTargetButton()
	Equal(b.shown, true)
	Equal(b.attrs.macrotext1, "/targetexact [nocombat] New-Realm")
	Equal(a.locationTargetState.current.name, "New-Realm")
end)

QT:RegisterTest("target macros preserve full identities and reject command syntax", function()
	local a = Fixture()
	for _, name in ipairs({ "Friend-Realm", "Aria Frostwind", "Élodie-Lune" }) do
		Equal(a:GetLocationTargetMacro(name), "/targetexact [nocombat] " .. name)
	end
	for _, name in ipairs({ "", "Friend\n/target enemy", "Friend;enemy", "[combat] Enemy", 'Friend"', "A|B", string.rep("a", 129) }) do
		-- An empty normalized name is rejected by the real normalizer too.
		Equal(a:GetLocationTargetMacro(name), nil)
	end
end)

QT:RegisterTest("target geometry callbacks cannot position an overlay after policy changes", function()
	local a = Fixture(); assert(a:Open())
	local b = a.locationTargetState.button
	local original = a.GetLocationTargetButtonRect
	function a:GetLocationTargetButtonRect(owner)
		a.blocked = true
		return original(self, owner)
	end
	b.scripts.OnUpdate(nil, 0.1)
	Equal(a.locationTargetState.current, nil)
	Equal(b.attrs.macrotext1, nil)
	Equal(b.shown, false)
end)

_G.QuestTogether:RecordTestModule("scripts/regression_location_targeting.lua")
