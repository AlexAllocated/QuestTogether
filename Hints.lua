-- Approved player-facing copy. Stable IDs keep the saved pool independent of wording and locale.
local QT = _G.QuestTogether
local L = QT.Translate

-- Link payloads name fixed navigation actions, never commands, method names or
-- setting values. Recheck the current client and restrictions on every click.
local function SettingsAction(label, category)
	return {
		label = label,
		run = function(addon)
			return addon:OpenSettingsCategory(category)
		end,
	}
end
local hintActions = {
	settings = SettingsAction(function()
		return L("Settings")
	end, "general"),
	announcements = SettingsAction(function()
		return L("What to Announce")
	end, "announcements"),
	where_to_announce = SettingsAction(function()
		return L("Where to Announce")
	end, "whereToAnnounce"),
	quest_plates = SettingsAction(function()
		return L("Quest Plates")
	end, "questPlates"),
	player_plates = SettingsAction(function()
		return L("Player Plates")
	end, "playerPlates"),
	player_locations = SettingsAction(function()
		return L("Player Locations")
	end, "playerLocations"),
	groups = SettingsAction(function()
		return L("Groups & Sharing")
	end, "groups"),
	accessibility = SettingsAction(function()
		return L("Accessibility")
	end, "accessibility"),
	profiles = SettingsAction(function()
		return L("Profiles")
	end, "profiles"),
	developer = SettingsAction(function()
		return L("Developer")
	end, "developer"),
	experimental = SettingsAction(function()
		return L("Experimental")
	end, "experimental"),
	party_log = {
		label = function()
			return L("Party Quest Log")
		end,
		run = function(addon)
			return addon:OpenPartyQuestCompare()
		end,
	},
	patch_notes = {
		label = function()
			return L("Patch Notes")
		end,
		run = function(addon)
			return addon:OpenReleaseNotes()
		end,
	},
	support = {
		label = function()
			return L("Discord — Feedback & Support")
		end,
		run = function(addon)
			return addon:OpenDiscordSupport()
		end,
	},
	debug = {
		label = function()
			return L("Open Debug Window")
		end,
		run = function(addon)
			return addon:ShowDebugWindow()
		end,
	},
	hud_edit = {
		label = function()
			return L("Open HUD Edit Mode")
		end,
		feature = "hud",
		run = function(addon)
			return addon:OpenHudEditMode()
		end,
	},
	keybindings = {
		label = function()
			return L("Key Bindings")
		end,
		run = function(addon)
			return addon.API.OpenKeyBindings()
		end,
	},
}

local function HintAction(addon, actionID)
	if not addon:CanAccessValue(actionID) or type(actionID) ~= "string" or #actionID > 32 then
		return nil
	end
	return hintActions[actionID]
end

function QT:GetHintActionInfo(actionID)
	local action = HintAction(self, actionID)
	if not action then
		return nil
	end
	if action.feature then
		local capabilities = self.API.GetHintCapabilities and self.API.GetHintCapabilities()
		if type(capabilities) ~= "table" or capabilities[action.feature] ~= true then
			return nil
		end
	end
	return { id = actionID, label = action.label(), tooltip = L("Click to open.") }
end

function QT:ParseHintActionLink(link)
	if not self:CanAccessValue(link) or type(link) ~= "string" or #link > 64 then
		return nil
	end
	local actionID = link:match("^questtogethertip:([a-z_]+)$")
	return HintAction(self, actionID) and actionID or nil
end

function QT:HandleHintActionLink(actionID)
	local action = HintAction(self, actionID)
	if
		not action
		or not self:GetHintActionInfo(actionID)
		or not self.hasLoggedIn
		or self.isLoggingOut
		or self:IsRuntimeRestricted()
	then
		return false
	end
	local ok, opened = pcall(action.run, self)
	return ok and opened ~= false
end

function QT:FormatHintEntry(hint)
	local text = self:FormatHint(hint.text)
	for _, actionID in ipairs(hint.actions or {}) do
		local action = self:GetHintActionInfo(actionID)
		if action then
			text = text .. " |cffffd100|Hquesttogethertip:" .. action.id .. "|h[" .. action.label .. "]|h|r"
		end
	end
	return text
end

