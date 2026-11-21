-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local SafeText = Access.Text
local tostring = SafeText

function QuestTogether:Print(message)
	local text = "|cff33ff99QuestTogether|r: " .. self:SafeToString(message)
	local chatFrame = self:GetChatLogFrame()
	if not self:TryAddMessageToChatFrame(chatFrame, text) then
		print("QuestTogether:", self:SafeToString(message))
	end
end

function QuestTogether:PrintRaw(message)
	local text = self:SafeToString(message)
	local chatFrame = self:GetChatLogFrame()
	if not self:TryAddMessageToChatFrame(chatFrame, text) then
		print(text)
	end
end

function QuestTogether:PrintChatLogSystemMessage(message)
	self:PrintChatLogRaw("|cff33ff99QuestTogether|r: " .. self:SafeToString(message, ""))
end

function QuestTogether:PrintChatLogWarningMessage(message)
	local warningPrefix = "|cffff8800" .. L("Warning:") .. "|r"
	local iconTag = self.GetDefaultAnnouncementIconChatTag and self:GetDefaultAnnouncementIconChatTag(14) or ""
	if iconTag ~= "" then
		warningPrefix = iconTag .. warningPrefix
	end

	self:PrintChatLogRaw(warningPrefix .. " |cffffd200" .. self:SafeToString(message, "") .. "|r")
end

function QuestTogether:PrintChatLogInfoMessage(message)
	local infoPrefix = "|cff33ff99" .. L("Info:") .. "|r"
	local iconTag = self.GetDefaultAnnouncementIconChatTag and self:GetDefaultAnnouncementIconChatTag(14) or ""
	if iconTag ~= "" then
		infoPrefix = iconTag .. infoPrefix
	end

	self:PrintChatLogRaw(infoPrefix .. " |cffffd200" .. self:SafeToString(message, "") .. "|r")
end

function QuestTogether:PrintChatLogWarningDetailMessage(message)
	self:PrintChatLogRaw("|cffff8800 - |r" .. self:SafeToString(message, ""))
end

function QuestTogether:PrintChatLogInfoDetailMessage(message)
	self:PrintChatLogRaw("|cff33ff99 - |r" .. self:SafeToString(message, ""))
end

function QuestTogether:ShouldMirrorChatLogsToMainChat()
	if not self.db or not self.db.profile or self.db.profile.mirrorChatLogsToMainChat ~= true then
		return false
	end

	if self:GetResolvedChatLogDestination() ~= "separate" then
		return false
	end

	local chatFrame = self:FindVisibleQuestLogChatFrame()
	return self:IsChatFrameDocked(chatFrame)
end

function QuestTogether:GetMainChatFrame()
	return DEFAULT_CHAT_FRAME
end

function QuestTogether:GetConfiguredQuestLogChatFrameID()
	if not self.db then
		return nil
	end

	local configuredID = self:SafeToNumber(self.db.profile and self.db.profile.questLogChatFrameID)
	if configuredID and configuredID > 0 then
		return configuredID
	end

	return nil
end

function QuestTogether:SetConfiguredQuestLogChatFrameID(chatFrameID)
	if not self.db then
		return false
	end

	local numericID = self:SafeToNumber(chatFrameID)
	if numericID and numericID > 0 then
		if self.db.profile then
			self.db.profile.questLogChatFrameID = numericID
		end
	else
		if self.db.profile then
			self.db.profile.questLogChatFrameID = nil
		end
	end

	return true
end

function QuestTogether:FindQuestLogChatFrame()
	local chatWindowName = self.questLogWindowName or "QuestTogether"
	local configuredID = self:GetConfiguredQuestLogChatFrameID()
	if configuredID and self.API.GetChatFrameByID and self.API.GetChatWindowInfo then
		local configuredFrame = self.API.GetChatFrameByID(configuredID)
		local configuredName = self.API.GetChatWindowInfo(configuredID)
		if self:CanAccessForeignFrame(configuredFrame) and configuredName == chatWindowName then
			return configuredFrame, configuredID
		end
	end

	local maxWindows = self:SafeToNumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0
	for chatFrameID = 1, maxWindows do
		local frameName = self.API.GetChatWindowInfo and self.API.GetChatWindowInfo(chatFrameID)
		if frameName == chatWindowName then
			local chatFrame = nil
			if self.API.GetChatFrameByID then
				chatFrame = self.API.GetChatFrameByID(chatFrameID)
			end
			if not chatFrame then
				chatFrame = _G["ChatFrame" .. tostring(chatFrameID)]
			end
			if self:CanAccessForeignFrame(chatFrame) then
				self:SetConfiguredQuestLogChatFrameID(chatFrameID)
				return chatFrame, chatFrameID
			end
		end
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	return nil, nil
end

