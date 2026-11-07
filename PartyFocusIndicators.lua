-- Read-only native tracker observation; only QT-owned pips are positioned.
-- PartyNavigation remains the sole source of focus, consent and freshness.
local QT = _G.QuestTogether
local L = QT.Translate
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT_SIZE, FOLLOW_SIZE, DOT_SPACING = 12, 14, 16
local BADGE_SIZE, BADGE_GAP = 12, 2
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
	pin.name, pin.questID, pin.geometry, pin.identity, pin.following, pin.follower = nil, nil, nil, nil, nil, nil
	a:HideOwnedUI(pin.tooltip)
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
						-- Read the actual native button edge: themes and UI scale can
						-- change its size. Keep our clickable markers clear of it.
						local poi = a:GetAccessibleFrameMember(block, "poiButton")
						local edge = left
						if Visible(a, poi) then
							local poiLeft, poiScale = Number(a, poi, "GetLeft"), Number(a, poi, "GetEffectiveScale")
							if not poiLeft or not poiScale or poiScale <= 0 then return end
							edge = math.min(left, poiLeft * poiScale / scale)
						elseif poi ~= nil then
							return
						end
						return { left = left, top = top, scale = scale, height = height,
							edge = edge,
							level = math.min(10000, math.max(0, math.floor(level))) + 1, strata = strata }
					end
				end
			end
		end
	end
end

local function NewPin(a, root)
	local frame = a:CreateOwnedUIFrame(a.CreateOwnedWindowFrame, "Button", root)
	Call(a, frame, "Hide")
	Call(a, frame, "EnableMouse", true)
	Call(a, frame, "RegisterForClicks", "LeftButtonUp")
	Call(a, frame, "SetSize", DOT_SIZE, DOT_SIZE)
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
	local border = Circle(DOT_SIZE, "ARTWORK")
	Call(a, border, "SetColorTexture", 0.04, 0.04, 0.04, 1)
	local badge = Call(a, frame, "CreateTexture", nil, "OVERLAY")
	Call(a, badge, "SetSize", BADGE_SIZE, BADGE_SIZE)
	Call(a, badge, "SetPoint", "RIGHT", frame, "LEFT", -BADGE_GAP, 0)
	Call(a, badge, "SetTexture", "Interface\\AddOns\\QuestTogether\\Media\\FocusFollower.tga")
	Call(a, badge, "Hide")
	return { frame = frame, border = border, dot = Circle(DOT_SIZE - 2, "OVERLAY"), badge = badge }
end

local function Current(a, pin, identity)
	return pin.identity == identity and pin.name ~= nil and a.isEnabled and not a.isLoggingOut
		and not a:IsWorkBlocked("foreign_frame_mutation") and a:CanMutateOwnedUI(pin.frame)
		and Call(a, pin.frame, "IsVisible") == true
		and a:GetPartyQuestFocusID(pin.name) == pin.questID
		and HeaderGeometry(a, a:GetPartyQuestFocusTrackerModules(), pin.questID) ~= nil
end

local function Tooltip(a, pin)
	if not pin.tooltip then
		local tip = a:CreateOwnedUIFrame(a.CreateOwnedWindowFrame, "Frame", a:GetOwnedUIParent())
		pin.tooltip = tip
		Call(a, tip, "Hide")
		Call(a, tip, "EnableMouse", false)
		Call(a, tip, "SetFrameStrata", "TOOLTIP")
		Call(a, tip, "SetFrameLevel", 140)
		Call(a, tip, "SetClampedToScreen", true)
		local background = Call(a, tip, "CreateTexture", nil, "BACKGROUND")
		Call(a, background, "SetAllPoints")
		Call(a, background, "SetColorTexture", 0.03, 0.03, 0.04, 0.97)
		pin.label = Call(a, tip, "CreateFontString", nil, "OVERLAY", "GameFontHighlight")
		Call(a, pin.label, "SetPoint", "TOPLEFT", 10, -8)
		Call(a, pin.label, "SetWidth", 260)
		Call(a, pin.label, "SetJustifyH", "LEFT")
		Call(a, pin.label, "SetWordWrap", true)
	end
	local name = (a:GetClassColorCode(pin.classFile) or "|cffffffff") .. pin.name:gsub("|", "||") .. "|r"
	local follower = a:IsPartyQuestFocusFollower(pin.name)
	local text = string.format(L("%s has this quest focused."), name)
	if follower then text = text .. "\n" .. L("Following your quest focus.") end
	if a:GetPartyQuestFollowTarget() == pin.name then
		text = text .. "\n" .. L("You are following this player.")
	elseif not follower then
		-- A direct follower cannot be followed back: that would form a loop.
		text = text .. "\n" .. L("Click to follow quest focus.")
	end
	Call(a, pin.label, "SetText", text)
	local height = a:SafeToNumber(Call(a, pin.label, "GetStringHeight"))
	if not height or height <= 0 then a:HideOwnedUI(pin.tooltip); return end
	Call(a, pin.tooltip, "SetSize", 280, height + 16)
	Call(a, pin.tooltip, "ClearAllPoints")
	Call(a, pin.tooltip, "SetPoint", "BOTTOMLEFT", pin.frame, "TOPRIGHT", 6, 6)
	Call(a, pin.tooltip, "Show")