function QT:GetHintCatalog()
	return {
		{
			id = "hint001",
			actions = { "settings" },
			text = L("Type /qt to open QuestTogether's settings, or /qt help to see its commands."),
		},
		{
			id = "hint002",
			actions = { "party_log" },
			text = L(
				"Left-click the QT minimap button to open or close Party Quest Log. Right-click it for the quick menu."
			),
			menu = true,
		},
		{
			id = "hint003",
			actions = { "groups" },
			text = L("Shift-click the QT minimap button to toggle Looking for Questing Partners."),
		},
		{
			id = "hint004",
			actions = { "groups" },
			text = L("A glowing QT minimap button is a reminder that you are currently looking for questing partners."),
		},
		{
			id = "hint005",
			text = L("Drag the QT minimap button around the minimap to put it somewhere more convenient."),
		},
		{
			id = "hint006",
			text = L(
				"Hover over the QT minimap button to check your partner status, chat scope, nearby range, and location-sharing setting."
			),
		},
		{
			id = "hint007",
			actions = { "settings" },
			text = L("Hidden your QT minimap button? Open /qt options and enable Show Minimap Icon to bring it back."),
		},
		{
			id = "hint008",
			actions = { "keybindings" },
			text = L(
				"Find QuestTogether in WoW's Key Bindings to assign shortcuts for its windows, menu, chat, and questing-partner status."
			),
		},
		{
			id = "hint009",
			actions = { "keybindings" },
			text = L("Bind Toggle Party Quest Log to open or close your party's quest comparison with one key."),
		},
		{
			id = "hint010",
			actions = { "keybindings" },
			text = L("Bind Open QuestTogether Menu to reach the quick menu even when the minimap button is hidden."),
			menu = true,
		},
		{
			id = "hint011",
			actions = { "keybindings" },
			text = L("Bind Open QuestTogether Chat to start typing a QT message without entering /qt first."),
		},
		{
			id = "hint012",
			actions = { "settings" },
			text = L(
				"QT's settings home page summarizes your current preferences and links to the relevant settings pages."
			),
		},
		{ id = "hint013", actions = { "settings" }, text = L("Hover over QT settings to see what each option does.") },
		{
			id = "hint014",
			actions = { "party_log" },
			text = L("Type /qt pql to see your party's quests side by side."),
		},
		{
			id = "hint015",
			actions = { "party_log" },
			text = L(
				"Party Quest Log includes quests your companions have even when those quests are missing from your own log."
			),
		},
		{
			id = "hint016",
			actions = { "party_log" },
			text = L(
				"Click a quest row in Party Quest Log to expand everyone's objectives and progress. Click again to collapse it."
			),
		},
		{
			id = "hint017",
			actions = { "party_log" },
			text = L(
				"You can keep several quests expanded in Party Quest Log to compare their objectives at the same time."
			),
		},
		{ id = "hint018", actions = { "party_log" }, text = L("Search Party Quest Log by quest name or quest ID.") },
		{
			id = "hint019",
			actions = { "party_log" },
			text = L("Party Quest Log can search quest names received from players using another language, too."),
		},
		{
			id = "hint020",
			actions = { "party_log" },
			text = L(
				"Combine quest ownership, party progress, and available-action filters to find what your group should do next."
			),
			menu = true,
		},
		{
			id = "hint021",
			actions = { "party_log" },
			text = L("Use the Everyone has the quest filter to find quests you can work on together."),
			menu = true,
		},
		{
			id = "hint022",
			actions = { "party_log" },
			text = L(
				"Use the Someone is missing the quest filter to check that everyone has picked up a quest before heading out."
			),
			menu = true,
		},
		{
			id = "hint023",
			actions = { "party_log" },
			text = L("Use the Quests I don't have filter to find quests your companions have picked up without you."),
			menu = true,
		},
		{
			id = "hint024",
			actions = { "party_log" },
			text = L("Use the Everyone ready filter to find quests the whole group can turn in."),
			menu = true,
		},
		{
			id = "hint025",
			actions = { "party_log" },
			text = L("Use the Someone is ready filter to spot quests where part of the group may still need help."),
			menu = true,
		},
		{
			id = "hint026",
			actions = { "party_log" },
			text = L("Use the Can share and Can request share filters to find quests your party can exchange."),
			feature = "sharing",
			menu = true,
		},
		{
			id = "hint027",
			actions = { "party_log" },
			text = L(
				"Party Quest Log remembers your filters per profile. Press Reset to clear both the filters and the search."
			),
		},
		{
			id = "hint028",
			actions = { "party_log" },
			text = L(
				"Loading or Unknown in Party Quest Log does not mean a player is missing the quest; QT does not have their answer yet."
			),
		},
		{
			id = "hint029",
			actions = { "party_log" },
			text = L(
				"Your own Party Quest Log column updates as you quest. Refresh requests updated quest lists from the other players."
			),
		},
		{
			id = "hint030",
			actions = { "party_log" },
			text = L(
				"Click a player's heading in Party Quest Log and choose Refresh this player to update just their column."
			),
			menu = true,
		},
		{
			id = "hint031",
			actions = { "party_log" },
			text = L(
				"Enable Auto-refresh while open in Party Quest Log's Filters menu to request updated quest lists periodically."
			),
			menu = true,
		},
		{
			id = "hint032",
			actions = { "party_log" },
			text = L(
				"Check the update time beneath a player's name in Party Quest Log before relying on their last reported progress."
			),
		},
		{
			id = "hint033",
			text = L(
				"Choose Compare Quests from a player's QT name or map-dot menu to compare your quest lists before grouping up."
			),
			menu = true,
		},
		{
			id = "hint034",
			actions = { "party_log" },
			text = L(
				"Drag Party Quest Log's bottom-right corner to resize it. Widen the window to show more columns at once."
			),
		},
		{
			id = "hint035",
			actions = { "party_log" },
			text = L("Party Quest Log can scroll sideways when your group's columns do not fit in the window."),
		},
		{
			id = "hint036",
			actions = { "party_log" },
			text = L("Use Share in Party Quest Log to offer an eligible quest to party members who are missing it."),
			feature = "sharing",
		},
		{
			id = "hint037",
			actions = { "party_log" },
			text = L("Use Request Share in Party Quest Log to ask a party member for a quest you do not have."),
			feature = "sharing",
		},
		{
			id = "hint038",
			text = L("You can also share an eligible quest from its quest-name menu in QT chat."),
			feature = "sharing",
			menu = true,
		},
		{
			id = "hint039",
			actions = { "party_log" },
			text = L("You can compare quests before grouping up, but sharing quests requires being in the same party."),
			feature = "sharing",
		},
		{
			id = "hint040",
			actions = { "groups" },
			text = L(
				"A party share request asks the quest owner for permission unless they have enabled Always allow party share requests."
			),
			feature = "sharing",
		},
		{
			id = "hint041",
			actions = { "groups" },
			text = L(
				"Always allow party share requests automatically approves eligible requests from your party. Recipients still accept quests through WoW's normal prompt."
			),
			feature = "sharing",
		},
		{
			id = "hint042",
			actions = { "party_log" },
			text = L(
				"QT follows WoW's quest-sharing rules. A quest may be unshareable, or its recipient may need to meet prerequisites first."
			),
			feature = "sharing",
		},
		{
			id = "hint043",
			actions = { "groups" },
			text = L("Type /qt lfg to toggle Looking for Questing Partners, or use the checkbox in the minimap menu."),
			menu = true,
		},
		{
			id = "hint044",
			actions = { "groups" },
			text = L(
				"Use /qt lfg on or /qt lfg off to set your partner-seeking status explicitly. Use /qt lfg status to check it."
			),
		},
		{
			id = "hint045",
			text = L("A gold glow on a QT player dot or logo means that player is looking for questing partners."),
		},
		{
			id = "hint046",
			actions = { "player_locations" },
			text = L(
				"Set Players shown on maps to Players looking for questing partners to focus on people who want company."
			),
		},
		{
			id = "hint047",
			actions = { "player_locations" },
			text = L(
				"Looking for Questing Partners does not turn on location sharing. Enable Share my location as well if you want others to find your map dot."
			),
		},
		{
			id = "hint048",
			actions = { "groups" },
			text = L(
				"Looking for Questing Partners is saved in your profile, so it can remain on when you next load that character."
			),
		},
		{
			id = "hint049",
			actions = { "groups" },
			text = L(
				"Enable Stop looking for partners when joining a group to clear your recruiting status when you join or form a group."
			),
		},
		{
			id = "hint050",
			actions = { "groups" },
			text = L("Still recruiting after joining a group? You can turn Looking for Questing Partners back on."),
		},
		{
			id = "hint051",
			text = L("Click a QT player name or right-click a world-map dot to whisper, invite, add a friend, or compare quests. Left-click a world-map dot to open its most detailed map, or the player menu if already there."),
			menu = true,
		},
		{
			id = "hint052",
			text = L(
				"A grouped player's menu can offer Request to Join, letting you ask for an invitation without first writing a whisper."
			),
			menu = true,
		},
		{
			id = "hint053",
			text = L(
				"If the player you contact cannot invite, QT can pass your join request to their party leader when the leader also supports QT join requests."
			),
		},
		{
			id = "hint054",
			actions = { "groups" },
			text = L(
				"Automatically invite friends who request to join applies to your character friends list, not every Battle.net friend."
			),
		},
		{
			id = "hint055",
			actions = { "groups" },
			text = L(
				"You can automatically approve join requests while Looking for Questing Partners is on. You still need permission and room to invite."
			),
		},
		{
			id = "hint056",
			actions = { "groups" },
			text = L(
				"QT's automatic join-request approvals do not accept invitations for you or leave your current group."
			),
		},
		{
			id = "hint057",
			text = L(
				"QT's player dots are class-colored. Hover a dot for the player's level, class, and other available details."
			),
		},
		{
			id = "hint058",
			text = L(
				"Left-click a QT minimap dot to try to target that player while out of combat. Right-click it for the player menu, with Target first."
			),
			menu = true,
		},
		{ id = "hint059", text = L("A small party badge on a QT player dot means that player is grouped.") },
		{ id = "hint060", text = L("Hover a player's QT dot to check their addon version when it is known.") },
		{
			id = "hint061",
			text = L("QT leaves your own party's location markers to WoW instead of drawing duplicate player dots."),
		},
		{
			id = "hint062",
			actions = { "player_locations" },
			text = L(
				"Players shown on maps controls which QT dots you see. It does not change who can see your location."
			),
		},
		{
			id = "hint063",
			actions = { "player_locations" },
			text = L("You can view other players' public dots while keeping Share my location turned off."),
		},
		{
			id = "hint064",
			actions = { "player_locations" },
			text = L(
				"Choose None under Players shown on maps to hide QT's player dots while keeping WoW's own party markers."
			),
		},
		{
			id = "hint065",
			actions = { "player_locations" },
			text = L(
				"Missing dots? Check Players shown on maps: the questing-partners filter hides players who are not currently looking for partners."
			),
		},
		{
			id = "hint066",
			actions = { "announcements" },
			text = L(
				"Nearby Range controls nearby quest announcements. Players shown on maps is the separate control for which player dots you see."
			),
		},
		{
			id = "hint067",
			text = L(
				"Map dots show recently reported locations. Hover an older dot to see how old its location information is."
			),
		},
		{
			id = "hint068",
			text = L(
				"QT updates distant locations less frequently than locations in your current zone or the zone you are viewing."
			),
		},
		{
			id = "hint069",
			text = L(
				"Keep a zone open on your world map for a few seconds to let QT discover players and receive updates there."
			),
		},
		{
			id = "hint070",
			text = L(
				"A dot at your location does not guarantee that you can see its player in the world; they may be in another phase or layer."
			),
		},
		{
			id = "hint071",
			text = L(
				"Hover a grouped player's QT dot to highlight the visible dots belonging to their party and identify their leader with a crown."
			),
		},
		{
			id = "hint072",
			text = L("Player tooltips can show the hovered player's party roster, with the leader listed first."),
		},
		{
			id = "hint073",
			text = L(
				"Hover a player name in QT chat to see the same available player details used by map-dot tooltips."
			),
		},
		{
			id = "hint074",
			text = L("A glowing QT logo in a party roster identifies a member who is looking for questing partners."),
		},
		{
			id = "hint075",
			text = L(
				"Ignoring someone in WoW also hides their new QT messages, bubbles, player dots, and player logos. Existing chat history stays in your log."
			),
		},
		{
			id = "hint076",
			actions = { "announcements", "where_to_announce" },
			text = L(
				"Use What to Announce to choose which event announcements you see, and Where to Announce to choose how they appear."
			),
		},
		{
			id = "hint077",
			actions = { "announcements" },
			text = L("Set Show Announcements For to Party Only if you want quest updates just from your group."),
		},
		{
			id = "hint078",
			actions = { "announcements" },
			text = L("Choose Party & Nearby Players to include quest updates from other QT players around you."),
		},
		{
			id = "hint079",
			actions = { "announcements" },
			text = L(
				"Adjust Nearby Range in What to Announce to change how far away nearby players' quest updates are shown."
			),
		},
		{
			id = "hint080",
			actions = { "announcements" },
			text = L(
				"With Party & Nearby Players selected, set Nearby Range to Entire Zone if you want announcements from across your current zone."
			),
		},
		{
			id = "hint081",
			actions = { "announcements" },
			text = L(
				"Ready To Turn In means the objectives are finished; Quest Completion means the quest has been turned in."
			),
		},
		{
			id = "hint082",
			actions = { "announcements" },
			text = L(
				"You can hide objective-progress announcements while keeping quest acceptance, ready-to-turn-in, or completion announcements."
			),
		},
		{
			id = "hint083",
			actions = { "announcements" },
			text = L("Quest-removal announcements can help you notice when a companion abandons a quest."),
		},
		{
			id = "hint084",
			actions = { "announcements" },
			text = L("Looking-for-partners announcements can reach your whole zone, beyond your normal nearby range."),
		},
		{
			id = "hint085",
			actions = { "announcements" },
			text = L(
				"Turn off Announce Looking for Questing Partners to quiet those announcements while keeping players' glowing partner-status icons."
			),
		},
		{ id = "hint086", text = L("Type /qt followed by a message to chat with other QuestTogether players.") },
		{
			id = "hint087",
			actions = { "where_to_announce" },
			text = L("Show QuestTogether Chat controls player conversations without hiding quest announcements."),
		},
		{
			id = "hint088",
			actions = { "where_to_announce" },
			text = L(
				"QT Chat Scope affects conversations, while Show Announcements For controls whose quest updates you see."
			),
		},
		{
			id = "hint089",
			actions = { "where_to_announce" },
			text = L("Choose Global in QT Chat Scope to see all QT conversations your client receives."),
		},
		{
			id = "hint090",
			actions = { "where_to_announce" },
			text = L(
				"Choose Zone Only in QT Chat Scope to show conversations from players whose recent shared location is in your zone."
			),
		},
		{
			id = "hint091",
			actions = { "where_to_announce" },
			text = L(
				"Missing someone in Zone Only chat? That filter hides players with unknown or outdated shared locations."
			),
		},
		{
			id = "hint092",
			actions = { "where_to_announce" },
			text = L(
				"Move QT logs into a separate chat window using Chat Log Destination in Where to Announce, or the minimap menu."
			),
		},
		{
			id = "hint093",
			actions = { "where_to_announce" },
			text = L("You can keep the separate QT chat window docked as a tab or float it beside your other windows."),
		},
		{
			id = "hint094",
			actions = { "where_to_announce" },
			text = L(
				"If your QT chat window is docked as a tab, you can also print its logs to main chat. Floating QT windows keep their logs separate."
			),
		},
		{
			id = "hint095",
			actions = { "where_to_announce" },
			text = L("Closing the separate QT chat window sends later QT logs back to main chat."),
		},
		{
			id = "hint096",
			actions = { "where_to_announce" },
			text = L(
				"QT can send your enabled event announcements to normal party chat when someone in the party is not using the addon."
			),
		},
		{
			id = "hint097",
			actions = { "where_to_announce" },
			text = L(
				"QT's fallback party-chat announcements go to the whole party, including members who use QT. You can turn them off in Where to Announce."
			),
		},
		{
			id = "hint098",
			actions = { "where_to_announce" },
			text = L("QT's automatic party-chat announcements do not post to raids."),
		},
		{
			id = "hint099",
			actions = { "where_to_announce" },
			text = L(
				"You can turn off Show Chat Logs and keep progress bubbles enabled, or use chat logs without bubbles."
			),
		},
		{
			id = "hint100",
			actions = { "where_to_announce" },
			text = L(
				"Hide My Own Chat Bubbles removes your personal bubbles while continuing to share your progress with other QT players."
			),
		},
		{
			id = "hint101",
			actions = { "where_to_announce" },
			text = L(
				"Quest-completion celebrations and level-up celebrations have separate settings in Where to Announce."
			),
		},
		{
			id = "hint102",
			actions = { "where_to_announce" },
			text = L(
				"You can turn off reactions to nearby players' celebrations without turning off your own celebration emotes."
			),
		},
		{
			id = "hint103",
			actions = { "quest_plates" },
			text = L(
				"Quest Plates can mark quest targets on Blizzard nameplates with an icon, a colored health bar, or both."
			),
			feature = "nameplates",
		},
		{
			id = "hint104",
			actions = { "quest_plates" },
			text = L(
				"Choose your own Quest Health Color in Quest Plates. The Reset button beside it restores the default color."
			),
			feature = "nameplates",
		},
		{
			id = "hint105",
			actions = { "quest_plates" },
			text = L("Quest icons can appear to the left, right, above, or before the name on a nameplate."),
			feature = "nameplates",
		},
		{
			id = "hint106",
			actions = { "quest_plates" },
			text = L("Quest Plates includes a preview so you can check your icon placement and highlight color."),
			feature = "nameplates",
		},
		{
			id = "hint107",
			actions = { "player_plates" },
			text = L(
				"Enable friendly nameplates in WoW to see QT logos beside friendly players who use QuestTogether."
			),
			feature = "nameplates",
		},
		{
			id = "hint108",
			actions = { "player_plates" },
			text = L(
				"Player Plates lets you choose where QT logos appear on friendly nameplates, independently of quest-target icons."
			),
			feature = "nameplates",
		},
		{
			id = "hint109",
			actions = { "player_plates" },
			text = L("A player's QT nameplate logo does not require them to share their map location."),
			feature = "nameplates",
		},
		{
			id = "hint110",
			actions = { "player_plates" },
			text = L(
				"Hover a player in the world to see a QT tooltip badge when the addon recognizes them as a QuestTogether user."
			),
		},
		{
			id = "hint111",
			actions = { "quest_plates" },
			text = L("QT's nameplate decorations are intended for the open world; they are disabled in instances."),
			feature = "nameplates",
		},
		{
			id = "hint112",
			actions = { "quest_plates" },
			text = L(
				"Using a replacement nameplate addon? QT's quest-target visuals are designed for Blizzard nameplates, so their appearance or availability may differ."
			),
			feature = "nameplates",
		},
		{
			id = "hint113",
			actions = { "accessibility" },
			text = L("Increase Window scale in Accessibility to make QT's window text and controls larger together."),
		},
		{
			id = "hint114",
			actions = { "accessibility" },
			text = L(
				"QT fits its saved windows to your current display and limits their scale when needed to keep them on screen."
			),
		},
		{
			id = "hint115",
			actions = { "accessibility" },
			text = L("Enable Reduce motion in Accessibility to make scrolling and objective expansion immediate."),
		},
		{
			id = "hint116",
			text = L("Use /qt resetlayout if a QT window's saved position or size is getting in your way."),
		},
		{ id = "hint117", text = L("Press Escape to close QT windows.") },
		{
			id = "hint118",
			actions = { "settings" },
			text = L(
				"Choose the Light theme under General for light parchment and dark text in QT's parchment windows."
			),
		},
		{
			id = "hint119",
			actions = { "profiles" },
			text = L("Each character starts with its own QT profile. Use Profiles to choose another saved setup."),
		},
		{
			id = "hint120",
			actions = { "profiles" },
			text = L("Want the same QT settings on multiple characters? Select the same profile on each character."),
		},
		{
			id = "hint121",
			actions = { "profiles" },
			text = L(
				"Use Copy Into Current Profile to copy another profile's settings without making the two characters share future changes."
			),
		},
		{
			id = "hint122",
			actions = { "profiles" },
			text = L("Create a new profile to make a copy of your current settings and try a different setup."),
		},
		{
			id = "hint123",
			actions = { "profiles" },
			text = L("Reset Active Profile restores that profile's settings to their defaults."),
		},
		{
			id = "hint124",
			actions = { "where_to_announce" },
			text = L(
				"You can use QT's maps and quest comparisons while keeping chat logs, bubbles, and celebrations quiet."
			),
		},
		{
			id = "hint125",
			actions = { "patch_notes" },
			text = L(
				"Type /qt notes to read the latest patch notes. Use History in that window to browse older releases."
			),
		},
		{
			id = "hint126",
			actions = { "support" },
			text = L("Type /qt discord to open QT's feedback and support invite."),
		},
		{ id = "hint127", text = L("Type /qt scan to refresh QT's information from your current quest log.") },
		{
			id = "hint128",
			text = L("Type /qt disable to pause QT's runtime features, and /qt enable to turn them back on."),
		},
		{
			id = "hint129",
			actions = { "patch_notes" },
			text = L("QT can notify you in its chat log when another player is using a newer stable release."),
		},
		{
			id = "hint130",
			actions = { "patch_notes" },
			text = L(
				"Having trouble comparing quests with a friend? Check that both of you are running compatible, up-to-date versions of QT."
			),
		},
		{
			id = "hint131",
			actions = { "support" },
			text = L(
				"When reporting a QT problem, include your game client, addon version, what happened, and how to reproduce it. Screenshots help, too."
			),
		},
		{
			id = "hint132",
			actions = { "debug" },
			text = L("Type /qt debug to open QT's diagnostic window when you need information for a bug report."),
		},
		{
			id = "hint133",
			actions = { "developer" },
			text = L("Optional diagnostic sharing can be changed under QT's Developer settings."),
		},
		{
			id = "hint134",
			text = L(
				"Click a quest name in QT chat and choose Quest Details to read the information WoW has available for it, even if you have not accepted the quest."
			),
			feature = "details",
			menu = true,
		},
		{
			id = "hint135",
			actions = { "party_log" },
			text = L("Click the book icon beside a quest you own in Party Quest Log to open it in WoW's quest log."),
			feature = "journal",
		},
		{
			id = "hint136",
			text = L("A quest's name menu in QT chat also offers Open in Quest Log when the quest is in your log."),
			feature = "journal",
			menu = true,
		},
		{
			id = "hint137",
			actions = { "party_log" },
			text = L(
				"Click the round quest-focus button in your own Party Quest Log column to make that quest your active focus."
			),
			feature = "focus",
		},
		{
			id = "hint138",
			actions = { "party_log" },
			text = L(
				"Click a party member's highlighted quest-focus button in Party Quest Log to follow their quest focus."
			),
			feature = "focus",
		},
		{
			id = "hint139",
			actions = { "party_log" },
			text = L("Hover a party member's heading in Party Quest Log to see their current quest focus."),
			feature = "focus",
		},
		{
			id = "hint140",
			actions = { "party_log" },
			text = L("Follow quest focus follows a party member's quest selection, not their character's movement."),
			feature = "focus",
		},
		{
			id = "hint141",
			actions = { "party_log" },
			text = L(
				"If the player you follow chooses a quest you do not have, following stops and your current navigation stays unchanged. Get the quest, then follow them again."
			),
			feature = "focus",
		},
		{
			id = "hint142",
			actions = { "party_log" },
			text = L("Choosing a different quest while following someone asks you to confirm ending the follow."),
			feature = "focus",
		},
		{
			id = "hint143",
			actions = { "keybindings" },
			text = L(
				"Use Stop following in Party Quest Log, or assign Stop following quest focus in WoW's QT keybindings."
			),
			feature = "focus",
		},
		{
			id = "hint144",
			actions = { "party_log" },
			text = L(
				"QT remembers whom you are following across reloads and resumes when fresh party information becomes available."
			),
			feature = "focus",
		},
		{
			id = "hint145",
			actions = { "groups" },
			text = L(
				"Share my focused quest works independently of public location sharing. Your party can see your active quest even with your public dot hidden."
			),
			feature = "focus",
		},
		{
			id = "hint146",
			actions = { "party_log" },
			text = L(
				"Quest-focus following supports parties of up to five, including dungeon groups, rather than raids."
			),
			feature = "focus",
		},
		{
			id = "hint147",
			text = L(
				"Hover a player who is looking for questing partners to see their currently focused quest when they are sharing it."
			),
		},
		{
			id = "hint148",
			actions = { "groups" },
			text = L(
				"With Share my waypoint enabled, placing, moving, or clearing your normal WoW map pin updates your party's shared destination."
			),
			feature = "waypoint",
		},
		{
			id = "hint149",
			text = L(
				"Receiving a party waypoint does not redirect you. Click its pin and choose Navigate here when you want to head there."
			),
			feature = "navigation",
			menu = true,
		},
		{
			id = "hint150",
			text = L(
				"Hover a party waypoint to see its owner, zone, and coordinates. Overlapping pins list everyone sharing that spot."
			),
		},
		{ id = "hint151", text = L("Shared party waypoints appear on the world map and, when nearby, the minimap.") },
		{
			id = "hint152",
			actions = { "groups" },
			text = L(
				"Share my waypoint and Show party waypoints are separate settings, so you can choose what to share and what to display."
			),
			feature = "waypoint",
		},
		{
			id = "hint153",
			text = L(
				"QT uses TomTom for waypoint navigation when available, with WoW's waypoint navigation as a fallback."
			),
			feature = "navigation",
		},
		{
			id = "hint154",
			text = L(
				"Click a coordinate link in a QT message to create a waypoint when TomTom or the client's waypoint support is available."
			),
			feature = "navigation",
		},
		{
			id = "hint155",
			text = L("Navigating to a waypoint ends quest-focus following."),
			feature = "navigationFocus",
		},
		{
			id = "hint156",
			actions = { "hud_edit" },
			text = L(
				"Move your personal progress bubble in HUD Edit Mode to keep updates away from the middle of the action."
			),
			feature = "hud",
		},
		{
			id = "hint157",
			actions = { "hud_edit" },
			text = L("Select QuestTogether Bubble in HUD Edit Mode to adjust bubble size and display duration."),
			feature = "hud",
		},
		{
			id = "hint158",
			actions = { "hud_edit" },
			text = L("Increase the bubble duration if progress messages disappear before you finish reading them."),
			feature = "hud",
		},
		{
			id = "hint159",
			actions = { "hud_edit" },
			text = L("QT bubble changes apply automatically in HUD Edit Mode; Blizzard's Save button is not required."),
			feature = "hud",
		},
		{
			id = "hint160",
			actions = { "hud_edit" },
			text = L(
				"Use Revert Changes in QT bubble settings to undo edits made since opening HUD Edit Mode or your last Save Changes."
			),
			feature = "hud",
		},
		{
			id = "hint161",
			actions = { "announcements" },
			text = L(
				"World-quest announcements have separate controls for entering an area, leaving, progress, and completion in What to Announce."
			),
			feature = "worldQuests",
		},
		{
			id = "hint162",
			actions = { "announcements" },
			text = L("Bonus-objective announcements have their own controls in What to Announce."),
			feature = "bonusObjectives",
		},
		{
			id = "hint163",
			actions = { "experimental" },
			text = L(
				"See a phasing icon on a QT player dot? Hover it for an experimental warning that the player may be on a different layer."
			),
			feature = "layers",
		},
		{
			id = "hint164",
			actions = { "experimental" },
			text = L(
				"QT's experimental layer detection uses nearby observations. Its warnings are estimates; a missing player alone does not prove a different layer."
			),
			feature = "layers",
		},
		{
			id = "hint165",
			actions = { "experimental" },
			text = L(
				"Detect different layers is an optional setting under Experimental. It needs location sharing and compatible QT clients."
			),
			feature = "layers",
		},
		{
			id = "hint166",
			text = L("Hover a player's QT dot to see their shared War Mode status when it is available."),
			feature = "warMode",
		},
		{ id = "hint167", text = L("Type /qt tip or /qt hint to see another QuestTogether tip whenever you like.") },
	}
