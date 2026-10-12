local QT = _G.QuestTogether
local L = QT.Translate
local MAX_LINES, MAX_TEXT, MAX_FIELD = 128, 32768, 4096

local function PlainText(addon, value)
	if not addon:CanAccessValue(value) or type(value) ~= "string" then
		return ""
	end
	if #value > MAX_FIELD then
		return nil
	end
	local text = addon:SafeTrimString(value, "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|K.-|k", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("[%z\001-\008\011\012\014-\031\127]", "")
	-- No remaining markup may be interpreted by the reader's FontString.
	return addon:SafeTrimString(text:gsub("||", "|"):gsub("|", "||"), "")
end

function QT:ReadQuestDetails(questID)
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return nil, "restricted"
	end
	local link = self.API.GetQuestDetailsLink(questID)
	if not link then
		return nil, "unavailable"
	end
	local ok, result, reason = pcall(function()
		local data = self.API.GetTooltipDataForHyperlink(link)
		if not self:CanAccessTable(data) or not self:CanAccessTable(data.lines) then
			return nil, "unavailable"
		end
		local lines = data.lines
		if #lines > MAX_LINES then
			return nil, "too_large"
		end
		local copied, bytes = {}, 0
		for index = 1, #lines do
			local line = lines[index]
			if self:CanAccessTable(line) then
				local left = PlainText(self, line.leftText)
				local right = PlainText(self, line.rightText)
				if left == "" then
					left = PlainText(self, line.text)
				end
				if not left or not right then
					return nil, "too_large"
				end
				local text = left ~= "" and right ~= "" and (left .. "    " .. right) or (left .. right)
				if text ~= "" then
					bytes = bytes + #text + (#copied > 0 and 2 or 0)
					if bytes > MAX_TEXT then
						return nil, "too_large"
					end
					copied[#copied + 1] = text
				end
			end
		end
		if #copied == 0 then
			return nil, "empty"
		end
		local instanceID = self:SafeToNumber(data.dataInstanceID)
		if not instanceID or instanceID < 0 or instanceID ~= math.floor(instanceID) then
			instanceID = nil
		end
		return { text = table.concat(copied, "\n\n"), dataInstanceID = instanceID }
	end)
	if not ok then
		return nil, "unavailable"
	end
	return result, reason
end

local function Call(addon, region, method, ...)
	return addon:CallOwnedUI(region, method, ...)
end

local function Current(addon, frame, session, visible)
	return frame.session == session
		and session.active
		and addon:CanMutateOwnedUI(frame)
		and (not visible or Call(addon, frame, "IsVisible"))
end

local function SetScroll(addon, frame, offset)
	offset = math.max(0, math.min(frame.maximumScroll or 0, addon:SafeToNumber(offset) or 0))
	Call(addon, frame.scroll, "SetVerticalScroll", offset)
	frame.scrollOffset = offset
	addon:UpdateOwnedScrollBar(frame.scrollBar, offset, frame.maximumScroll or 0, frame.viewportHeight or 1, 36)
end

local function Layout(addon, frame)
	local width = Call(addon, frame, "GetWidth") - frame.contentInset * 2 - 24
	local height = Call(addon, frame, "GetHeight") - frame.contentTop - frame.contentBottom
	Call(addon, frame.scroll, "SetSize", width, height)
	Call(addon, frame.body, "SetWidth", width)
	local textHeight = math.max(1, addon:SafeToNumber(Call(addon, frame.body, "GetStringHeight")) or 1)
	Call(addon, frame.content, "SetSize", width, textHeight)
	Call(addon, frame.scrollBar, "SetHeight", height)
	frame.viewportHeight, frame.maximumScroll = height, math.max(0, textHeight - height)
	SetScroll(addon, frame, frame.scrollOffset)
end

local function Refresh(addon, frame, session)
	if not Current(addon, frame, session, true) then
		return false
	end
	local details, reason = addon:ReadQuestDetails(session.questID)
	if details then
		session.dataInstanceID, session.text = details.dataInstanceID, details.text
	elseif reason == "too_large" then
		session.timedOut = true
	end
	Call(
		addon,
		frame.body,
		"SetText",
		session.text or (session.timedOut and L("Quest details are unavailable.") or L("Loading quest details..."))
	)
	Layout(addon, frame)
	return details ~= nil
end

local function StopEvents(addon, frame)
	if addon.LibChev.CanMutateOwnedRegion(frame) then
		frame:UnregisterAllEvents()
	end
end

local function Retire(addon, frame)
	local session = frame.session
	frame.session = nil
	StopEvents(addon, frame)
	if session then
		addon:CancelRuntimeWorkOwner(session)
	end
end

local function Create(addon)
	local frame = addon:CreateScrollDialog(620, 500, L("Quest Details"))
	if not frame then
		return nil
	end
	addon.questDetailsWindow = frame
	local function New(kind, parent, template)
		return addon:CreateOwnedUIFrame(addon.CreateOwnedWindowFrame, kind, parent, template)
	end
	frame.scroll = New("ScrollFrame", frame)
	Call(addon, frame.scroll, "SetPoint", "TOPLEFT", frame.contentInset, -frame.contentTop)
	Call(addon, frame.scroll, "EnableMouseWheel", true)
	frame.content = New("Frame", frame.scroll)
	Call(addon, frame.scroll, "SetScrollChild", frame.content)
	frame.body = Call(addon, frame.content, "CreateFontString", nil, "OVERLAY", "GameFontHighlight")
	Call(addon, frame.body, "SetPoint", "TOPLEFT")
	Call(addon, frame.body, "SetJustifyH", "LEFT")
	Call(addon, frame.body, "SetJustifyV", "TOP")
	Call(addon, frame.body, "SetWordWrap", true)
	addon:AddScrollDialogLabel(frame, frame.body)
	frame.scrollBar = addon:CreateOwnedScrollBar(addon.CreateOwnedWindowFrame, frame, false, function(value)
		if addon:CanMutateOwnedUI(frame) then
			SetScroll(addon, frame, value)
		end
	end)
	Call(addon, frame.scrollBar, "SetPoint", "TOPLEFT", frame.scroll, "TOPRIGHT", 8, 0)
	Call(addon, frame.scroll, "SetScript", "OnMouseWheel", function(_, delta)
		if addon:CanMutateOwnedUI(frame) then
			SetScroll(addon, frame, (frame.scrollOffset or 0) - (addon:SafeToNumber(delta) or 0) * 36)
		end
	end)
	frame.close = New("Button", frame, "UIPanelCloseButton")
	Call(addon, frame.close, "SetPoint", "TOPRIGHT", -18, -10)
	Call(addon, frame.close, "SetSize", 28, 28)
	Call(addon, frame.close, "SetScript", "OnClick", function()
		addon:DismissManagedWindow(frame)
	end)
	frame.LayoutManagedWindow = function()
		if addon:CanMutateOwnedUI(frame) then
			Layout(addon, frame)
		end
	end
	Call(addon, frame, "SetScript", "OnEvent", function(_, event, identity)
		local session = frame.session
		if not session or not Current(addon, frame, session, true) or not addon:CanAccessValue(identity) then
			return
		end
		local id = addon:SafeToNumber(identity)
		if
			(event == "QUEST_DATA_LOAD_RESULT" and id == session.questID)
			or (event == "TOOLTIP_DATA_UPDATE" and (identity == nil or (id and id == session.dataInstanceID)))
		then
			addon:ScheduleRuntimeWork("foreign_frame_mutation", "quest_details_refresh", function()
				Refresh(addon, frame, session)
			end, {
				lifetime = "ui",
				owner = session,
				mode = "nextFrame",
				coalesce = true,
				reason = "quest details cache update",
			})
		end
	end)
	addon:ConfigureWindowController(frame, {
		suspend = function()
			addon:StopOwnedScrollBar(frame.scrollBar)
			StopEvents(addon, frame)
		end,
		dismiss = function()
			Retire(addon, frame)
		end,
		resume = function()
			local session = frame.session
			if session and Current(addon, frame, session, true) then
				Call(addon, frame, "RegisterEvent", "TOOLTIP_DATA_UPDATE")
				Call(addon, frame, "RegisterEvent", "QUEST_DATA_LOAD_RESULT")
				Refresh(addon, frame, session)
			end
		end,
	})
	frame.ready = true
	return frame
end

function QT:ShowQuestDetails(questID, fallbackTitle)
	local id = self:GetQuestDetailsAvailability(questID)
	if not id then
		return false
	end
	local ok, shown = pcall(function()
		local frame = rawget(self, "questDetailsWindow")
		if frame and not frame.ready then
			self:HideOwnedUI(frame)
			frame = nil
		end
		frame = frame or Create(self)
		if not frame or not self:CanMutateOwnedUI(frame) then
			return false
		end
		Retire(self, frame)
		local session = self:NewRuntimeWorkOwner()
		session.questID = id
		frame.session, frame.scrollOffset = session, 0
		local title = PlainText(self, self:NormalizeQuestLinkTitleText(fallbackTitle, id))
		Call(self, frame.title, "SetText", title and title ~= "" and title or L("Quest Details"))
		Call(self, frame.body, "SetText", L("Loading quest details..."))
		Layout(self, frame)
		self:ApplyScrollDialogTheme(frame)
		Call(self, frame, "RegisterEvent", "TOOLTIP_DATA_UPDATE")
		Call(self, frame, "RegisterEvent", "QUEST_DATA_LOAD_RESULT")
		Call(self, frame, "Show")
		Call(self, frame, "Raise")
		self.API.RequestLocalizedQuestTitle(id)
		Refresh(self, frame, session)
		self:ScheduleRuntimeWork("foreign_frame_mutation", "quest_details_timeout", function()
			if frame.session == session and session.active then
				session.timedOut = true
				Refresh(self, frame, session)
			end
		end, { lifetime = "ui", owner = session, delay = 10, reason = "quest details cache wait" })
		return true
	end)
	if not ok then
		local frame = rawget(self, "questDetailsWindow")
		if frame then
			Retire(self, frame)
			self:HideOwnedUI(frame)
		end
		if self.RecordDiagnosticError then
			self:RecordDiagnosticError("quest_details", shown)
		end
		return false
	end
	return shown == true
end
