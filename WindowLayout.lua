-- Only QT-owned windows are registered here. Saved anchors are screen-relative;
-- every restoration fits the current display, never the display that saved it.
local QT = _G.QuestTogether
local L = QT.Translate
local function Number(v, fallback)
	if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
		return fallback
	end
	return v
end
local function Read(a, frame, method)
	local getter = a:GetAccessibleFrameMember(frame, method)
	if type(getter) ~= "function" then
		return
	end
	local ok, value = pcall(getter, frame)
	if ok then
		return Number(a:SafeToNumber(value))
	end
end
function QT:FitWindowGeometry(width, height, screenWidth, screenHeight, preferredScale, x, y)
	width, height = math.max(1, Number(width, 700)), math.max(1, Number(height, 500))
	screenWidth, screenHeight = math.max(1, Number(screenWidth, 1920)), math.max(1, Number(screenHeight, 1080))
	local scale = math.min(
		math.max(0.8, math.min(1.5, Number(preferredScale, 1))),
		screenWidth * 0.94 / width,
		screenHeight * 0.94 / height
	)
	local halfW, halfH = width * scale / screenWidth / 2, height * scale / screenHeight / 2
	x = math.max(halfW + 0.01, math.min(1 - halfW - 0.01, Number(x, 0.5)))
	y = math.max(halfH + 0.01, math.min(1 - halfH - 0.01, Number(y, 0.5)))
	return scale, x, y
end
function QT:GetWindowScale()
	return math.max(0.8, math.min(1.5, Number(self:GetOption("windowScale"), 100) / 100))
end
function QT:SaveWindowLayout(frame)
	local info = rawget(self, "managedWindows") and self.managedWindows[frame]
	if
		not info
		or info.applying
		or info.profile ~= (self.db and self.db.profile)
		or self:IsWorkBlocked("foreign_frame_mutation")
		or not self.LibChev.CanMutateOwnedRegion(frame)
	then
		return
	end
	local root = self:GetOwnedUIParent()
	if not self:CanAccessForeignFrame(root) then
		return
	end
	local w, h = Read(self, frame, "GetWidth"), Read(self, frame, "GetHeight")
	local rw, rh, rs =
		Read(self, root, "GetWidth"), Read(self, root, "GetHeight"), Read(self, root, "GetEffectiveScale")
	local fs, left, top =
		Read(self, frame, "GetEffectiveScale"), Read(self, frame, "GetLeft"), Read(self, frame, "GetTop")
	local rl, rb = Read(self, root, "GetLeft"), Read(self, root, "GetBottom")
	if
		not w
		or not h
		or not rw
		or not rh
		or not rs
		or not fs
		or not left
		or not top
		or not rl
		or not rb
		or rw <= 0
		or rh <= 0
		or rs <= 0
	then
		return
	end
	local x, y = ((left + w / 2) * fs / rs - rl) / rw, ((top - h / 2) * fs / rs - rb) / rh
	local _, cx, cy = self:FitWindowGeometry(w, h, rw, rh, fs / rs, x, y)
	if info.key and self.db and self.db.profile then
		self.db.profile.windowLayouts = type(self.db.profile.windowLayouts) == "table" and self.db.profile.windowLayouts
			or {}
		self.db.profile.windowLayouts[info.key] = { width = w, height = h, x = cx, y = cy }
	end
	info.x, info.y = cx, cy