function QuestTogether:GetResolvedChatLogDestination()
	local chatFrame = self:FindVisibleQuestLogChatFrame()
	if chatFrame then
		return "separate"
	end

	return "main"
end

function QuestTogether:FindVisibleQuestLogChatFrame(excludedFrame)
	local chatWindowName = self.questLogWindowName or "QuestTogether"
	local maxWindows = self:SafeToNumber(self.API.GetNumChatWindows and self.API.GetNumChatWindows()) or 0

	for chatFrameID = 1, maxWindows do
		local frameName = self.API.GetChatWindowInfo and self.API.GetChatWindowInfo(chatFrameID)
		if frameName == chatWindowName then
			local chatFrame = nil
			if self.API.GetChatFrameByID then
				chatFrame = self.API.GetChatFrameByID(chatFrameID)
			end
			if not chatFrame then
				chatFrame = _G["ChatFrame" .. tostring(chatFrameID)]
			end
			if
				chatFrame
				and chatFrame ~= excludedFrame
				and self:CanAccessForeignFrame(chatFrame)
				and self:IsQuestLogChatFrameVisible(chatFrame)
			then
				self:SetConfiguredQuestLogChatFrameID(chatFrameID)
				return chatFrame, chatFrameID
			end
		end
	end

	return nil, nil
end

function QuestTogether:IsQuestLogChatFrame(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) or not chatFrame.GetID then
		return false
	end

	local expectedName = self.questLogWindowName or "QuestTogether"
	local frameID = chatFrame:GetID()
	local configuredID = self:GetConfiguredQuestLogChatFrameID()
	if configuredID and configuredID == frameID then
		return true
	end

	if self.API.GetChatWindowInfo then
		local frameName = self.API.GetChatWindowInfo(frameID)
		if frameName == expectedName then
			return true
		end
	end

	return false
end

function QuestTogether:IsQuestLogChatFrameVisible(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) or not self:IsQuestLogChatFrame(chatFrame) then
		return false
	end

	local frameShown = chatFrame.IsShown and chatFrame:IsShown()
	if frameShown then
		return true
	end

	local frameName = chatFrame.GetName and chatFrame:GetName()
	if not frameName or frameName == "" then
		return false
	end

	local chatTab = _G[frameName .. "Tab"]
	return self:CanAccessForeignFrame(chatTab) and chatTab.IsShown and chatTab:IsShown() or false
end

function QuestTogether:IsChatFrameDocked(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) then
		return false
	end

	if chatFrame.IsDocked then
		local ok, isDocked = pcall(chatFrame.IsDocked, chatFrame)
		if ok and type(isDocked) == "boolean" then
			return isDocked
		end
	end

	if type(chatFrame.isDocked) == "boolean" then
		return chatFrame.isDocked
	end

	local frameName = chatFrame.GetName and chatFrame:GetName()
	if frameName and frameName ~= "" then
		local chatTab = _G[frameName .. "Tab"]
		if self:CanAccessForeignFrame(chatTab) and type(chatTab.isDocked) == "boolean" then
			return chatTab.isDocked
		end
	end

	if FCFDock_GetChatFrames and GENERAL_CHAT_DOCK then
		local ok, dockedFrames = pcall(FCFDock_GetChatFrames, GENERAL_CHAT_DOCK)
		if ok and type(dockedFrames) == "table" then
			for _, dockedFrame in ipairs(dockedFrames) do
				if dockedFrame == chatFrame then
					return true
				end
			end
		end
	end

	return false
end

