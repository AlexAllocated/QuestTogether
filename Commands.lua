-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Access = QuestTogether.NativeAccess
local SafeText, SafeMatch = Access.Text, Access.Match
local tostring = SafeText

BINDING_HEADER_QUESTTOGETHER = "QuestTogether"
BINDING_NAME_QUESTTOGETHER_PARTY_LOG = L("Toggle Party Quest Log")
BINDING_NAME_QUESTTOGETHER_MENU = L("Open QuestTogether menu")
BINDING_NAME_QUESTTOGETHER_QUEST_PARTNERS = L("Toggle Looking for Questing Partners")
BINDING_NAME_QUESTTOGETHER_FOLLOW_TARGET = L("Follow target's quest focus")
BINDING_NAME_QUESTTOGETHER_STOP_FOLLOW = L("Stop following quest focus")
BINDING_NAME_QUESTTOGETHER_CHAT = L("Open QuestTogether chat")
BINDING_NAME_QUESTTOGETHER_SETTINGS = L("Open QuestTogether settings")

function QuestTogether:OpenHudEditMode()
	-- This explicit UI action must not initialize or open Blizzard panels while
	-- restrictions are active, including encounter/map states outside combat.
	if self:IsRuntimeRestricted() or not self.API or type(self.API.GetEditModeManagerFrame) ~= "function" then
		return false
	end
	local manager = self.API.GetEditModeManagerFrame()
	if not self:CanAccessValue(manager) then
		return false
	end
	if manager == nil then
		if type(self.API.LoadEditMode) ~= "function" or self.API.LoadEditMode() ~= true then
			return false
		end
		manager = self.API.GetEditModeManagerFrame()
	end
	if not self:CanAccessForeignFrame(manager) or self:IsRuntimeRestricted() then
		return false
	end
	local canEnter = self:GetAccessibleFrameMember(manager, "CanEnterEditMode")
	if type(canEnter) ~= "function" then
		return false
	end
	local ok, allowed = pcall(canEnter, manager)
	if not ok or not self:CanAccessValue(allowed) or allowed ~= true or self:IsRuntimeRestricted() then
		return false
	end

	-- ShowUIPanel owns the panel lifecycle; its OnShow initializes Edit Mode.
	-- Calling EnterEditMode directly activates editing with no visible manager.
	if type(self.API.ShowUIPanel) ~= "function" or self.API.ShowUIPanel(manager) ~= true then
		return false
	end
	return self:CanAccessForeignFrame(manager, true)
end

function QuestTogether:InitializeSlashCommands()
	SLASH_QUESTTOGETHER1 = "/qt"
	SLASH_QUESTTOGETHER2 = "/questtogether"
	SLASH_QUESTTOGETHER3 = "/questogether"

	SlashCmdList.QUESTTOGETHER = function(input)
		QuestTogether:HandleSlashCommand(input or "")
	end

	SLASH_QUESTTOGETHERDUMP1 = "/qtd"
	SlashCmdList.QUESTTOGETHERDUMP = function(input)
		local normalizedInput = QuestTogether:SafeTrimString(input, "")
		if normalizedInput ~= "" then
			QuestTogether:HandleSlashCommand("dump " .. normalizedInput)
			return
		end
		QuestTogether:ShowDebugWindow()
	end
end

function QuestTogether:ParseBoolean(text)
	if not text then
		return nil
	end
	local normalized = string.lower(text)
	if normalized == "true" or normalized == "1" or normalized == "on" or normalized == "yes" then
		return true
	end
	if normalized == "false" or normalized == "0" or normalized == "off" or normalized == "no" then
		return false
	end
	return nil
end

