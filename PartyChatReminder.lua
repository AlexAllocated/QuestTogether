local QT = _G.QuestTogether
local L = QT.Translate
local GRACE = 10

function QT:ClosePartyChatReminderPreview()
	self.partyChatReminderPreview = nil
	self:HideRetiredPartyRequestPrompt(rawget(self, "partyChatReminderPreviewFrame"), nil)
end

function QT:ShowPartyChatReminderPreview()
	if self:IsWorkBlocked("foreign_frame_mutation") then
		self:Print(L("Party chat preview is unavailable while UI restrictions are active."))
		return false
	end
	local request = { preview = true, names = { L("Example Player") .. " 1", L("Example Player") .. " 2" } }
	self.partyChatReminderPreview = request
	self:RenderPartyChatReminder(request)
	local frame = rawget(self, "partyChatReminderPreviewFrame")
	return frame ~= nil and frame.request == request
end

function QT:ResetPartyChatReminder()
	self.partyChatReminderState = nil
	self:HideRetiredPartyRequestPrompt(rawget(self, "partyChatReminderFrame"), nil)
end

-- One acknowledgement per newly unidentified member in this group session.
-- Repaints never acknowledge anything; a checked box is saved only on a button.
function QT:UpdatePartyChatReminder(members)
	local profile = self.db and self.db.profile
	if not self.isEnabled or self.isLoggingOut or not profile
		or self:GetOption("announceToNonQTParty") ~= true or self.suppressLocalAnnouncementDisplayDuringTests then
		self:ResetPartyChatReminder()
		return false
	end
	if self:GetOption("hidePartyChatReminder") == true then
		self:ResetPartyChatReminder()
		return true
	end
	if self:IsRuntimeRestrictionTypeActive("chat") then return false end
	-- Forwarding supplies already validated current members. An existing
	-- acknowledgement remains usable during combat without creating UI or
	-- bypassing chat restrictions; periodic discovery itself waits safely.
	if self:IsRuntimeRestricted() and not members then return false end
	members = members or self:GetNonQTPartyMembers()
	if not members then
		local s = rawget(self, "partyChatReminderState")
		if s then s.request = nil end
		self:RenderPartyChatReminder(nil)
		return false
	end
	local now = self:SafeToNumber(self.API.GetTime())
	if not now then return false end
	local s = rawget(self, "partyChatReminderState")
	if not s or s.profile ~= profile or now < s.at then
		s = { profile = profile, seen = {}, acknowledged = {}, at = now }
		self.partyChatReminderState = s
	end
	s.at = now
	local current, pending, ready = {}, {}, true
	for _, name in ipairs(members) do
		current[name] = true
		s.seen[name] = s.seen[name] or now
		if not s.acknowledged[name] then
			pending[#pending + 1] = name
			if now - s.seen[name] < GRACE then ready = false end
		end
	end
	for name in pairs(s.seen) do
		if not current[name] then s.seen[name], s.acknowledged[name] = nil, nil end
	end
	local key = table.concat(pending, "\n")
	if key == "" or not ready then s.request = nil
	elseif not s.request or s.request.key ~= key then
		s.request = { key = key, names = pending, profile = profile }
	end
	self:RenderPartyChatReminder(s.request)
	return #pending == 0
end

function QT:AcknowledgePartyChatReminder(request, hideFuture, turnOff)
	if request and request.preview then
		if rawget(self, "partyChatReminderPreview") ~= request then return false end
		self:ClosePartyChatReminderPreview()
		return true
	end
	local s = rawget(self, "partyChatReminderState")
	if not s or not request or s.request ~= request then return false end
	if self:IsRuntimeRestricted() or self:IsRuntimeRestrictionTypeActive("chat") then return false end
	local profile = self.db and self.db.profile
	local now = self:SafeToNumber(self.API.GetTime())
	if not self.isEnabled or self.isLoggingOut or self.suppressLocalAnnouncementDisplayDuringTests
		or s.profile ~= profile or request.profile ~= profile
		or not now or self:GetOption("announceToNonQTParty") ~= true then return false end
	if now < s.at then self:UpdatePartyChatReminder(); return false end
	-- These are explicit profile preferences, not consent for the displayed
	-- roster. Discovery can recognize a member between rendering and clicking;
	-- refreshing first would dismiss the prompt without saving the checked box.
	if hideFuture or turnOff then
		local changes = {}
		if hideFuture then changes.hidePartyChatReminder = true end
		if turnOff then changes.announceToNonQTParty = false end
		if not self:SetOptions(changes) then return false end
		self:ResetPartyChatReminder()
		self:RenderPartyChatReminder(nil)
		if self.RefreshOptionsWindow then self:RefreshOptionsWindow() end
		return true
	end
	-- An ordinary acknowledgement still applies only to the current roster,
	-- never to newly joined members or requests retired by discovery.
	local members = self:GetNonQTPartyMembers()
	if not members then return false end
	self:UpdatePartyChatReminder(members)
	if self:IsRuntimeRestricted() or self:IsRuntimeRestrictionTypeActive("chat")
		or rawget(self, "partyChatReminderState") ~= s or s.request ~= request then return false end
	for _, name in ipairs(request.names) do s.acknowledged[name] = true end
	s.request = nil
	self:RenderPartyChatReminder(nil)
	if self.RefreshOptionsWindow then self:RefreshOptionsWindow() end
	return true
end