function QuestTogether:HandleQuestLogChatFrameClosed(chatFrame)
	if self.suppressQuestLogChatCloseHook then
		return false
	end
	if self.isLoggingOut then
		return false
	end
	if not self:IsQuestLogChatFrame(chatFrame) then
		return false
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	local evaluateClose = function()
		if self.isLoggingOut then
			return
		end

		local existingFrame, existingID = self:FindVisibleQuestLogChatFrame(chatFrame)
		if existingFrame then
			self:SetConfiguredQuestLogChatFrameID(existingID)
			self:Debugf(
				"chat",
				"Ignoring QuestTogether chat window close because a visible replacement exists id=%s",
				tostring(existingID)
			)
			if self.RefreshOptionsWindow then
				self:RefreshOptionsWindow()
			end
			return
		end

		self:Debug("QuestTogether chat window was closed; reverting chat log destination to main chat window", "chat")
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		if self.isEnabled and self.hasLoggedIn then
			self:PrintChatLogDestinationMessage()
		end
	end

	if self.API and self.API.Delay then
		self.API.Delay(0, evaluateClose)
	else
		evaluateClose()
	end

	return true
end

function QuestTogether:TryInstallChatWindowHooks()
	if self.chatWindowHooksInstalled then
		return
	end
	if type(hooksecurefunc) ~= "function" or type(FCF_Close) ~= "function" then
		return
	end

	hooksecurefunc("FCF_Close", function(frame, fallback)
		local closedFrame = fallback or frame
		QuestTogether:HandleQuestLogChatFrameClosed(closedFrame)
	end)

	self.chatWindowHooksInstalled = true
	self:Debug("Installed chat window hooks", "chat")
end