function QuestTogether:PrintHelp()
	self:Print(L("Commands:"))
	self:Print(L("/qt <message> - Chat with QuestTogether players (recognized commands still run)"))
	self:Print(L("/qt options - Open the QuestTogether options window"))
	self:Print(L("/qt enable | disable - Enable or disable runtime behavior"))
	self:Print(L("/qt set <option> <value> - Set a boolean option (e.g. emoteOnQuestCompletion off)"))
	self:Print(L("/qt get <option> - Read an option value"))
	self:Print(L("/qt pql - Open Party Quest Log"))
	self:Print(L("/qt focus [name] - Follow a party member's quest focus (your target if omitted)"))
	self:Print(L("/qt unfollow - Stop following quest focus"))
	self:Print(L("/qt companions - Open your private recent companions list"))
	self:Print(L("/qt vip - Learn about VIP rewards and activate your cosmetics"))
	self:Print(L("/qt tip | hint - Show another QuestTogether tip"))
	self:Print("/qt resetlayout - " .. L("Reset window layout"))
	self:Print(L("/qt lfg [on|off|toggle|status] - Set or check Looking for Questing Partners (no argument toggles)"))
	self:Print(L("/qt notes | changelog | patchnotes - Open the latest welcome and patch notes"))
	self:Print(L("/qt scan - Rescan your quest log now"))
	self:Print(L("/qt help debug - Show debugging and developer commands"))
end

function QuestTogether:PrintDebugHelp()
	self:Print(L("Debugging and developer commands:"))
	self:PrintPreviewHelp()
	self:Print(L("/qt debug - Open the shared QuestTogether debug window"))
	self:Print(L("/qt devlogall [on|off|toggle] - Show or control dev all-announcements logging"))
	self:Print(L("/qt test - Run in-game unit tests, then open /qt dump filtered to TEST"))
	self:Print(L("/qt dump [clear|CATEGORY] - Open the shared QuestTogether debug window"))
	self:Print(L("/qt diagnostics [questID] - Copy client, runtime, and recent event diagnostics"))
	self:Print(L("/qtd - Shortcut for /qt dump"))
end

function QuestTogether:PrintPreviewHelp()
	self:Print(
		L("/qt preview share|join|partychat|bubble|discord|unfollow - Preview a QT dialog without changing settings")
	)
	self:Print(L("/qt preview compare - Preview Party Quest Log with mock data (no sharing)"))
	self:Print(L("/qt preview compare chains - Preview real quest chains with simulated teammates"))
	self:Print(L("/qt pqlpreview chains - Preview real quest chains with simulated teammates"))
	self:Print(L("/qt preview notes - Preview the welcome and patch-notes window"))
	self:Print(L("/qt preview announcement <text> - Run a local bubble preview for your current target"))
	self:Print(
		L(
			'/qt preview announcement "<player>" <text> - Run a local bubble preview for a nearby visible player (no target)'
		)
	)
	self:Print(L("Player names can be unquoted: Name-Realm, or First Surname on Forever."))
end

function QuestTogether:HandlePreviewCommand(input)
	local kind, arguments = SafeMatch(input, "^%s*(%S*)%s*(.-)$")
	kind = string.lower(kind or "")
	-- Only normalize the selector. Names, quotes and message text retain case.
	if kind == "announcement" then
		return self:PreviewBubbleAnnouncement(arguments or "")
	end
	if kind == "compare" and string.lower(arguments or "") == "chains" then
		return self:OpenPartyQuestComparePreview("chains")
	end
	if arguments and arguments ~= "" then
		self:PrintPreviewHelp()
		return false
	end
	if kind == "compare" then
		return self:OpenPartyQuestComparePreview()
	end
	if kind == "notes" or kind == "welcome" then
		return self:OpenReleaseNotes()
	end
	if
		kind == "share"
		or kind == "join"
		or kind == "partychat"
		or kind == "bubble"
		or kind == "discord"
		or kind == "unfollow"
	then
		return self:ShowDialogPreview(kind)
	end
	-- Empty/unknown preview commands are help, never outgoing QT chat.
	self:PrintPreviewHelp()
	return kind == "" or kind == "help"
end

