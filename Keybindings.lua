-- Binding actions reuse the same player-facing operations as menus and chat.
-- No default keys, binding overrides, or Blizzard input state are changed.
local QT = _G.QuestTogether

function QT:HandleKeybinding(action)
	if not self.isInitialized or type(self.db) ~= "table" or type(self.db.profile) ~= "table" or self.isLoggingOut then
		return false
	end
	if action == "stop_follow" then
		-- A live preview can temporarily own navigation. Stop what the player is
		-- currently following without changing their selected quest or waypoint.
		local controller = rawget(self, "nativePartyFocusOwner") or self:GetPartyFocusController()
		return controller:Stop() ~= false
	end
	if self:IsRuntimeRestricted() then
		return false
	end
	if action == "menu" then
		return self:OpenQuickMenu() ~= false
	elseif action == "party_log" then
		return self:TogglePartyQuestCompare() ~= false
	elseif action == "quest_partners" then
		return self:HandleQuestPartnerCommand("toggle") ~= false
	elseif action == "chat" then
		return self.API and type(self.API.OpenQTChatComposer) == "function" and self.API.OpenQTChatComposer() ~= false
			or false
	elseif action == "settings" then
		return self:OpenOptionsWindow() ~= false
	end
	return false
end
