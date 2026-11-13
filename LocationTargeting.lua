local QT = _G.QuestTogether
local L = QT.Translate
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
	FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

-- One QT-owned secure button follows the hovered dot/menu row in screen space.
-- Never parent or anchor it to a map or a pooled Blizzard menu frame: doing so
-- would make those foreign frames protected through the secure child.
function QT:CreateLocationTargetButton()
	local button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	button:Hide()
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("type1", "macro")
	-- No 'show' branch: ending combat must not resurrect a stale hover target.
	RegisterStateDriver(button, "visibility", "[combat] hide")
	return button
end

function QT:GetLocationTargetButtonLayer(owner)
	local strataGetter = self:GetAccessibleFrameMember(owner, "GetFrameStrata")
	local levelGetter = self:GetAccessibleFrameMember(owner, "GetFrameLevel")
	if type(strataGetter) ~= "function" or type(levelGetter) ~= "function" then return end
	local ok, strata = pcall(strataGetter, owner)
	if not ok or not self:CanAccessValue(strata) or type(strata) ~= "string" or not STRATA[strata] then return end
	local levelOK, level = pcall(levelGetter, owner)
	level = levelOK and self:SafeToNumber(level) or nil
	if not level then return end
	return strata, math.min(10000, math.max(0, math.floor(level))) + 1
end

local function SetLayer(state, strata, level)
	-- A secure child would protect foreign map/menu frames, so the overlay is
	-- independent. Mirror its owner's layer explicitly: a tooltip-layer button
	-- over a minimap marker can otherwise steal clicks from windows above it.
	if state.strata ~= strata then state.button:SetFrameStrata(strata); state.strata = strata end
	if state.level ~= level then state.button:SetFrameLevel(level); state.level = level end
end

function QT:GetLocationTargetButtonRect(owner)
	if not self:CanAccessForeignFrame(owner, true) or not self:CanAccessForeignFrame(UIParent) then return end
	local left, bottom, width, height = owner:GetRect()
	local scale, uiScale = self:SafeToNumber(owner:GetEffectiveScale()), self:SafeToNumber(UIParent:GetEffectiveScale())
	left, bottom, width, height = self:SafeToNumber(left), self:SafeToNumber(bottom), self:SafeToNumber(width), self:SafeToNumber(height)
	if not left or not bottom or not width or not height or width <= 0 or height <= 0
		or not scale or not uiScale or scale <= 0 or uiScale <= 0 then return end
	local ratio = scale / uiScale
	return left * ratio, bottom * ratio, width * ratio, height * ratio
end

function QT:IsLocationTargetOwnerVisible(owner)
	local method = self:GetAccessibleFrameMember(owner, "IsVisible")
	if type(method) ~= "function" then return false end
	local ok, visible = pcall(method, owner)
	return ok and self:CanAccessValue(visible) and visible == true
end

function QT:PositionLocationTargetButton(button, left, bottom, width, height)
	button:ClearAllPoints()
	button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
	button:SetSize(width, height)
end

function QT:GetLocationTargetMacro(name)
	name = self:NormalizeMemberName(name)
	-- Comms names are data, never macro syntax. Keep full realm/surname identity.
	if not name or name == "" or #name > 128 or name:find('[%c%[%]/;|\\"]') then return end
	return "/targetexact [nocombat] " .. name
end

local function Current(addon, record)
	if not record or not addon.isEnabled or addon:IsRuntimeRestricted()
		or not addon:CanAccessForeignFrame(record.owner, true) or not addon:IsLocationTargetOwnerVisible(record.owner)
		or addon:IsIgnoredPlayerName(record.name) then return false end
	local ok, valid = pcall(record.isCurrent)
	return ok and valid == true
end

function QT:CanMutateLocationTargetButton(button)
	if not self:CanAccessForeignFrame(button) then return false end
	local check = self.API and self.API.CanCallProtectedFunctions
	if type(check) ~= "function" then return false end
	local ok, allowed = pcall(check, button)
	return ok and self:CanAccessValue(allowed) and allowed == true
