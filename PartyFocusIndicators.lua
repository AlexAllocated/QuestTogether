-- Read-only native tracker observation; only QT-owned pips are positioned.
-- PartyNavigation remains the sole source of focus, consent and freshness.
local QT = _G.QuestTogether
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }

local function Read(a, frame, method, ...)
	local getter = a:GetAccessibleFrameMember(frame, method)
	if type(getter) ~= "function" then return end
	local ok, value = pcall(getter, frame, ...)
	if ok and a:CanAccessValue(value) then return value end
end
local function Number(a, frame, method)
	return a:SafeToNumber(Read(a, frame, method))
end
local function Visible(a, frame)
	return a:CanAccessForeignFrame(frame) and Read(a, frame, "IsVisible") == true
end
local function NotSliding(a, frame)
	local slide, readable = a:GetAccessibleFrameMember(frame, "slideInfo")
	return readable and slide == nil
end
local function Call(a, frame, method, ...)
	return a:CallOwnedUI(frame, method, ...)
end
local function Hide(a, pin)
	pin.name, pin.questID, pin.geometry = nil, nil, nil
	a:HideOwnedUI(pin.frame)
end

function QT:GetPartyQuestFocusRows()
	local rows = {}
	if not self.isEnabled or self.isLoggingOut or not self:GetPartyNavigationRoute() then return rows end
	for _, name in ipairs(self.partyMemberOrder or {}) do
		if not self:IsSelfSender(name) then
			local questID = self:NormalizeQuestID(self:GetPartyQuestFocusID(name))
			if questID then
				rows[#rows + 1] = { name = name, questID = questID, classFile = self:GetGroupedSenderClassFile(name) }
				if #rows == 4 then break end
			end
		end
	end
	return rows
end

function QT:GetPartyQuestFocusTrackerModules()
	local modules = {}
	for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "WorldQuestObjectiveTracker", "BonusObjectiveTracker" }) do
		local module = _G[name]
		if self:CanAccessForeignFrame(module) then modules[#modules + 1] = module end
	end
	return modules
end

local function HeaderGeometry(a, modules, questID)
	for _, module in ipairs(modules) do
		-- GetExistingBlock is a lookup, unlike GetBlock which allocates and lays
		-- out native frames. Never retain a block: Blizzard recycles them.
		if Visible(a, module) and NotSliding(a, module) then
			local block = Read(a, module, "GetExistingBlock", questID)
			if Visible(a, block) and a:GetAccessibleFrameMember(block, "used") == true
				and a:GetAccessibleFrameMember(block, "id") == questID
				and a:GetAccessibleFrameMember(block, "parentModule") == module
				and NotSliding(a, block) then
				local header = a:GetAccessibleFrameMember(block, "HeaderText")
				if Visible(a, header) then
					local left, top = Number(a, header, "GetLeft"), Number(a, header, "GetTop")
					local scale, height = Number(a, header, "GetEffectiveScale"), Number(a, header, "GetHeight")
					local level, strata = Number(a, block, "GetFrameLevel"), Read(a, block, "GetFrameStrata")
					if left and top and scale and scale > 0 and height and height > 0 and level
						and type(strata) == "string" and STRATA[strata] then
						return { left = left, top = top, scale = scale, height = height,
							level = math.min(10000, math.max(0, math.floor(level))) + 1, strata = strata }
					end
				end
			end
		end
	end
end

local function NewPin(a, root)
	local frame = a:CreateOwnedUIFrame(a.CreateOwnedWindowFrame, "Frame", root)
	Call(a, frame, "Hide")
	Call(a, frame, "EnableMouse", false)
	Call(a, frame, "SetSize", 7, 7)
	local function Circle(size, layer)
		local texture = Call(a, frame, "CreateTexture", nil, layer)
		Call(a, texture, "SetSize", size, size)
		Call(a, texture, "SetPoint", "CENTER")
		local mask = Call(a, frame, "CreateMaskTexture")
		Call(a, mask, "SetTexture", MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		Call(a, mask, "SetAllPoints", texture)
		Call(a, texture, "AddMaskTexture", mask)
		return texture
	end
	local border = Circle(7, "ARTWORK")
	Call(a, border, "SetColorTexture", 0.04, 0.04, 0.04, 1)
	return { frame = frame, border = border, dot = Circle(5, "OVERLAY") }
end

function QT:ResetPartyQuestFocusIndicators()
	local state = rawget(self, "partyFocusIndicatorState")
	if not state then return end
	state.rows = {}
	for index = 1, 4 do
		if state.pins[index] then Hide(self, state.pins[index]) end
	end
end

function QT:UpdatePartyQuestFocusIndicators()
	if not self.isEnabled or self.isLoggingOut or self:IsWorkBlocked("foreign_frame_mutation") then
		self:ResetPartyQuestFocusIndicators()
		return
	end
	local rows = self:GetPartyQuestFocusRows()
	local state = rawget(self, "partyFocusIndicatorState")
	if #rows == 0 then self:ResetPartyQuestFocusIndicators(); return end
	if not state then
		state = { rows = {}, pins = {} }
		self.partyFocusIndicatorState = state
	end
	state.rows = rows
	self:RefreshPartyQuestFocusIndicatorGeometry()
end

function QT:RefreshPartyQuestFocusIndicatorGeometry()
	local state = rawget(self, "partyFocusIndicatorState")
	if not state or #state.rows == 0 then return end
	if not self.isEnabled or self.isLoggingOut or self:IsWorkBlocked("foreign_frame_mutation") then
		self:ResetPartyQuestFocusIndicators()
		return
	end
	local root = self:GetOwnedUIParent()
	local left, bottom, scale = Number(self, root, "GetLeft"), Number(self, root, "GetBottom"), Number(self, root, "GetEffectiveScale")
	if not left or not bottom or not scale or scale <= 0 then
		self:ResetPartyQuestFocusIndicators()
		return
	end
	local modules, geometry, slots = self:GetPartyQuestFocusTrackerModules(), {}, {}
	local active, counts = {}, {}
	for index, row in ipairs(state.rows) do
		if self:GetPartyQuestFocusID(row.name) == row.questID then
			active[index] = true
			counts[row.questID] = (counts[row.questID] or 0) + 1
		end
	end
	for index, row in ipairs(state.rows) do
		if geometry[row.questID] == nil then geometry[row.questID] = HeaderGeometry(self, modules, row.questID) or false end
		local header = active[index] and geometry[row.questID]
		local pin = state.pins[index]
		if header then
			if not pin then pin = NewPin(self, root); state.pins[index] = pin end
			if self:CanMutateOwnedUI(pin.frame) and self:CanMutateOwnedUI(pin.dot) then
				slots[row.questID] = (slots[row.questID] or 0) + 1
				-- Blizzard leaves a 7px gap between its POI icon and the title.
				-- A vertical stack fits there without covering text or item buttons.
				local x = header.left - 3.5 - left * scale / header.scale
				local y = header.top - math.min(7, header.height / 2) - (slots[row.questID] - (counts[row.questID] + 1) / 2) * 7
					- bottom * scale / header.scale
				local s = header.scale / scale
				local old = pin.geometry
				if not old or old.x ~= x or old.y ~= y or old.scale ~= s or old.level ~= header.level or old.strata ~= header.strata then
					Call(self, pin.frame, "SetScale", s)
					Call(self, pin.frame, "SetFrameStrata", header.strata)
					Call(self, pin.frame, "SetFrameLevel", header.level)
					Call(self, pin.frame, "ClearAllPoints")
					Call(self, pin.frame, "SetPoint", "CENTER", root, "BOTTOMLEFT", x, y)
					pin.geometry = { x = x, y = y, scale = s, level = header.level, strata = header.strata }
				end
				if pin.name ~= row.name or pin.classFile ~= row.classFile then
					local r, g, b = self:GetWindowClassColor(row.classFile, 1)
					Call(self, pin.dot, "SetColorTexture", r, g, b, 1)
				end
				pin.name, pin.questID, pin.classFile = row.name, row.questID, row.classFile
				Call(self, pin.frame, "Show")
			else
				Hide(self, pin)
			end
		elseif pin then
			Hide(self, pin)
		end
	end
	for index = #state.rows + 1, 4 do
		if state.pins[index] then Hide(self, state.pins[index]) end
	end
end