function QuestTogether:PreviewBubbleAnnouncement(rest)
	if rest == nil or rest == "" then
		self:Print(L("Usage: /qt preview announcement <text>"))
		self:Print(L('   or: /qt preview announcement "<player>" <text> (without a target)'))
		return
	end
	if not self.SendBubbleAnnouncementTest then
		self:Print(L("Bubble test is unavailable."))
		return
	end

	local senderName = nil
	local testText = rest
	if not (self.API.UnitExists and self.API.UnitExists("target")) then
		local explicitSenderName, explicitText
		if string.sub(rest, 1, 1) == '"' then
			-- Quotes delimit a complete identity without consuming preview text.
			explicitSenderName, explicitText = SafeMatch(rest, '^"([^"]+)"%s+(.+)$')
		else
			explicitSenderName, explicitText = SafeMatch(rest, "^(%S+)%s+(.+)$")
			if
				explicitSenderName
				and self:UsesRegionalPlayerNames()
				and not string.find(explicitSenderName, "-", 1, true)
			then
				-- Native regional names have a first name and surname. Preserve
				-- legacy First-Surname inputs as a single identity token.
				local surname
				surname, explicitText = SafeMatch(explicitText, "^(%S+)%s+(.+)$")
				explicitSenderName = surname and (explicitSenderName .. " " .. surname) or nil
			end
		end
		senderName = self:SafeTrimString(explicitSenderName, "")
		testText = self:SafeTrimString(explicitText, "")
		if senderName == "" or testText == "" then
			self:Print(L('Usage without a target: /qt preview announcement "<player>" <text>'))
			return
		end
	end

	local ok, senderNameOrError = self:SendBubbleAnnouncementTest(testText, senderName)
	if not ok then
		self:Print(senderNameOrError)
		return
	end
	self:Print(L("Ran local bubble preview for ") .. tostring(self:GetShortDisplayName(senderNameOrError)))
	return
end

