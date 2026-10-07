-- Private buttons only. Never execute a macro or touch secure client globals.
local QT = _G.QuestTogether
local function Equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function Fixture()
	local a = setmetatable({ isEnabled = true, valid = true }, { __index = QT })
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
			assert(not a.blocked, "restricted attribute write")
			assert(type(value) ~= "table", "secure payload must stay primitive")
			self.attrs[key] = value
		end
		function b:Hide() assert(not a.blocked); self.shown = false end
		function b:Show() assert(not a.blocked); self.shown = true end
		return b
	end
	a.owner = { shown = true }
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
		elseif reason == "restricted" then a.blocked = true; b.shown = false -- Secure visibility driver.
		elseif reason == "forbidden" then a.owner.forbidden = true
		else a.valid = false end
		b.scripts.OnUpdate(nil, 0.1)
		Equal(a.locationTargetState.current, nil)
		Equal(b.shown, false)
		a.blocked = false
		b.scripts.PostClick(nil, "LeftButton")
		Equal(a.clicked, nil)
	end
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

QT:RegisterTest("minimap Target is the first action and map menus retain their normal order", function()
	for _, minimap in ipairs({ true, false }) do
		local a = Fixture()
		function a:GetShortDisplayName(name) return name end
		function a:IsPlayerLookingForQuestPartners() return false end
		function a:ShouldRequestPartyJoin() return false end
		function a:PopulatePartyFocusMenu() end
		local root = { buttons = {} }
		function root:CreateTitle() end
		function root:CreateButton(text, callback)
			local entry = { text = text, callback = callback }
			function entry:SetEnabled(value) self.enabled = value end
			function entry:SetOnEnter(fn) self.enter = fn end
			function entry:AddResetter(fn) self.reset = fn end
			self.buttons[#self.buttons + 1] = entry
			return entry
		end
		local first = minimap and function(menu)
			a:PopulateLocationTargetMenu(menu, "Friend-Realm", function() return a.valid end)
		end or nil
		a:PopulateChatLogSpeakerMenu(root, a.owner, "Friend-Realm", first)
		Equal(root.buttons[1].text, minimap and "Target" or "Invite")
		if minimap then
			root.buttons[1].enter(a.owner)
			Equal(a.locationTargetState.current.name, "Friend-Realm")
			root.buttons[1].reset()
			Equal(a.locationTargetState.current, nil)
		end
	end
end)