end

function QT:HideLocationTargetButton()
	local state = rawget(self, "locationTargetState")
	if not state then return end
	state.current = nil
	-- New actions obey all addon restrictions; retiring this secure action uses
	-- its actual native write permission. Noncombat policy is not combat lockdown.
	-- Keep retrying from OnUpdate if the native object really is protected.
	if self:CanMutateLocationTargetButton(state.button) and state.current == nil then
		state.button:SetAttribute("macrotext1", nil)
		-- Native attribute callbacks can acquire a new hover or change permission.
		if self:CanMutateLocationTargetButton(state.button) and state.current == nil then state.button:Hide() end
	end
end

function QT:ShowLocationTargetButton(owner, name, isCurrent, onEnter, onLeave, onClick)
	local macro = self:GetLocationTargetMacro(name)
	local record = { owner = owner, name = name, isCurrent = isCurrent, onEnter = onEnter, onLeave = onLeave, onClick = onClick }
	if not macro or not Current(self, record) then return false end
	local left, bottom, width, height = self:GetLocationTargetButtonRect(owner)
	local strata, level = self:GetLocationTargetButtonLayer(owner)
	if not left or not strata then return false end
	local state = rawget(self, "locationTargetState")
	if not state then
		state = { button = self:CreateLocationTargetButton() }
		self.locationTargetState = state
		local button = state.button
		-- Preserve SecureActionButtonTemplate's OnClick. Only primitive macro text
		-- crosses into its attributes; all validation and callbacks stay addon-owned.
		button:SetScript("PreClick", function()
			local current = state.current
			if not Current(self, current) and state.current == current then self:HideLocationTargetButton() end
		end)
		button:SetScript("PostClick", function(_, mouseButton)
			local current = state.current
			local valid = Current(self, current)
			self:HideLocationTargetButton()
			if valid and current.onClick then current.onClick(mouseButton) end
		end)
		button:SetScript("OnEnter", function()
			local current = state.current
			if Current(self, current) and current.onEnter then current.onEnter() end
		end)
		button:SetScript("OnLeave", function()
			local current = state.current
			self:HideLocationTargetButton()
			if current and current.onLeave then current.onLeave() end
		end)
		button:SetScript("OnUpdate", function(_, elapsed)
			state.elapsed = (state.elapsed or 0) + elapsed
			if state.elapsed < 0.05 then return end
			state.elapsed = 0
			local current = state.current
			if not Current(self, current) then self:HideLocationTargetButton(); return end
			local x, y, w, h = self:GetLocationTargetButtonRect(current.owner)
			local currentStrata, currentLevel = self:GetLocationTargetButtonLayer(current.owner)
			if state.current ~= current then return end
			if not x or not currentStrata or not Current(self, current)
				or not self:CanMutateLocationTargetButton(button) then self:HideLocationTargetButton(); return end
			SetLayer(state, currentStrata, currentLevel)
			self:PositionLocationTargetButton(button, x, y, w, h)
		end)
	end
	if not Current(self, record) or not self:CanMutateLocationTargetButton(state.button) then return false end
	state.current = record
	SetLayer(state, strata, level)
	self:PositionLocationTargetButton(state.button, left, bottom, width, height)
	state.button:SetAttribute("macrotext1", macro)
	state.button:Show()
	return true
end

function QT:PopulateLocationTargetMenu(root, name, isCurrent)
	if root.qtOwnedActionPanel then return end
	local entry = root:CreateButton(L("Target"))
	entry:SetEnabled(self:GetLocationTargetMacro(name) ~= nil)
	entry:SetOnEnter(function(frame)
		self:ShowLocationTargetButton(frame, name, isCurrent, nil, nil, function(button)
			if button == "LeftButton" then entry:Pick(MenuInputContext.MouseButton, button) end
		end)
	end)
	entry:AddResetter(function() self:HideLocationTargetButton() end)
end