function QuestTogether:HandleSlashCommand(input)
	local compareCommand = string.lower(self:SafeTrimString(input, ""))
	if compareCommand == "partychatpreview" then
		return self:HandlePreviewCommand("partychat")
	elseif compareCommand:match("^pqlpreview%s+chains$") then
		return self:OpenPartyQuestComparePreview("chains")
	elseif compareCommand == "pql" or compareCommand == "compare" then
		self:ClosePartyQuestComparePreview()
		return self:OpenPartyQuestCompare()
	elseif compareCommand:match("^compare%s+debug$") then
		return self:HandlePreviewCommand("compare")
	end
	local command, rest = SafeMatch(input, "^%s*(%S*)%s*(.-)$")
	command = string.lower(command or "")

	if command == "resetlayout" then
		return self:ResetWindowLayouts()
	end
	if command == "companions" then
		return self:OpenRecentCompanions()
	end
	if command == "vip" then
		return self:OpenVIPWindow()
	end
	if command == "focus" then
		return self:HandlePartyQuestFocusCommand(rest)
	end
	if command == "unfollow" then
		return self:HandleKeybinding("stop_follow")
	end
	if command == "tip" or command == "hint" then
		if not self:ShowHint() then
			self:Print(L("Tips are unavailable right now."))
		end
		return
	end
	if command == "preview" then
		return self:HandlePreviewCommand(rest)
	end
	if command == "bubbletest" then
		return self:HandlePreviewCommand("announcement " .. (rest or ""))
	end
	if command == "discord" then
		return self:OpenDiscordSupport()
	end
	if command == "ad" then
		return self:HandleAdvertisementCommand(rest)
	end

	if command == "" or command == "options" then
		self:OpenOptionsWindow()
		return
	end
	if command == "notes" or command == "changelog" or command == "patchnotes" then
		return self:OpenReleaseNotes()
	end
	if command == "lfg" then
		return self:HandleQuestPartnerCommand(rest)
	end

	-- Help is presentation only; do not delegate topics to executable debug commands.
	if command == "help" then
		if string.lower(self:SafeTrimString(rest, "")) == "debug" then
			self:PrintDebugHelp()
		else
			self:PrintHelp()
		end
		return
	end

	-- Generic debug commands and their presentation belong to the shared controller.
	if (command == "diagnostics" or command == "diag") and string.lower(self:SafeTrimString(rest, "")) == "cursor" then
		local captured, reason = self:CapturePlayerNoteCursorDiagnostics()
		if not captured and reason then
			self:Print(reason)
		end
		return captured
	end
	if command == "debug" and rest ~= "" and rawget(self, "isLocalDeveloper") == true then
		return self:RequestRemoteDiagnostics(rest)
	end
	local debugCommand = command == "debuglog" and "dump" or command
	if (debugCommand == "dump" or debugCommand == "debug") and rest ~= "" then
		debugCommand = "dump " .. rest
	end
	local handled = self:GetDebugController():HandleCommand(debugCommand, rest)
	if handled then
		return
	end

	if command == "enable" then
		self:Enable()
		self:Print(L("QuestTogether enabled."))
		return
	end

	if command == "disable" then
		self:Disable()
		self:Print(L("QuestTogether disabled."))
		return
	end

	if command == "devlogall" then
		local flag = string.lower(rest or "")
		if flag == "" then
			self:Print("devLogAllAnnouncements = " .. tostring(self:GetOption("devLogAllAnnouncements")))
			return
		end
		if flag == "toggle" then
			self:SetOption("devLogAllAnnouncements", not self:GetOption("devLogAllAnnouncements"))
		else
			local boolValue = self:ParseBoolean(flag)
			if boolValue == nil then
				self:Print(L("Usage: /qt devlogall on|off|toggle"))
				return
			end
			self:SetOption("devLogAllAnnouncements", boolValue)
		end
		self:Print("devLogAllAnnouncements = " .. tostring(self:GetOption("devLogAllAnnouncements")))
		return
	end

	if command == "set" then
		local optionKey, optionValueText = SafeMatch(rest, "^(%S+)%s+(.+)$")
		if not optionKey or not optionValueText then
			self:Print(L("Usage: /qt set <option> <value>"))
			return
		end
		local boolValue = self:ParseBoolean(optionValueText)
		if boolValue == nil then
			self:Print(L("Only boolean values are supported here: true/false, on/off, 1/0"))
			return
		end
		if self:GetOption(optionKey) == nil then
			self:Print(L("Unknown option key: ") .. tostring(optionKey))
			return
		end
		if type(self.DEFAULTS.profile[optionKey]) ~= "boolean" then
			self:Print(L("This command only changes on/off settings."))
			return
		end
		self:SetOption(optionKey, boolValue)
		self:Print(optionKey .. " = " .. tostring(self:GetOption(optionKey)))
		if self.RefreshOptionsWindow then
			self:RefreshOptionsWindow()
		end
		return
	end

	if command == "get" then
		local optionKey = SafeMatch(rest, "^(%S+)$")
		if not optionKey then
			self:Print(L("Usage: /qt get <option>"))
			return
		end
		self:Print(optionKey .. " = " .. tostring(self:GetOption(optionKey)))
		return
	end

	if command == "scan" then
		self:ScanQuestLog()
		return
	end

	if command == "ping" then
		if
			rawget(self, "isLocalDeveloper") ~= true
			or not self.SendPingRequest
			or (rest ~= "" and string.lower(rest) ~= "global")
		then
			self:Print(L("Ping is unavailable."))
			return
		end

		local ok, requestIdOrError = self:SendPingRequest()
		if not ok then
			self:Print(tostring(requestIdOrError))
			return
		end

		self:PrintChatLogSystemMessage(L("Ping sent."))
		return
	end

	if not self:SendQTChannelChat(input) then
		self:Print(L("Unable to send QuestTogether chat. Make sure the addon is enabled and try again."))
	end
end
