-- Optional toolbar integration. The display (or another addon) supplies LDB;
-- QT neither embeds it nor declares a load dependency on it.
local QT = _G.QuestTogether
local L = QT.Translate
local actions = { pql = true, menu = true, partners = true, settings = true, none = true }

function QT:IsDataBrokerAction(value)
	return self:CanAccessValue(value) and type(value) == "string" and actions[value] == true
end
function QT:GetDataBrokerAction(key)
	local value = self:GetOption(key)
	return self:IsDataBrokerAction(value) and value or self.DEFAULTS.profile[key]
end
function QT:GetDataBrokerActionOptions()
	return {
		{ value = "pql", text = L("Party Quest Log") },
		{ value = "menu", text = L("Menu") },
		{ value = "partners", text = L("Looking for Questing Partners") },
		{ value = "settings", text = L("Settings") },
		{ value = "none", text = L("None") },
	}
end

-- A separate adapter makes absent/late libraries testable without ever changing
-- LibStub or registering fixture launchers in the player's real registry.
function QT:GetDataBrokerLibrary()
	if QT.isRunningTests then return end
	local stub = rawget(_G, "LibStub")
	if type(stub) ~= "table" or not self:CanAccessTable(stub) then return end
	local ok, library = pcall(function()
		if type(stub.GetLibrary) == "function" then
			return stub:GetLibrary("LibDataBroker-1.1", true)
		end
	end)
	if ok and type(library) == "table" and self:CanAccessTable(library) then return library end
end

function QT:HandleDataBrokerClick(frame, button)
	if self.isRunningTests or not self.hasLoggedIn or self.isLoggingOut
		or self:IsRuntimeRestricted() or not self:CanAccessValue(button) then return false end
	local key = button == "LeftButton" and "brokerLeftClick" or button == "RightButton" and "brokerRightClick"
	if not key then return false end
	local action = self:GetDataBrokerAction(key)
	if action == "pql" then
		if not self.isEnabled then return false end
		return self:TogglePartyQuestCompare()
	elseif action == "partners" then
		return self:HandleQuestPartnerCommand("toggle")
	elseif action == "settings" then
		return self:OpenOptionsWindow()
	elseif action == "menu" then
		if not self:CanAccessForeignFrame(frame) or self:IsProtectedFrame(frame) then return false end
		return self:ShowMinimapMenu(frame)
	end
	return false
end

function QT:PopulateDataBrokerTooltip(tooltip)
	if self.isRunningTests or not self.hasLoggedIn or self.isLoggingOut or self:IsRuntimeRestricted()
		or not self:CanAccessForeignFrame(tooltip) or self:IsProtectedFrame(tooltip) then return false end
	local addLine = self:GetAccessibleFrameMember(tooltip, "AddLine")
	if type(addLine) ~= "function" then return false end
	local labels = {}
	for _, action in ipairs(self:GetDataBrokerActionOptions()) do labels[action.value] = action.text end
	-- The display owns clearing, positioning, showing and hiding its tooltip.
	-- Use its public content API only; never install QT fields or scripts on it.
	local lines = {
		L("QuestTogether"),
		self.isEnabled and L("Enabled") or L("Disabled"),
		L("Looking for Questing Partners") .. ": " .. (self:GetOption("lookingForQuestPartners") and L("On") or L("Off")),
		" ",
		string.format(L("Left-click: %s"), labels[self:GetDataBrokerAction("brokerLeftClick")]),
		string.format(L("Right-click: %s"), labels[self:GetDataBrokerAction("brokerRightClick")]),
	}
	for i, line in ipairs(lines) do
		local ok = pcall(addLine, tooltip, line, 1, i == 1 and 0.82 or 1, i == 1 and 0 or 1, true)
		if not ok then return false end
	end
	return true
end

function QT:RefreshDataBroker()
	if not self.hasLoggedIn or not self.db or self.isLoggingOut or self:IsRuntimeRestricted() then return false end
	local state = rawget(self, "dataBrokerState")
	if state and state.busy then return false end
	if not state then state = {}; self.dataBrokerState = state end
	-- Registry creation and attribute writes synchronously call other addons.
	-- Fence re-entry and isolate their errors from QT settings/lifecycle work.
	state.busy = true
	local ok, updated = pcall(function()
		local looking = self.isEnabled and self:GetOption("lookingForQuestPartners") == true
		local text = not self.isEnabled and L("Disabled") or looking and L("Looking for Questing Partners") or L("QuestTogether")
		local shade = self.isEnabled and 1 or 0.5
		if not state.object then
			local library = self:GetDataBrokerLibrary()
			if not library or type(library.NewDataObject) ~= "function"
				or type(library.GetDataObjectByName) ~= "function" then return false end
			local existing = library:GetDataObjectByName("QuestTogether")
			if existing then
				-- A callback may have failed after LDB installed our own candidate.
				-- Never adopt or overwrite a similarly named third-party object.
				if existing ~= state.candidate then return false end
				state.object = existing
			else
				local object = {
					type = "launcher", label = L("QuestTogether"), text = text, tocname = "QuestTogether",
					icon = self:GetMinimapIdentityTexture(), iconR = shade, iconG = shade, iconB = shade,
					OnClick = function(frame, button)
						local success, result = pcall(self.HandleDataBrokerClick, self, frame, button)
						return success and result
					end,
					OnTooltipShow = function(tooltip)
						local success, result = pcall(self.PopulateDataBrokerTooltip, self, tooltip)
						return success and result
					end,
				}
				state.candidate = object
				state.object = library:NewDataObject("QuestTogether", object)
				if not state.object then return false end
			end
			state.candidate = nil
		end
		local object = state.object
		object.icon = self:GetMinimapIdentityTexture()
		object.text = text
		object.iconR, object.iconG, object.iconB = shade, shade, shade
		return true
	end)
	state.busy = nil
	return ok and updated == true
end