end

local function Bind(a, pin)
	local identity = {}
	pin.identity = identity
	a:HideOwnedUI(pin.tooltip)
	Call(a, pin.frame, "SetScript", "OnEnter", function()
		if Current(a, pin, identity) then Tooltip(a, pin) end
	end)
	Call(a, pin.frame, "SetScript", "OnLeave", function()
		if pin.identity == identity then a:HideOwnedUI(pin.tooltip) end
	end)
	Call(a, pin.frame, "SetScript", "OnClick", function(_, button)
		if button == "LeftButton" and Current(a, pin, identity) then
			a:HideOwnedUI(pin.tooltip)
			a:RequestPartyQuestFocusFollow(pin.name)
		end
	end)
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
	local followTarget = self:GetPartyQuestFollowTarget()
	local active = {}
	for index, row in ipairs(state.rows) do
		if self:GetPartyQuestFocusID(row.name) == row.questID then
			active[index] = true
		end
	end
	for index, row in ipairs(state.rows) do
		if geometry[row.questID] == nil then geometry[row.questID] = HeaderGeometry(self, modules, row.questID) or false end
		local header = active[index] and geometry[row.questID]
		local pin = state.pins[index]
		if header then
			if not pin then pin = NewPin(self, root); state.pins[index] = pin end
			if self:CanMutateOwnedUI(pin.frame) and self:CanMutateOwnedUI(pin.dot) and self:CanMutateOwnedUI(pin.border)
				and self:CanMutateOwnedUI(pin.badge) then
				local follower = self:IsPartyQuestFocusFollower(row.name)
				-- Grow leftward along the title row, not vertically into adjacent
				-- quests whose objective lists may be collapsed or empty. Reserve
				-- each badge's width so it cannot cover the next player's dot.
				local x = header.edge - DOT_SIZE / 2 - 3 - (slots[row.questID] or 0)
					- left * scale / header.scale
				slots[row.questID] = (slots[row.questID] or 0) + DOT_SPACING + (follower and BADGE_SIZE + BADGE_GAP or 0)
				local y = header.top - math.min(7, header.height / 2)
					- bottom * scale / header.scale
				local s = header.scale / scale
				local old = pin.geometry
				if not old or old.x ~= x or old.y ~= y or old.scale ~= s or old.level ~= header.level or old.strata ~= header.strata then
					Call(self, pin.frame, "SetScale", s)
					-- Dots, follow rings and badges belong to the tracker layer so
					-- ordinary windows can cover both their artwork and hit targets.
					Call(self, pin.frame, "SetFrameStrata", header.strata)
					Call(self, pin.frame, "SetFrameLevel", header.level)
					Call(self, pin.frame, "ClearAllPoints")
					Call(self, pin.frame, "SetPoint", "CENTER", root, "BOTTOMLEFT", x, y)
					pin.geometry = { x = x, y = y, scale = s, level = header.level, strata = header.strata }
				end
				if pin.name ~= row.name or pin.questID ~= row.questID or pin.classFile ~= row.classFile then
					local r, g, b = self:GetWindowClassColor(row.classFile, 1)
					Call(self, pin.dot, "SetColorTexture", r, g, b, 1)
					Bind(self, pin)
				end
				pin.name, pin.questID, pin.classFile = row.name, row.questID, row.classFile
				local following = followTarget == row.name
				if pin.following ~= following then
					pin.following = following
					local size = following and FOLLOW_SIZE or DOT_SIZE
					Call(self, pin.border, "SetSize", size, size)
					Call(self, pin.border, "SetColorTexture", following and 0.5 or 0.04, following and 1 or 0.04, following and 0 or 0.04, 1)
					if pin.tooltip and Call(self, pin.tooltip, "IsShown") == true then Tooltip(self, pin) end
				end
				if pin.follower ~= follower then
					pin.follower = follower
					Call(self, pin.badge, follower and "Show" or "Hide")
					Call(self, pin.frame, "SetHitRectInsets", follower and -(BADGE_SIZE + BADGE_GAP) or 0, 0, 0, 0)
					if pin.tooltip and Call(self, pin.tooltip, "IsShown") == true then Tooltip(self, pin) end
				end
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
