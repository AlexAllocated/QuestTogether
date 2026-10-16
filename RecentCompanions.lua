-- Private group history. Never add these records to peers, profiles or messages.
local QT = _G.QuestTogether
local L = QT.Translate
local MAX_ENTRIES, RETENTION = 100, 90 * 24 * 60 * 60
local ROWS, ROW_HEIGHT = 8, 44

local function Now(addon)
	local now = addon:SafeToNumber(addon.API.GetServerTime and addon.API.GetServerTime())
	return now and now > 0 and now < math.huge and math.floor(now) or nil
end

local function Namespace(addon)
	local key = addon.API.GetPlayerNotesNamespace and addon.API.GetPlayerNotesNamespace()
	key = addon:SafeTrimString(key, "")
	local realm = addon:SafeStripWhitespace(addon.API.GetRealmName and addon.API.GetRealmName(), "")
	return key ~= "" and realm ~= "" and key .. ":" .. realm or nil
end

local function Store(addon, create)
	local db = rawget(addon, "db")
	local global = db and db.global
	if type(global) ~= "table" then return nil end
	local namespace = Namespace(addon)
	if not namespace then return nil end
	if type(global.recentCompanions) ~= "table" then
		if not create then return nil end
		global.recentCompanions = {}
	end
	if type(global.recentCompanions[namespace]) ~= "table" then
		if not create then return nil end
		global.recentCompanions[namespace] = {}
	end
	return global.recentCompanions[namespace]
end

local function Class(addon, value)
	value = addon:SafeTrimString(value, "")
	return #value <= 24 and value:match("^[A-Z]+$") and value or nil
end

