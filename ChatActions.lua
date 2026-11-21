-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local SafeText, SafeMatch = Access.Text, Access.Match
local tostring = SafeText

function QuestTogether:PrintConsoleAnnouncement(
	message,
	targetName,
	classFile,
	eventType,
	iconAsset,
	iconKind,
	locationInfo
)
	local speakerName = targetName
	local isRemoteSpeaker = false
	if speakerName == nil or speakerName == "" then
		speakerName = self:GetPlayerFullName() or self:GetPlayerName()
	end
	local resolvedClassFile = classFile
	if not resolvedClassFile or resolvedClassFile == "" then
		if speakerName ~= nil and speakerName ~= "" and self.NormalizeMemberName then
			local normalizedSpeaker = self:NormalizeMemberName(speakerName)
			local normalizedPlayer = self:NormalizeMemberName(self:GetPlayerFullName() or self:GetPlayerName() or "")
			isRemoteSpeaker = normalizedSpeaker and normalizedPlayer and normalizedSpeaker ~= normalizedPlayer and true
				or false
			if isRemoteSpeaker then
				resolvedClassFile = self.GetGroupedSenderClassFile and self:GetGroupedSenderClassFile(speakerName)
					or nil
			end
		end
		if (not resolvedClassFile or resolvedClassFile == "") and not isRemoteSpeaker then
			resolvedClassFile = self:GetPlayerClassFile()
		end
	end
	self:PrintChatLogRaw(
		self:BuildConsoleAnnouncementMessage(
			speakerName,
			message,
			resolvedClassFile,
			eventType,
			iconAsset,
			iconKind,
			locationInfo
		)
	)
end

function QuestTogether:ShowChatLogSpeakerMenu(ownerFrame, speakerName, firstAction)
	return self.API.CreateContextMenu(ownerFrame, function(_, rootDescription)
		self:PopulateChatLogSpeakerMenu(rootDescription, ownerFrame, speakerName, firstAction)
	end)
end

function QuestTogether:IsIgnoredPlayerName(playerName)
	local fullName = self:SafeTrimString(playerName, "")
	if fullName == "" or not self.API or not self.API.IsOnIgnoredList then
		return false
	end

	if self.API.IsOnIgnoredList(fullName) then
		return true
	end
	-- Hiding our surname is presentation only; never query social identity
	-- using a first-name-only label that could identify somebody else.
	if self:UsesRegionalPlayerNames() then
		return false
	end

	local shortName = self:GetShortDisplayName(fullName)
	if shortName ~= "" and shortName ~= fullName and self.API.IsOnIgnoredList(shortName) then
		return true
	end

	return false
end

function QuestTogether:InviteChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.InviteUnit then
		return false
	end

	local ok, sent = pcall(self.API.InviteUnit, fullName)
	return ok and sent == true
end

function QuestTogether:WhisperChatLogSpeaker(speakerName, ownerFrame)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.SendTell then
		return false
	end

	return self.API.SendTell(fullName, ownerFrame) == true
end

function QuestTogether:AddFriendFromChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.AddFriend then
		return false
	end

	self.API.AddFriend(fullName)
	return true
end

function QuestTogether:ToggleIgnoreChatLogSpeaker(speakerName)
	local fullName = tostring(speakerName or "")
	if fullName == "" or not self.API or not self.API.AddOrDelIgnore then
		return false
	end

	self.API.AddOrDelIgnore(fullName)
	if self.IGNORELIST_UPDATE then
		self:IGNORELIST_UPDATE()
	end
	return true
end

function QuestTogether:CompareQuestsWithChatLogSpeaker(speakerName)
	local fullName = self:NormalizeMemberName(speakerName) or tostring(speakerName or "")
	if fullName == "" or not self.OpenPlayerQuestCompare then
		return false
	end

	return self:OpenPlayerQuestCompare(fullName)
end

