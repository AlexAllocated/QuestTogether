-- Private frame tree shared by UI regressions and safe to load in /qt test.
-- No fallback metatable: an unimplemented engine method is a test failure.
local QT = _G.QuestTogether
function QT:CreateTestUIRegion(owner, parent, kind)
	owner = owner or {}
	local frame = {
		owner = owner,
		parent = parent,
		kind = kind,
		children = {},
		scripts = {},
		rawScripts = {},
		hooks = {},
		shown = true,
		enabled = true,
		value = 0,
		width = 1200,
		height = 800,
		points = {},
		writes = 0,
	}
	if parent then
		parent.children[#parent.children + 1] = frame
	end
	function frame:IsForbidden()
		return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
	end
	function frame:IsProtected()
		return self.protected == true or (self.parent and self.parent:IsProtected()) or false
	end
	function frame:CheckRead()
		if self:IsForbidden() then
			owner.invalidCalls = (owner.invalidCalls or 0) + 1
			error("unsafe owned read")
		end
	end
	function frame:Check(teardown)
		if (owner.blocked and not teardown) or self:IsForbidden() or self:IsProtected() then
			owner.invalidCalls = (owner.invalidCalls or 0) + 1
			error("unsafe owned mutation")
		end
		self.writes = self.writes + 1
	end
	local function RebuildScript(event)
		if not frame.rawScripts[event] and not frame.hooks[event] then
			frame.scripts[event] = nil
			return
		end
		local primary, hooks = frame.rawScripts[event], frame.hooks[event]
		frame.scripts[event] = function(...)
			if primary then
				primary(...)
			end
			for _, callback in ipairs(hooks or {}) do
				callback(...)
			end
		end
	end
	function frame:SetScript(event, callback)
		self:Check(callback == nil)
		self.rawScripts[event] = callback
		RebuildScript(event)
	end
	function frame:GetScript(event)
		self:CheckRead()
		return self.rawScripts[event]
	end
	function frame:HookScript(event, callback)
		self:Check()
		self.hooks[event] = self.hooks[event] or {}
		table.insert(self.hooks[event], callback)
		RebuildScript(event)
	end
	function frame:IsShown()
		self:CheckRead()
		return self.shown
	end
	function frame:IsVisible()
		self:CheckRead()
		return self.shown and (not self.parent or self.parent:IsVisible())
	end
	local function VisibilityMutation(self, mutate)
		local previous = {}
		local function Visible(node)
			return node.shown and (not node.parent or Visible(node.parent))
		end
		local function Gather(node)
			previous[#previous + 1] = { node, Visible(node) }
			for _, child in ipairs(node.children) do
				Gather(child)
			end
		end
		Gather(self)
		mutate()
		for _, old in ipairs(previous) do
			local node, visible = old[1], Visible(old[1])
			if visible ~= old[2] then
				local callback = node.scripts[visible and "OnShow" or "OnHide"]
				if callback then
					callback(node)
				end
			end
		end
	end
	function frame:Show()
		self:Check()
		VisibilityMutation(self, function()
			self.shown = true
		end)
	end
	function frame:Hide()
		self:Check(true)
		VisibilityMutation(self, function()
			self.shown = false
		end)
	end
	function frame:SetParent(value)
		self:Check()
		VisibilityMutation(self, function()
			if self.parent then
				for index, child in ipairs(self.parent.children) do
					if child == self then
						table.remove(self.parent.children, index)
						break
					end
				end
			end
			self.parent = value
			if value then
				value.children[#value.children + 1] = self
			end
		end)
	end
	function frame:GetParent()
		self:CheckRead()
		return self.parent
	end
	function frame:SetSize(w, h)
		self:Check()
		if self.resizeBounds then
			w = math.max(self.resizeBounds[1], math.min(self.resizeBounds[3] or math.huge, w))
			h = math.max(self.resizeBounds[2], math.min(self.resizeBounds[4] or math.huge, h))
		end
		local changed = self.width ~= w or self.height ~= h
		self.width, self.height = w, h
		if changed and self.scripts.OnSizeChanged then
			self.scripts.OnSizeChanged(self, w, h)
		end
	end
	function frame:SetWidth(v)
		self:SetSize(v, self.height)
	end
	function frame:SetHeight(v)
		self:SetSize(self.width, v)
	end
	function frame:GetWidth()
		self:CheckRead()
		return self.width
	end
	function frame:GetHeight()
		self:CheckRead()
		return self.height
	end
	function frame:SetScale(v)
		self:Check()
		self.scale = v
	end
	function frame:GetScale()
		self:CheckRead()
		return self.scale or 1
	end
	function frame:GetEffectiveScale()
		self:CheckRead()
		return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
	end
	function frame:GetLeft()
		self:CheckRead()
		return self.left or (self.parent and 200 or 0)
	end
	function frame:GetTop()
		self:CheckRead()
		return self.top or 800
	end
	function frame:GetBottom()
		self:CheckRead()
		return self.bottom or 0
	end
	function frame:SetPoint(...)
		self:Check()
		self.points[#self.points + 1] = { ... }
	end
	function frame:ClearAllPoints()
		self:Check()
		self.points = {}
	end
	function frame:SetAllPoints(relative)
		self:Check()
		self.allPoints = relative or self.parent
	end
	function frame:SetFrameLevel(value)
		self:Check()
		self.frameLevel = value
	end
	function frame:GetFrameLevel()
		self:CheckRead()
		return self.frameLevel or (self.parent and self.parent:GetFrameLevel() + 1) or 1
	end
	function frame:SetText(v)
		self:Check()
		self.text = v
		if self.scripts.OnTextChanged then
			self.scripts.OnTextChanged(self, false)
		end
	end
	function frame:GetText()
		self:CheckRead()
		return self.text or ""
	end
	function frame:SetFontObject(v)
		self:Check()
		self.font = v
	end
	function frame:GetStringWidth()
		self:CheckRead()
		return #(self.text or "") * 7
	end
	function frame:GetStringHeight()
		self:CheckRead()
		if owner.measureUnavailable then
			return nil
		end
		local size = self.font == "GameFontNormalLarge" and 20 or 14
		local columns = math.max(1, math.floor((self.width > 0 and self.width or 500) / 7))
		local lines = 0
		for line in ((self.text or "") .. "\n"):gmatch("(.-)\n") do
			lines = lines + math.max(1, math.ceil(#line / columns))
		end
		return math.max(1, lines) * size
	end
	function frame:CreateTexture(_, _, template)
		self:Check()
		if owner.failTextureCreate then
			owner.failTextureCreate = false
			error("fixture texture creation interrupted")
		end
		local child = QT:CreateTestUIRegion(owner, self, "Texture")
		child.template = template
		if owner.regions then
			owner.regions[#owner.regions + 1] = child
		end
		return child
	end
	function frame:CreateMaskTexture()
		return self:CreateTexture()
	end
	function frame:CreateFontString(_, _, font)
		self:Check()
		local child = QT:CreateTestUIRegion(owner, self, "FontString")
		child.font = font
		if owner.regions then
			owner.regions[#owner.regions + 1] = child
		end
		return child
	end
	function frame:SetValue(v)
		self:Check()
		if self.minimum then
			v = math.max(self.minimum, math.min(self.maximum, v))
		end
		if self.value == v then
			return
		end
		self.value = v
		if self.scripts.OnValueChanged then
			self.scripts.OnValueChanged(self, v)
		end
	end
	function frame:GetValue()
		self:CheckRead()
		return self.value
	end
	function frame:SetMinMaxValues(a, b)
		self:Check()
		self.minimum, self.maximum = a, b
		self:SetValue(self.value)
	end
	function frame:SetScrollChild(child)
		self:Check()
		self.child = child
	end
	function frame:SetVerticalScroll(v)
		self:Check()
		self.offset, self.verticalScroll = v, v
	end
	function frame:SetHorizontalScroll(v)
		self:Check()
		self.horizontalScroll = v
	end
	function frame:SetChecked(v)
		self:Check()
		self.checked = v
	end
	function frame:GetChecked()
		self:CheckRead()
		return self.checked
	end
	function frame:SetEnabled(v)
		self:Check()
		self.enabled = v
	end
	function frame:SetTexture(v)
		self:Check()
		self.texture, self.atlas = v, nil
	end
	function frame:SetAtlas(v)
		self:Check()
		self.atlas = v
	end
	function frame:GetAtlas()
		self:CheckRead()
		return self.atlas
	end
	function frame:SetDesaturated(v)
		self:Check()
		self.desaturated = v
	end
	function frame:SetResizeBounds(...)
		self:Check()
		self.resizeBounds = { ... }
	end
	function frame:StartMoving()
		self:Check()
		self.moving = true
	end
	function frame:StartSizing(point, fromMouse)
		self:Check()
		self.sizing, self.sizingPoint, self.sizingFromMouse = point, point, fromMouse
		self.resizeArmedOnStart = self.resizing
	end
	function frame:StopMovingOrSizing()
		self:Check(true)
		self.moving, self.sizing = false, nil
	end
	function frame:SetFocus()
		self:Check()
		self.focus = true
	end
	function frame:ClearFocus()
		self:Check(true)
		self.focus = false
	end
	function frame:SetPropagateKeyboardInput(v)
		self:Check()
		self.propagate = v
	end
	function frame:Click(...)
		if self.scripts.OnClick then
			self.scripts.OnClick(self, ...)
		end
	end
	function frame:SetButtonState(state, locked)
		self:Check()
		self.buttonState, self.buttonStateLocked = state, locked
	end
	for method, field in pairs({
		SetTextColor = "textColor",
		SetVertexColor = "vertexColor",
		SetColorTexture = "textureColor",
		SetTexCoord = "texCoords",
	}) do
		frame[method] = function(self, ...)
			self:Check()
			self[field] = { ... }
		end
	end
	for _, method in ipairs({ "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture" }) do
		frame[method] = function(self, texture)
			self:Check()
			self.buttonTextures = self.buttonTextures or {}
			self.buttonTextures[method] = texture
		end
	end
	function frame:SetFrameStrata(value)
		self:Check()
		self.strata = value
	end
	-- Known presentation-only methods; behavioral calls above are never no-ops.
	for _, method in ipairs({
		"SetAlpha",
		"SetMovable",
		"SetResizable",
		"RegisterForDrag",
		"RegisterForClicks",
		"SetToplevel",
		"SetFlattensRenderLayers",
		"SetClampedToScreen",
		"EnableMouse",
		"SetHorizTile",
		"SetVertTile",
		"SetBlendMode",
		"AddMaskTexture",
		"SetJustifyH",
		"SetJustifyV",
		"SetWordWrap",
		"EnableMouseWheel",
		"SetOrientation",
		"SetValueStep",
		"SetThumbTexture",
		"SetObeyStepOnDrag",
		"SetAutoFocus",
		"EnableKeyboard",
		"SetTextInsets",
		"HighlightText",
		"Raise",
		"SetMaxLetters",
		"SetMaxLines",
		"SetBackdrop",
		"SetBackdropColor",
		"SetBackdropBorderColor",
		"SetSpacing",
		"SetClipsChildren",
	}) do
		frame[method] = function(self)
			self:Check()
		end
	end
	return frame
end