local function Rows(addon, store, now)
	local rows = {}
	for name, record in pairs(store or {}) do
		local identity = addon:GetPlayerNoteIdentity(name)
		local stamp = type(record) == "table" and addon:SafeToNumber(record.lastGrouped)
		if identity == name and stamp and stamp > 0 and stamp <= now + 300 and now - stamp <= RETENTION then
			rows[#rows + 1] = { name = name, classFile = Class(addon, record.classFile), lastGrouped = stamp }
		else
			store[name] = nil
		end
	end
	table.sort(rows, function(a, b)
		if a.lastGrouped ~= b.lastGrouped then return a.lastGrouped > b.lastGrouped end
		return a.name < b.name
	end)
	for index = #rows, MAX_ENTRIES + 1, -1 do
		store[rows[index].name] = nil
		rows[index] = nil
	end
	return rows
end

function QT:GetRecentCompanions()
	local now = Now(self)
	return now and Rows(self, Store(self, false), now) or {}
end

function QT:ResetRecentCompanionObservation()
	self.recentCompanionObservation = nil
end

function QT:RecordRecentCompanions(previousOnly)
	if self.isEnabled ~= true or (self.isLoggingOut and not previousOnly) then return false end
	local db = rawget(self, "db")
	if type(db and db.global) ~= "table" then return false end
	local members = rawget(self, "partyMembers")
	if type(members) ~= "table" then return false end
	local namespace = Namespace(self)
	local observation = rawget(self, "recentCompanionObservation")
	-- Old roster tables survive zoning/disable. Only the exact roster observed
	-- in this enabled world lifetime may receive a departure timestamp.
	if previousOnly and (not observation or observation.roster ~= members or observation.namespace ~= namespace) then
		return false
	end
	local now = Now(self)
	if not now then return false end
	local store = Store(self, true)
	if not store then return false end
	local ownName = self:GetPlayerFullName()
	if not ownName then return false end
	local omitted = rawget(self, "recentCompanionOmissions")
	for name in pairs(omitted or {}) do
		if not members[name] then omitted[name] = nil end
	end
	for name, member in pairs(members) do
		local identity = self:GetPlayerNoteIdentity(name)
		if identity and identity ~= ownName and type(member) == "table" and not (omitted and omitted[identity]) then
			local previous = store[identity]
			store[identity] = {
				lastGrouped = now,
				classFile = Class(self, member.classFile) or (type(previous) == "table" and Class(self, previous.classFile)) or nil,
			}
		end
	end
	Rows(self, store, now)
	if not previousOnly then self.recentCompanionObservation = { roster = members, namespace = namespace } end
	self:RefreshRecentCompanionsWindow()
	return true
end

function QT:RemoveRecentCompanion(name)
	local identity, store = self:GetPlayerNoteIdentity(name), Store(self, false)
	if not identity or not store or not store[identity] then return false end
	store[identity] = nil
	local members = rawget(self, "partyMembers")
	if members and members[identity] then
		self.recentCompanionOmissions = rawget(self, "recentCompanionOmissions") or {}
		self.recentCompanionOmissions[identity] = true
	end
	self:RefreshRecentCompanionsWindow()
	return true
end

function QT:ClearRecentCompanions()
	local store = Store(self, false)
	if not store then return false end
	for name in pairs(store) do store[name] = nil end
	self.recentCompanionOmissions = {}
	for name in pairs(rawget(self, "partyMembers") or {}) do self.recentCompanionOmissions[name] = true end
	self:RefreshRecentCompanionsWindow()
	return true
end

local function Guard(addon, frame)
	return addon.isEnabled == true and not addon:IsWorkBlocked("foreign_frame_mutation")
		and addon:CanMutateOwnedUI(frame)
end

local function Current(addon, frame, session)
	return frame.session == session and session ~= nil and Guard(addon, frame) and frame:IsVisible()
end

local function Age(addon, stamp)
	local elapsed = math.max(0, (Now(addon) or stamp) - stamp)
	if elapsed < 60 then return L("Last grouped: just now") end
	if elapsed < 3600 then return string.format(L("Last grouped: %d min ago"), math.floor(elapsed / 60)) end
	if elapsed < 86400 then return string.format(L("Last grouped: %d hr ago"), math.floor(elapsed / 3600)) end
	return string.format(L("Last grouped: %d days ago"), math.floor(elapsed / 86400))
end

function QT:ShowRecentCompanionMenu(owner, name)
	local frame = rawget(self, "recentCompanionsWindow")
	local session = frame and frame.session
	local store = Store(self, false)
	if not frame or not Current(self, frame, session) or not Guard(self, owner)
		or not store or not store[name] then return false end
	return self.API.CreateContextMenu(owner, function(_, menu)
		if not Current(self, frame, session) or not Guard(self, owner) then return end
		self:PopulateChatLogSpeakerMenu(menu, owner, name)
		menu:CreateDivider()
		menu:CreateButton(L("Remove from recent companions"), function()
			if Current(self, frame, session) then self:RemoveRecentCompanion(name) end
		end)
	end)
end

function QT:RefreshRecentCompanionsWindow()
	local frame = rawget(self, "recentCompanionsWindow")
	if not frame or not Guard(self, frame) or not frame.session then return false end
	for _, region in ipairs(frame.regions) do
		if not Guard(self, region) then return false end
	end
	local entries = self:GetRecentCompanions()
	local offset = math.max(0, math.min(math.max(0, #entries - ROWS), math.floor(frame.offset or 0)))
	frame.offset = offset
	for index, row in ipairs(frame.rows) do
		local entry = entries[offset + index]
		row.identity = entry and entry.name or nil
		if entry then
			row.name:SetText(self:GetClassColorCode(entry.classFile) .. entry.name:gsub("|", "||") .. "|r")
			row.detail:SetText(Age(self, entry.lastGrouped))
			row:Show()
		else
			row:Hide()
		end
	end
	if #entries == 0 then frame.empty:Show() else frame.empty:Hide() end
	frame.clear:SetEnabled(#entries > 0)
	frame.count:SetText(string.format(L("%d recent companions"), #entries))
	self:UpdateOwnedScrollBar(frame.scrollBar, offset, math.max(0, #entries - ROWS), ROWS, 1)
	return true
end

local function Create(addon)
	local frame = addon:CreateScrollDialog(620, 530, L("Recent Companions"))
	if not frame then return nil end
	addon.recentCompanionsWindow = frame
	frame.regions, frame.rows = {}, {}
	local function Track(region)
		frame.regions[#frame.regions + 1] = region
		return region
	end
	local function New(kind, parent, template)
		return Track(addon:CreateOwnedUIFrame(addon.CreateOwnedWindowFrame, kind, parent or frame, template))
	end
	local function Label(parent, font)
		local label = Track(parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall"))
		label:SetJustifyH("LEFT")
		addon:AddScrollDialogLabel(frame, label)
		return label
	end
	frame.hint = Label(frame)
	frame.hint:SetPoint("TOPLEFT", frame.contentInset, -frame.contentTop)
	frame.hint:SetWidth(frame.contentWidth)
	frame.hint:SetText(L("People you grouped with. Private across your characters on this realm; never shared. Keeps the latest 100 for 90 days."))
	frame.list = New("Frame")
	frame.list:SetPoint("TOPLEFT", frame.hint, "BOTTOMLEFT", 0, -12)
	frame.list:SetSize(frame.contentWidth - 24, ROWS * ROW_HEIGHT)
	frame.list:EnableMouseWheel(true)
	frame.empty = Label(frame.list, "GameFontHighlight")
	frame.empty:SetPoint("TOPLEFT", 8, -16)
	frame.empty:SetWidth(frame.contentWidth - 40)
	frame.empty:SetText(L("No recent companions yet. Join a group to start your history."))
	for index = 1, ROWS do
		local row = New("Button", frame.list)
		frame.rows[index] = row
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetSize(frame.contentWidth - 24, ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local highlight = Track(row:CreateTexture(nil, "HIGHLIGHT"))
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 0.82, 0, 0.12)
		row.name = Label(row, "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", 8, -5)
		row.name:SetWidth(frame.contentWidth - 40)
		row.detail = Label(row)
		row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
		row.detail:SetWidth(frame.contentWidth - 40)
		row:SetScript("OnClick", function()
			if Current(addon, frame, frame.session) and row.identity then
				addon:ShowRecentCompanionMenu(row, row.identity)
			end
		end)
	end
	frame.scrollBar = Track(addon:CreateOwnedScrollBar(addon.CreateOwnedWindowFrame, frame, false, function(offset)
		if Current(addon, frame, frame.session) then
			frame.offset = math.floor(offset + 0.5)
			addon:RefreshRecentCompanionsWindow()
		end
	end))
	frame.scrollBar:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 8, 0)
	frame.scrollBar:SetHeight(ROWS * ROW_HEIGHT)
	frame.list:SetScript("OnMouseWheel", function(_, delta)
		if Current(addon, frame, frame.session) then
			frame.offset = (frame.offset or 0) - (addon:SafeToNumber(delta) or 0) * 3
			addon:RefreshRecentCompanionsWindow()
		end
	end)
	frame.count = Label(frame)
	frame.count:SetPoint("TOPLEFT", frame.list, "BOTTOMLEFT", 0, -12)
	frame.count:SetWidth(frame.contentWidth - 150)
	frame.clear = New("Button", frame, "UIPanelButtonTemplate")
	frame.clear:SetPoint("TOPRIGHT", frame.list, "BOTTOMRIGHT", 0, -8)
	frame.clear:SetSize(130, 24)
	frame.clear:SetText(L("Clear history"))
	frame.clear:SetScript("OnClick", function()
		local session = frame.session
		if not Current(addon, frame, session) then return end
		addon.API.CreateContextMenu(frame.clear, function(_, menu)
			if not Current(addon, frame, session) then return end
			menu:CreateTitle(L("Clear recent companions?"))
			menu:CreateButton(L("Clear history"), function()
				if Current(addon, frame, session) then addon:ClearRecentCompanions() end
			end)
		end)
	end)
	frame.help = Label(frame)
	frame.help:SetPoint("TOPLEFT", frame.count, "BOTTOMLEFT", 0, -14)
	frame.help:SetWidth(frame.contentWidth)
	frame.help:SetText(L("Select a player to whisper, invite, or manage a private note. History does not indicate whether someone is online."))
	frame.close = New("Button", frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", -18, -10)
	frame.close:SetSize(28, 28)
	frame.close:SetScript("OnClick", function() addon:DismissRecentCompanions() end)
	frame.LayoutManagedWindow = function()
		if not Guard(addon, frame) then return end
		for _, region in ipairs(frame.regions) do if not Guard(addon, region) then return end end
		frame:SetHeight(frame.contentTop + frame.hint:GetStringHeight() + 12 + ROWS * ROW_HEIGHT
			+ 12 + frame.count:GetStringHeight() + 14 + frame.help:GetStringHeight() + frame.contentBottom)
		addon:FitScrollDialog(frame)
	end
	addon:ConfigureWindowController(frame, {
		suspend = function() addon:StopOwnedScrollBar(frame.scrollBar) end,
		dismiss = function() frame.session = nil end,
		resume = function() addon:RefreshRecentCompanionsWindow() end,
	})
	return frame
end

function QT:OpenRecentCompanions()
	if self.isEnabled ~= true or self:IsWorkBlocked("foreign_frame_mutation") or not Store(self, true) then return false end
	local frame = rawget(self, "recentCompanionsWindow") or Create(self)
	if not frame or not Guard(self, frame) then return false end
	for _, region in ipairs(frame.regions) do if not Guard(self, region) then return false end end
	frame.session, frame.offset = {}, 0
	if not self:ApplyScrollDialogTheme(frame) then return false end
	self:RefreshRecentCompanionsWindow()
	frame:LayoutManagedWindow()
	frame:Show()
	frame:Raise()
	return true
end

function QT:DismissRecentCompanions()
	local frame = rawget(self, "recentCompanionsWindow")
	if frame then self:DismissManagedWindow(frame) end
end
