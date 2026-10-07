local QT = _G.QuestTogether
local L = QT.Translate

-- Deliberately English campaign copy, independent of the client's UI language.
-- Keep the author's download milestone as a fixed claim, not a live counter.
local ADS = {
	"Want an easier way to find players to quest with across phase layers? Check out QuestTogether! Flag yourself as looking for questing partners and find some company for the grind.",
	"Still asking 'which quests do you have?' Check out QuestTogether! Its Party Quest Log puts everyone's quests side by side so you can see what you share and who's missing out.",
	"Waiting for everyone to finish those last few quest items? QuestTogether shows your party's objective counts and progress bars in one place. Less asking, more questing :)",
	"Always asking your questing buddy 'which quest are we doing next?' QuestTogether lets you follow their quest focus and updates yours as they pick the next quest you both have!",
	"'Where are we going?' QuestTogether shares party waypoints on your map and minimap, with a class-colored pin for each player. Pick a pin when you want to head their way!",
	"Got the quest but your friend doesn't? QuestTogether's Party Quest Log shows who's missing it, with Share and Request Share buttons where the game allows it. Handy little time saver!",
	"Questing doesn't have to be a solo grind. QuestTogether helps you find questing partners, compare quests, and keep up with each other's progress. Come make some questing friends :)",
	"Over 30k downloads during beta! Check out QuestTogether if you like questing with other people. Find partners, compare your party's quests, and follow a friend's quest focus.",
	"Love seeing your friends make progress? QuestTogether adds quest progress chat bubbles and updates so you can cheer each other on while you quest. The grind is better with company :)",
	"Who's ready to turn in, and who still needs help? QuestTogether's Party Quest Log shows the whole party at a glance. Expand a quest to see everyone's objectives and progress!",
	"QuestTogether puts other QT players on your world map and minimap as class-colored dots. See who's out questing nearby, even when phase layers make the world look empty!",
	"Want company without repeatedly asking in chat? Turn on Looking for Questing Partners in QuestTogether. Your map dot gets a gold glow so other QT players can find you!",
	"Looking for people who actually WANT to group? QuestTogether can filter your maps to just players looking for questing partners. Less guesswork, more company :)",
	"See a questing group you'd like to join? QuestTogether lets you request an invite from another QT player's menu. They get a prompt, and you still accept the normal party invite!",
	"Questing with regular buddies? QuestTogether can automatically approve join requests from your character friends list. It's optional, and you stay in control of your party.",
	"Not everyone in your group has QuestTogether? It can also send your quest updates to normal party chat so those friends can keep up. You choose which updates to announce!",
	"Which mobs do I still need? QuestTogether can add quest icons and optional health-bar tints to quest objectives on Blizzard nameplates. Spot the mobs you need at a glance!",
	"Spot fellow QuestTogether users in the wild! QT can add its little scroll logo beside friendly player nameplates, with a gold glow when they're looking for questing partners.",
	"Want a chat channel with other QuestTogether players? Type /qt followed by your message. Meet other questers and talk between pulls, with QT chat logs and nearby chat bubbles!",
	"Like quest updates but hate burying guild chat? QuestTogether can put its logs in a separate chat tab or floating window. Keep your questing chatter where you want it!",
	"Want party updates without all the nearby chatter? QuestTogether lets you choose Party Only, or include nearby players with an adjustable announcement range. Your questing, your pace.",
	"Want progress updates but not every quest pickup or turn-in? QuestTogether lets you toggle announcement types individually. Keep the bits you enjoy and quiet the rest!",
	"Finishing quests deserves a little celebration :) QuestTogether can play completion emotes and react to nearby QT players finishing theirs. Each celebration type is optional!",
	"Ding! QuestTogether can celebrate your level-ups and react when nearby QT players level up too. A little more cheering, a little less silently grinding alone :)",
	"Who's grouped with whom? Hover a party member's map dot in QuestTogether to highlight their nearby party dots and crown their leader. Find the whole crew at a glance!",
	"Before you whisper someone to quest, hover their QuestTogether map dot. See their level, class, and party details when available, plus whether they're looking for company!",
	"Want to see other questers without broadcasting your own location? QuestTogether keeps location sharing and viewing separate. You choose whether your own dot is visible.",
	"QuestTogether's clickable player names and map dots have shortcuts for whispering, inviting, adding friends, and comparing quests. Less menu hunting when you find a questing buddy!",
	"Found a questing buddy on the map? QuestTogether can set a waypoint to their shared location, using TomTom when available or the game's waypoint support. Go say hello :)",
	"Different alts, different moods? QuestTogether has character profiles you can copy or share. Keep one character social and another focused on party-only questing.",
	"No need to juggle two quest windows: QuestTogether puts a little book button beside quests you own. Open that quest straight in Blizzard's Quest Log from Party Quest Log!",
	"Big quest log, small attention span? QuestTogether's Party Quest Log has search and filters for ownership, progress, and sharing actions. Find what the group needs next.",
	"Questing with friends on another client language? QuestTogether can display their updates using localized quest titles when available. Progress is easier to follow in your own language!",
	"Someone making questing less fun? QuestTogether respects WoW's ignore list for new chat, bubbles, player dots, and icons. You decide whose company you keep.",
	"You don't have to turn on every bell and whistle. QuestTogether lets you use player maps and party quest comparisons while keeping chat logs, bubbles, and celebrations quiet.",
	"Want a map focused on your own group? QuestTogether can show only your party's player locations. Or open it up to other QT players when you're looking for new company!",
	"Found your questing group? QuestTogether can automatically turn off Looking for Questing Partners when you join a party. Turn it back on whenever you're ready to recruit more!",
}
local SIGNOFF = " This msg is a macro, but I am not a bot. Just spreading the word :)"