end

function QT:FormatHint(text, label)
	return self:GetIconChatTagFromAsset("Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherTipIcon", "texture", 14)
		.. " |cffffd100"
		.. (label or L("Tip:"))
		.. "|r |cfffff2cc"
		.. text
		.. "|r"
end

function QT:ShowHint()
	if not self.hasLoggedIn or self.isLoggingOut then
		return false
	end
	local global = self.db and self.db.global
	if type(global) ~= "table" then
		return false
	end
	local capabilities = self.API.GetHintCapabilities and self.API.GetHintCapabilities() or {}
	if type(capabilities) ~= "table" then
		capabilities = {}
	end
	local previous = type(global.hintPool) == "table" and global.hintPool or {}
	local seenBefore = type(previous.seen) == "table" and previous.seen or {}
	local seen, eligible, remaining = {}, {}, {}
	local last
	for _, hint in ipairs(self:GetHintCatalog()) do
		-- Iterate our bounded catalog, not potentially corrupt saved data.
		if seenBefore[hint.id] == true then
			seen[hint.id] = true
		end
		if previous.last == hint.id then
			last = hint.id
		end
		if
			(not hint.feature or capabilities[hint.feature] == true) and (not hint.menu or capabilities.menu == true)
		then
			eligible[#eligible + 1] = hint
			if not seen[hint.id] then
				remaining[#remaining + 1] = hint
			end
		end
	end
	if #eligible == 0 then
		return false
	end
	if #remaining == 0 then
		seen = {}
		for _, hint in ipairs(eligible) do
			-- Avoid the same tip on both sides of a refill. The previous tip
			-- remains unseen and can be drawn later in this new cycle.
			if #eligible == 1 or hint.id ~= last then
				remaining[#remaining + 1] = hint
			end
		end
	end
	local index = self:SafeToNumber(self.API.Random(1, #remaining))
	if not index or index % 1 ~= 0 or index < 1 or index > #remaining then
		index = 1
	end
	local hint = remaining[index]
	if not self:TryAddMessageToConfiguredChatLogFrames(self:FormatHintEntry(hint)) then
		return false
	end
	-- Drawing uniformly from unseen IDs is a shuffled hat, without storing a
	-- second order list. Only successfully printed tips consume a draw.
	seen[hint.id] = true
	global.hintPool = { seen = seen, last = hint.id }
	return true
end

function QT:ScheduleStartupHint()
	if
		rawget(self, "startupHintState")
		or not self.isEnabled
		or not self.hasLoggedIn
		or self.isLoggingOut
		or self:GetOption("showStartupTips") ~= true
	then
		return false
	end
	local state = { attempts = 0 }
	self.startupHintState = state
	local function PrintWhenReady()
		if
			rawget(self, "startupHintState") ~= state
			or state.shown
			or not self.isEnabled
			or not self.hasLoggedIn
			or self.isLoggingOut
			or self:GetOption("showStartupTips") ~= true
		then
			return
		end
		state.attempts = state.attempts + 1
		state.shown = self:ShowHint()
		if not state.shown and state.attempts < 3 then
			self:ScheduleRuntimeWork(
				"foreign_frame_mutation",
				"startup_hint",
				PrintWhenReady,
				{ lifetime = "ui", delay = 2, owner = state }
			)
		end
	end
	local queued = self:ScheduleRuntimeWork(
		"foreign_frame_mutation",
		"startup_hint",
		PrintWhenReady,
		{ lifetime = "ui", mode = "nextFrame", owner = state }
	)
	if not queued then
		self.startupHintState = nil
	end
	return queued
end