function QuestTogether:PopulateChatLogSpeakerMenu(rootDescription, ownerFrame, speakerName, firstAction)
	if not rootDescription then
		return false
	end

	local fullName = tostring(speakerName or "")
	local shortName = self:GetShortDisplayName(fullName)
	local isIgnored = false
	-- Context menus should stay usable even if ignored-list lookups fail for edge-case names.
	local ignoredOk, ignoredResult = pcall(function()
		return self:IsIgnoredPlayerName(fullName)
	end)
	if ignoredOk and ignoredResult then
		isIgnored = true
	end

	rootDescription:CreateTitle(shortName ~= "" and shortName or "QuestTogether")
	if self:IsPlayerLookingForQuestPartners(fullName) then
		rootDescription:CreateTitle(L("Looking for Questing Partners"))
	end

	if fullName ~= "" then
		if firstAction then
			firstAction(rootDescription)
		end
		local requestJoin = self.ShouldRequestPartyJoin and self:ShouldRequestPartyJoin(fullName)
		rootDescription:CreateButton(requestJoin and L("Request to Join") or L("Invite"), function()
			if requestJoin then
				self:RequestPartyJoin(fullName)
			else
				self:InviteChatLogSpeaker(fullName)
			end
		end)
		rootDescription:CreateButton(L("Whisper"), function()
			self:WhisperChatLogSpeaker(fullName, ownerFrame)
		end)
		rootDescription:CreateButton(L("Add Friend"), function()
			self:AddFriendFromChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton(isIgnored and L("Unignore") or L("Ignore"), function()
			self:ToggleIgnoreChatLogSpeaker(fullName)
		end)
		rootDescription:CreateButton(L("Compare Quests"), function()
			self:CompareQuestsWithChatLogSpeaker(fullName)
		end)
		if self:CanFindPlayerOnMap(fullName) then
			rootDescription:CreateButton(L("Find on Map"), function()
				self:FindPlayerOnMap(fullName)
			end)
		end
		self:PopulatePlayerNotesMenu(rootDescription, fullName)
	end

	self:PopulatePartyFocusMenu(rootDescription, fullName)
	return true
end

function QuestTogether:PopulateChatLogDestinationMenu(rootDescription)
	local isSeparate = self:GetOption("chatLogDestination") == "separate"
	local buttonText = isSeparate and L("Move QuestTogether Logs to Main Window")
		or L("Move QuestTogether Logs to Separate Window")
	rootDescription:CreateButton(buttonText, function()
		if self:IsRuntimeRestricted() then
			return
		end
		self:SetOption("chatLogDestination", isSeparate and "main" or "separate")
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
	end)
end

function QuestTogether:HandleChatLogSpeakerLink(_link, _text, linkData, contextData)
	local speakerName = linkData and linkData.options
	if not speakerName or speakerName == "" then
		return LinkProcessorResponse.Handled
	end
	if self.API and self.API.IsModifiedClick and self.API.IsModifiedClick("CHATLINK") then
		return LinkProcessorResponse.Handled
	end
	return self:ShowChatLogSpeakerMenu(contextData and contextData.frame or UIParent, speakerName)
			and LinkProcessorResponse.Handled
		or LinkProcessorResponse.Handled
end

function QuestTogether:HandleChatLogQuestLink(_link, text, linkData, contextData)
	if not self:CanAccessTable(linkData) then
		return LinkProcessorResponse.Handled
	end
	local questId = self:SafeToNumber(linkData.options)
	if not questId or questId <= 0 or questId ~= math.floor(questId) then
		return LinkProcessorResponse.Handled
	end
	if self.API and self.API.IsModifiedClick and self.API.IsModifiedClick("CHATLINK") then
		return LinkProcessorResponse.Handled
	end

	if not self:CanAccessValue(contextData) then
		return LinkProcessorResponse.Handled
	end
	if contextData ~= nil and not self:CanAccessTable(contextData) then
		return LinkProcessorResponse.Handled
	end
	if not self:ShowChatLogQuestMenu(contextData and contextData.frame, questId, self:SafeTrimString(text, "")) then
		self:Print(L("Quest menu is unavailable."))
	end
	return LinkProcessorResponse.Handled
end

function QuestTogether:GetQuestShareAvailability(questId)
	local id = self:SafeToNumber(questId)
	if not id or id <= 0 or id ~= math.floor(id) then
		return nil, L("Invalid quest."), "invalid"
	end
	if not self.isEnabled then
		return nil, L("Enable QuestTogether to share quests."), "disabled"
	end
	if self:IsWorkBlocked("quest_share") then
		return nil, L("Quest sharing is unavailable while restricted."), "restricted"
	end
	if not self.API.CanShareQuests or self.API.CanShareQuests() ~= true then
		return nil, L("Quest sharing is unavailable on this client."), "unsupported"
	end
	if not self.API.IsInGroup or self.API.IsInGroup() ~= true then
		return nil, L("Join a party to share quests."), "group"
	end
	local index = self:SafeToNumber(self.API.GetQuestLogIndexForSharing(id))
	if not index or index <= 0 or index ~= math.floor(index) then
		return nil, L("This quest is not available in your quest log."), "not_owned"
	end
	local pushable = self.API.IsPushableQuest(id)
	if not self:CanAccessValue(pushable) or type(pushable) ~= "boolean" then
		return nil, L("Quest shareability is unavailable."), "unknown"
	end
	if not pushable then
		return nil, L("This quest cannot be shared."), "not_shareable"
	end
	return index
end

function QuestTogether:ShareQuestFromChatLog(questId)
	-- A menu can outlive its initial eligibility check. Never retain its index
	-- or queue this manual action for a later party/restriction state.
	local index, reason = self:GetQuestShareAvailability(questId)
	if not index then
		self:Print(reason)
		return false
	end
	if not self.API.PushQuestToParty(index) then
		self:Print(L("Unable to share that quest."))
		return false
	end
	return true
end

function QuestTogether:GetQuestJournalAvailability(questId)
	local id = self:SafeToNumber(questId)
	if not id or id <= 0 or id ~= math.floor(id) then
		return nil, L("Invalid quest.")
	end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return nil, L("Opening the quest log is unavailable while restricted.")
	end
	if not self.API.CanOpenQuestJournal or self.API.CanOpenQuestJournal() ~= true then
		return nil, L("Opening the quest log is unavailable on this client.")
	end
	local index = self:SafeToNumber(self.API.GetQuestLogIndexForQuestID(id))
	if not index or index <= 0 or index ~= math.floor(index) then
		return nil, L("This quest is not in your quest log.")
	end
	return id
end

function QuestTogether:OpenQuestJournalFromChatLog(questId)
	-- Recheck the quest and restrictions when clicked; never open stale or
	-- deferred journal entries after the player has moved on.
	local id, reason = self:GetQuestJournalAvailability(questId)
	if not id then
		self:Print(reason)
		return false
	end
	if self.API.OpenQuestJournal(id) ~= true then
		self:Print(L("Unable to open that quest in your quest log."))
		return false
	end
	return true
end

function QuestTogether:GetQuestDetailsAvailability(questId)
	local id = self:SafeToNumber(questId)
	if not id or id <= 0 or id > 2147483647 or id ~= math.floor(id) then
		return nil, L("Invalid quest.")
	end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		return nil, L("Quest details are unavailable while restricted.")
	end
	if not self.API.CanOpenQuestDetails or self.API.CanOpenQuestDetails() ~= true then
		return nil, L("Quest details are unavailable on this client.")
	end
	return id
end

function QuestTogether:OpenQuestDetailsFromChatLog(questId, fallbackTitle)
	local id, reason = self:GetQuestDetailsAvailability(questId)
	if not id then
		self:Print(reason)
		return false
	end
	if self:ShowQuestDetails(id, fallbackTitle) ~= true then
		self:Print(L("Unable to show details for that quest."))
		return false
	end
	return true
end

function QuestTogether:PopulateChatLogQuestMenu(rootDescription, questId, fallbackTitle)
	local details = rootDescription:CreateButton(L("Quest Details"), function()
		self:OpenQuestDetailsFromChatLog(questId, fallbackTitle)
	end)
	local detailsID, detailsReason = self:GetQuestDetailsAvailability(questId)
	details:SetEnabled(detailsID ~= nil)
	details:SetTooltip(function(tooltip)
		if self:CanAccessForeignFrame(tooltip) then
			tooltip:SetText(
				self:AppendQuestIDToTooltipText(
					questId,
					detailsReason or L("Show the game's available information for this quest.")
				)
			)
		end
	end)
	local share = rootDescription:CreateButton(L("Share"), function()
		self:ShareQuestFromChatLog(questId)
	end)
	local index, reason = self:GetQuestShareAvailability(questId)
	share:SetEnabled(index ~= nil)
	share:SetTooltip(function(tooltip)
		if self:CanAccessForeignFrame(tooltip) then
			tooltip:SetText(self:AppendQuestIDToTooltipText(questId, reason or L("Share this quest with your party.")))
		end
	end)
	local journal = rootDescription:CreateButton(L("Open in Quest Log"), function()
		self:OpenQuestJournalFromChatLog(questId)
	end)
	local journalID, journalReason = self:GetQuestJournalAvailability(questId)
	journal:SetEnabled(journalID ~= nil)
	journal:SetTooltip(function(tooltip)
		if self:CanAccessForeignFrame(tooltip) then
			tooltip:SetText(
				self:AppendQuestIDToTooltipText(questId, journalReason or L("Open this quest in your quest log."))
			)
		end
	end)
	local compare = rootDescription:CreateButton(L("Party Quest Log"), function()
		if self.isEnabled and not self:IsRuntimeRestricted() then
			self:OpenPartyQuestCompare()
		end
	end)
	compare:SetEnabled(self.isEnabled == true)
end

function QuestTogether:ShowChatLogQuestMenu(ownerFrame, questId, fallbackTitle)
	return self.API.CreateContextMenu(ownerFrame, function(_, rootDescription)
		self:PopulateChatLogQuestMenu(rootDescription, questId, fallbackTitle)
	end)
end

function QuestTogether:HandleChatLogCoordLink(_link, _text, linkData, _contextData)
	local options = tostring(linkData and linkData.options or "")
	local mapID, coordX, coordY = SafeMatch(options, "^([^:]+):([^:]+):([^:]+)$")
	if not mapID or not coordX or not coordY then
		return LinkProcessorResponse.Handled
	end
	if self.API and self.API.IsModifiedClick and self.API.IsModifiedClick("CHATLINK") then
		return LinkProcessorResponse.Handled
	end

	if not self:OpenPingWaypoint(mapID, coordX, coordY) then
		self:Print(L("Unable to set that waypoint."))
	end
	return LinkProcessorResponse.Handled
end

function QuestTogether:TryInstallChatLogLinkHandler()
	self:InitializeChatLogPlayerTooltips()
	if self.chatLogLinkHandlerInstalled then
		return
	end
	if not LinkUtil or not LinkUtil.RegisterLinkHandler then
		return
	end

	local speakerRegistered = LinkUtil.IsLinkHandlerRegistered
		and LinkUtil.IsLinkHandlerRegistered(self.chatLogLinkType)
	if not speakerRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogSpeakerLink(link, text, linkData, contextData)
		end)
	end

	local questRegistered = LinkUtil.IsLinkHandlerRegistered
		and LinkUtil.IsLinkHandlerRegistered(self.chatLogQuestLinkType)
	if not questRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogQuestLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogQuestLink(link, text, linkData, contextData)
		end)
	end
	local coordRegistered = LinkUtil.IsLinkHandlerRegistered
		and LinkUtil.IsLinkHandlerRegistered(self.chatLogCoordLinkType)
	if not coordRegistered then
		LinkUtil.RegisterLinkHandler(self.chatLogCoordLinkType, function(link, text, linkData, contextData)
			return QuestTogether:HandleChatLogCoordLink(link, text, linkData, contextData)
		end)
	end
	local tipType = "questtogethertip"
	if not (LinkUtil.IsLinkHandlerRegistered and LinkUtil.IsLinkHandlerRegistered(tipType)) then
		LinkUtil.RegisterLinkHandler(tipType, function(_, _, linkData)
			if
				QuestTogether:CanAccessTable(linkData)
				and not (QuestTogether.API.IsModifiedClick and QuestTogether.API.IsModifiedClick("CHATLINK"))
			then
				QuestTogether:HandleHintActionLink(QuestTogether:SafeToString(linkData.options, ""))
			end
			return LinkProcessorResponse.Handled
		end)
	end
	self.chatLogLinkHandlerInstalled = true
end

function QuestTogether:PrintChatLogDestinationMessage()
	if self:GetOption("showChatLogs") == false then
		return
	end
	self:PrintConsoleAnnouncement(L("You will now see QuestTogether logs here."))
end

function QuestTogether:GetPlayerName()
	local playerName = self.API and self.API.UnitName and self.API.UnitName("player") or nil
	return playerName or L("Unknown")
end

function QuestTogether:IsSelfSender(sender)
	if not self:CanAccessValue(sender) or type(sender) ~= "string" or sender == "" then
		return false
	end
	local playerName = self:GetPlayerFullName()
	return playerName ~= nil and self:NormalizeMemberName(sender) == self:NormalizeMemberName(playerName)
end