function QuestTogether:ActivateQuestLogChatFrame(chatFrame)
	if not self:CanAccessForeignFrame(chatFrame) or not chatFrame.GetID then
		return false
	end

	local chatTab = _G[chatFrame:GetName() .. "Tab"]
	local frameShown = chatFrame.IsShown and chatFrame:IsShown()
	local tabShown = self:CanAccessForeignFrame(chatTab) and chatTab.IsShown and chatTab:IsShown() or false
	if frameShown or tabShown then
		return true
	end

	if FCF_CheckShowChatFrame then
		FCF_CheckShowChatFrame(chatFrame)
		if self:CanAccessForeignFrame(chatTab) then
			FCF_CheckShowChatFrame(chatTab)
		end
	end
	if SetChatWindowShown then
		SetChatWindowShown(chatFrame:GetID(), true)
	end
	if FCF_DockFrame and FCFDock_GetChatFrames and GENERAL_CHAT_DOCK then
		FCF_DockFrame(chatFrame, (#FCFDock_GetChatFrames(GENERAL_CHAT_DOCK) + 1), true)
	end
	if FCF_FadeInChatFrame and FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
		local selectedFrame = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		if selectedFrame then
			FCF_FadeInChatFrame(selectedFrame)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.SetLastActiveWindow and self:CanAccessForeignFrame(chatFrame.editBox) then
		ChatFrameUtil.SetLastActiveWindow(chatFrame.editBox)
	end

	self:Debugf("chat", "Reactivated existing QuestTogether chat window id=%s", tostring(chatFrame:GetID()))
	return true
end

function QuestTogether:EnsureQuestLogChatFrame()
	if self:GetOption("showChatLogs") == false and self:GetOption("showQTChat") == false then
		return nil
	end
	local existingFrame, existingID = self:FindQuestLogChatFrame()
	if existingFrame then
		self:ActivateQuestLogChatFrame(existingFrame)
		return existingFrame, existingID
	end

	if not self.API.OpenChatWindow then
		return nil, nil
	end

	local chatFrame, chatFrameID = self.API.OpenChatWindow(self.questLogWindowName or "QuestTogether", true)
	if not self:CanAccessForeignFrame(chatFrame) then
		return nil, nil
	end

	if chatFrame.RemoveAllMessageGroups then
		chatFrame:RemoveAllMessageGroups()
	end
	if chatFrame.RemoveAllChannels then
		chatFrame:RemoveAllChannels()
	end
	self:SetConfiguredQuestLogChatFrameID(chatFrameID)
	self:Debugf("chat", "Created QuestTogether chat window id=%s", tostring(chatFrameID))
	return chatFrame, chatFrameID
end

function QuestTogether:CloseQuestLogChatFrame()
	local chatFrame, chatFrameID = self:FindQuestLogChatFrame()
	if not chatFrame then
		self:SetConfiguredQuestLogChatFrameID(nil)
		return false
	end
	if not self:CanAccessForeignFrame(chatFrame) then
		self:SetConfiguredQuestLogChatFrameID(nil)
		return false
	end

	if self.API.CloseChatWindow then
		self.suppressQuestLogChatCloseHook = true
		-- Closing chat windows can fail in restricted UI states; keep close flow resilient.
		local ok = pcall(self.API.CloseChatWindow, chatFrame)
		self.suppressQuestLogChatCloseHook = false
		if not ok then
			self:Debugf("chat", "Failed to close QuestTogether chat window id=%s", tostring(chatFrameID))
		end
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	self:Debugf("chat", "Closed QuestTogether chat window id=%s", tostring(chatFrameID))
	if self.isEnabled and self.hasLoggedIn then
		self:PrintChatLogDestinationMessage()
	end
	return true
end

function QuestTogether:ReconcileQuestLogChatDestination()
	if self:GetOption("showChatLogs") == false and self:GetOption("showQTChat") == false then
		self:CloseQuestLogChatFrame()
		return
	end
	local visibleFrame, visibleID = self:FindVisibleQuestLogChatFrame()
	if visibleFrame and visibleID then
		self:SetConfiguredQuestLogChatFrameID(visibleID)
		self:Debugf("chat", "Adopted existing QuestTogether chat window id=%s on login", tostring(visibleID))
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return true
	end

	self:SetConfiguredQuestLogChatFrameID(nil)
	return false
end

function QuestTogether:ApplyMainChatFontSizeToChatFrame(chatFrame)
	if
		not self:CanAccessForeignFrame(chatFrame)
		or not chatFrame.GetID
		or not self.API.GetChatWindowInfo
		or not self.API.SetChatWindowFontSize
	then
		return false
	end
	local mainChatFrame = self:GetMainChatFrame()
	if not self:CanAccessForeignFrame(mainChatFrame) or not mainChatFrame.GetID then
		return false
	end

	local mainChatID = mainChatFrame:GetID()
	local _, fontSize = self.API.GetChatWindowInfo(mainChatID)
	fontSize = self:SafeToNumber(fontSize)
	if not fontSize or fontSize <= 0 then
		return false
	end

	self.API.SetChatWindowFontSize(chatFrame, fontSize)
	self:Debugf(
		"chat",
		"Applied main chat font size=%s to QuestTogether chat frame id=%s",
		tostring(fontSize),
		tostring(chatFrame:GetID())
	)
	return true
end

function QuestTogether:GetChatLogFrame()
	if self:GetResolvedChatLogDestination() == "separate" then
		local chatFrame = self:EnsureQuestLogChatFrame()
		if chatFrame and chatFrame.AddMessage then
			return chatFrame
		end
		self:Debug("Separate QuestTogether chat window unavailable; falling back to main chat", "chat")
	end

	return self:GetMainChatFrame()
end

function QuestTogether:TryAddMessageToConfiguredChatLogFrames(message)
	local text = self:SafeToString(message, "")
	local primaryFrame = self:GetChatLogFrame()
	local wroteMessage = self:TryAddMessageToChatFrame(primaryFrame, text)

	if self:ShouldMirrorChatLogsToMainChat() then
		local mainChatFrame = self:GetMainChatFrame()
		if mainChatFrame and mainChatFrame ~= primaryFrame and self:TryAddMessageToChatFrame(mainChatFrame, text) then
			wroteMessage = true
		end
	end

	return wroteMessage
end

function QuestTogether:PrintChatLogRaw(message)
	local text = self:SafeToString(message, "")
	if not self:TryAddMessageToConfiguredChatLogFrames(text) then
		self:PrintRaw(text)
	end
end