function QT:PickAdvertisement()
	local pool = rawget(self, "advertisementPool")
	if not pool or #pool == 0 then
		pool = {}
		for index = 1, #ADS do pool[index] = index end
		for index = #pool, 2, -1 do
			local other = self.API.Random(1, index)
			pool[index], pool[other] = pool[other], pool[index]
		end
		-- Pop from the end. Avoid repeating the last draw across refills, too.
		if #pool > 1 and pool[#pool] == rawget(self, "lastAdvertisementIndex") then
			local other = self.API.Random(1, #pool - 1)
			pool[#pool], pool[other] = pool[other], pool[#pool]
		end
		self.advertisementPool = pool
	end
	local index = pool[#pool]
	return ADS[index] .. SIGNOFF, index
end

function QT:HandleAdvertisementCommand(input)
	local channel = self:SafeTrimString(input, "")
	if channel == "" or #channel > 128 or channel:find("[%c|]") then
		self:Print(L("Usage: /qt ad <channel> (for example: /qt ad 1, /qt ad say, or /qt ad yell)"))
		return false
	end
	channel = channel:gsub("^/(%d+)$", "%1")
	local number = tonumber(channel)
	local api = self.API or {}
	local mode = channel:upper()
	local localChat = mode == "SAY" or mode == "YELL"
	-- Resolve on every keypress: channel numbers can change when zoning or joining.
	local ok, id
	if not localChat and type(api.GetChannelName) == "function" and (not number or (number > 0 and number % 1 == 0)) then
		ok, id = pcall(api.GetChannelName, number or channel)
	end
	id = ok and self:SafeToNumber(id) or nil
	if not localChat and (not id or id <= 0 or id % 1 ~= 0) then
		self:Print(L("That chat channel is not joined. Use its current number or name."))
		return false
	end
	local send = api.SendChannelChatMessage
	if localChat then send = api.SendLocalChatMessage end
	if self:IsRuntimeRestrictionTypeActive("chat") or type(send) ~= "function" then
		self:Print(L("The ad could not be sent. Try again when chat is available."))
		return false
	end
	local message, index = self:PickAdvertisement()
	-- Send synchronously from the slash/macro invocation. Never queue or retry ads.
	local sentOK, sent = pcall(send, message, localChat and mode or id)
	if not sentOK or sent ~= true then
		self:Print(L("The ad could not be sent. Try again when chat is available."))
		return false
	end
	table.remove(self.advertisementPool)
	self.lastAdvertisementIndex = index
	return true
end