end
function QT:ApplyWindowLayout(frame, restore)
	local info = rawget(self, "managedWindows") and self.managedWindows[frame]
	if
		not info
		or info.applying
		or self:IsWorkBlocked("foreign_frame_mutation")
		or not self.LibChev.CanMutateOwnedRegion(frame)
	then
		return false
	end
	local root = self:GetOwnedUIParent()
	if not self:CanAccessForeignFrame(root) then
		return false
	end
	local rw, rh = Read(self, root, "GetWidth"), Read(self, root, "GetHeight")
	if not rw or not rh or rw <= 0 or rh <= 0 then
		return false
	end
	local profile = self.db and self.db.profile
	local profileChanged = info.profile ~= profile
	local layouts = profile and profile.windowLayouts
	local saved = info.key and type(layouts) == "table" and layouts[info.key]
	if type(saved) ~= "table" then
		saved = nil
	end
	-- Geometry belongs to the profile that last completed restoration. Keep
	-- that identity until success so a deferred profile change survives later
	-- display events, and an unsaved profile cannot inherit the previous layout.
	restore = restore or profileChanged
	local relayout = restore or info.resetRequested
	info.applying = true
	if info.resetRequested or (profileChanged and not saved) then
		frame.userWidth, frame.userHeight = nil, nil
		frame:SetSize(math.max(info.width, frame.minimumWidth or 1), info.height)
		info.x, info.y, info.resetRequested = 0.5, 0.5, nil
	end
	if restore and saved then
		local w = math.max(info.minWidth or 1, math.min(1800, Number(saved.width, info.width)))
		local h = math.max(info.minHeight or 1, math.min(1200, Number(saved.height, info.height)))
		frame.userWidth, frame.userHeight = w, h
		frame:SetSize(w, h)
		info.x, info.y = Number(saved.x, 0.5), Number(saved.y, 0.5)
	end
	if frame.UpdateResizeBounds then
		frame:UpdateResizeBounds(frame.displaySession and #frame.displaySession.members or 1)
	end
	-- Reset/restoration can resize a hidden window without a drag event. Let
	-- content-sized dialogs and resizable views remeasure their owned children
	-- before fitting the resulting size to this display. The callback must not
	-- show the window or acknowledge its current request.
	if relayout and type(frame.LayoutManagedWindow) == "function" then
		local ok, err = pcall(frame.LayoutManagedWindow, frame)
		if not ok then
			info.applying = nil
			error(err)
		end
	end
	local w, h = Read(self, frame, "GetWidth"), Read(self, frame, "GetHeight")
	if not w or not h then
		info.applying = nil
		return false
	end
	local scale, x, y = self:FitWindowGeometry(w, h, rw, rh, self:GetWindowScale(), info.x, info.y)
	frame:SetScale(scale)
	if frame.UpdateResizeBounds then
		frame:UpdateResizeBounds(frame.displaySession and #frame.displaySession.members or 1)
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", root, "BOTTOMLEFT", x * rw / scale, y * rh / scale)
	frame:SetClampedToScreen(true)
	info.profile = profile
	info.applying = nil
	return true
end
function QT:RegisterManagedWindow(frame, key, minWidth, minHeight)
	if self:IsWorkBlocked("foreign_frame_mutation") or not self.LibChev.CanMutateOwnedRegion(frame) then
		return
	end
	self.managedWindows = rawget(self, "managedWindows") or setmetatable({}, { __mode = "k" })
	if self.managedWindows[frame] then
		return
	end
	self.managedWindows[frame] = {
		key = key,
		minWidth = minWidth,
		minHeight = minHeight,
		width = math.max(
			minWidth or 1,
			(Read(self, frame, "GetWidth") or 0) > 0 and Read(self, frame, "GetWidth") or 700
		),
		height = math.max(
			minHeight or 1,
			(Read(self, frame, "GetHeight") or 0) > 0 and Read(self, frame, "GetHeight") or 500
		),
	}
	self:ConfigureWindowController(frame)
	-- Do not write UISpecialFrames or another native registry. Input belongs to
	-- our frames; ordinary keys propagate, Escape dismisses only the top QT window.
	if type(frame.EnableKeyboard) == "function" and type(frame.SetPropagateKeyboardInput) == "function" then
		frame:EnableKeyboard(true)
		frame:SetPropagateKeyboardInput(true)
		frame:SetScript("OnKeyDown", function(_, keyPressed)
			if self:IsWorkBlocked("foreign_frame_mutation") or not self.LibChev.CanMutateOwnedRegion(frame) then
				return
			end
			frame:SetPropagateKeyboardInput(true)
			if keyPressed ~= "ESCAPE" then
				return
			end
			if frame.escapeAction then
				frame.escapeAction()
			elseif frame.close and type(frame.close.Click) == "function" then
				frame.close:Click()
			else
				self:DismissManagedWindow(frame, "escape")
			end
			frame:SetPropagateKeyboardInput(false)
		end)
	end
	if type(frame.HookScript) == "function" then
		frame:HookScript("OnShow", function()
			if self:IsWorkBlocked("foreign_frame_mutation") then
				return
			end
			if type(frame.SetPropagateKeyboardInput) == "function" then
				frame:SetPropagateKeyboardInput(true)
			end
			self:ApplyWindowLayout(frame)
		end)
	end
	self:ApplyWindowLayout(frame, true)
end
function QT:QueueWindowLayout(callback)
	if not self:IsWorkBlocked("foreign_frame_mutation") then
		callback()
		return
	end
	self:ScheduleRuntimeWork("foreign_frame_mutation", "window_layouts", callback,
		{ lifetime = "ui", delay = 0, reason = "fit windows to display" })
end
function QT:RefreshManagedWindowLayouts()
	self:QueueWindowLayout(function()
		for frame in pairs(rawget(self, "managedWindows") or {}) do
			if self.LibChev.CanMutateOwnedRegion(frame) then
				self:StopWindowDrag(frame, true)
				if frame.resizing then
					frame:StopMovingOrSizing()
					frame.resizing = nil
				end
				if frame.UpdateResizeBounds then
					frame.minimumWidth = nil
					frame:UpdateResizeBounds(frame.displaySession and #frame.displaySession.members or 1)
				end
				self:RefreshManagedWindow(frame, true)
			end
		end
	end)
end
function QT:ResetWindowLayouts()
	if self.db and self.db.profile then
		self.db.profile.windowLayouts = {}
	end
	for _, info in pairs(rawget(self, "managedWindows") or {}) do
		info.resetRequested = true
	end
	self:RefreshManagedWindowLayouts()
	self:Print(L("Window layouts reset."))
end
function QT:DISPLAY_SIZE_CHANGED()
	self:RefreshManagedWindowLayouts()
end
function QT:UI_SCALE_CHANGED()
	self:RefreshManagedWindowLayouts()
end
