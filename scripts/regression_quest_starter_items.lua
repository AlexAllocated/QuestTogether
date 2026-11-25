-- SPDX-License-Identifier: GPL-3.0-only
-- Private native contracts and observations; never touch live bags or chat.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local LINK = "|cffffffff|Hitem:123:0|h[Old Book]|h|r"
local function Fixture()
	local h = { now = 100, bag = {}, cached = true, scans = 0, requests = 0, events = {}, secret = {} }
	local a = setmetatable({ isEnabled = true, isRunningTests = false,
		suppressLocalAnnouncementDisplayDuringTests = false, db = { profile = {} }, locale = "enUS" }, { __index = QT })
	function a:CanAccessValue(v) return v ~= h.secret end
	function a:CanAccessTable(v) return type(v) == "table" and v ~= h.secret end
	function a:PublishAnnouncementEvent(kind, text, id, extra)
		h.events[#h.events + 1] = { kind = kind, text = text, id = id, extra = extra }
	end
	local n = { lastBag = 0, selfLootFormats = { "You receive loot: %s.", "You receive loot: %sx%d." },
		UnitGUID = function() return "Player-1-ABC" end,
		GetContainerNumSlots = function() h.scans = h.scans + 1; return #h.bag end,
		GetContainerItemID = function(_, slot) return h.bag[slot].id end,
		GetContainerItemQuestInfo = function(_, slot) return h.bag[slot].info end,
		IsItemDataCachedByID = function() return h.cached end,
		GetItemNameByID = function() return h.name or "Old Book" end,
		GetItemIconByID = function() return 134245 end,
		RequestLoadItemDataByID = function() h.requests = h.requests + 1 end,
	}
	a.API = a:CreateQuestStarterNativeAdapter(n)
	a.API.GetTime = function() return h.now end
	h.a, h.native = a, n
	function h:Loot(guid, text)
		a:CHAT_MSG_LOOT(nil, text or ("You receive loot: " .. LINK .. "."), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
	end
	function h:Tick(delta) self.now = self.now + (delta or 0); a:UpdateQuestStarterItems() end
	function h:Item(info) self.bag = { { id = 123, info = info or { questID = 456, isActive = false, isQuestItem = false } } } end
	return h
end
QT:RegisterTest("quest starter loot announces a native starter once with item icon and facts", function()
	local h = Fixture(); h:Item(); h:Loot("Player-1-ABC"); h:Tick()
	Equal(#h.events, 1); local event = h.events[1]
	Equal(event.kind, "QUEST_STARTER_FOUND"); Equal(event.id, 456)
	Equal(event.text, "Quest-starting item found: Old Book"); Equal(event.extra.iconAsset, 134245)
	Equal(h.a:DecodeAnnouncementFacts(event.extra.eventFacts).index, 123)
	h:Loot("Player-1-ABC"); h:Tick(1); Equal(#h.events, 1)
end, { offline = true })
QT:RegisterTest("quest starter loot distinguishes other players and localized self messages", function()
	local h = Fixture(); h:Item()
	h:Loot("Player-2-DEF"); h:Tick(); Equal(#h.events, 0)
	h:Loot(nil, "Other receives loot: " .. LINK .. "."); h:Tick(); Equal(#h.events, 0)
	h:Loot(nil); h:Tick(); Equal(#h.events, 1)
	for _, format in ipairs({ "Ihr erhaltet Beute: %s.", "Vous recevez : %1$s." }) do
		h = Fixture(); h:Item(); h.native.selfLootFormats = { format }
		h:Loot(nil, (format:gsub("%%1%$s", LINK):gsub("%%s", LINK))); h:Tick(); Equal(#h.events, 1)
	end
	h = Fixture(); h:Item(); h:Loot(nil, "You receive loot: " .. LINK .. "x2."); h:Tick(); Equal(#h.events, 1)
end, { offline = true })
QT:RegisterTest("quest starter loot ignores ordinary quest items and already active starters", function()
	for _, info in ipairs({ { isQuestItem = true, isActive = false }, { questID = 456, isActive = true } }) do
		local h = Fixture(); h:Item(info); h:Loot(nil); h:Tick(); Equal(#h.events, 0)
		Equal(next(h.a.questStarterItems.pending), nil)
	end
end, { offline = true })
QT:RegisterTest("quest starter bag moves and startup do not create announcements", function()
	local h = Fixture(); h:Item(); h:Tick(); h:Tick(1)
	Equal(#h.events, 0); Equal(h.scans, 0); Equal(h.requests, 0)
end, { offline = true })
QT:RegisterTest("quest starter waits for bags and cached metadata with bounded retries", function()
	local h = Fixture(); h.cached = false; h:Loot(nil); h:Tick(); Equal(#h.events, 0)
	h:Item(); h:Tick(0.5); Equal(#h.events, 0)
	h.cached = true; h:Tick(0.5); Equal(#h.events, 1); Equal(h.requests, 1)
	h = Fixture(); h:Loot(nil); h:Tick(11); h:Item(); h:Tick(1); Equal(#h.events, 0)
end, { offline = true })
QT:RegisterTest("quest starter rejects inaccessible malformed and failing native data", function()
	for _, mode in ipairs({ "secret", "error", "invalid", "name", "absent" }) do
		local h = Fixture(); h:Item()
		if mode == "secret" then h.bag[1].info = h.secret
		elseif mode == "error" then h.native.GetContainerItemQuestInfo = function() error("unavailable") end
		elseif mode == "invalid" then h.bag[1].info.questID = -5
		elseif mode == "name" then h.name = "|Hunsafe|h"
		elseif mode == "absent" then h.native.GetContainerItemQuestInfo = nil end
		h:Loot(nil); h:Tick(); Equal(#h.events, 0)
	end
	local h = Fixture(); h:Item(); h:Loot(h.secret); h:Tick(); Equal(#h.events, 0)
end, { offline = true })
QT:RegisterTest("quest starter retires work across profiles disable and world resets", function()
	for _, mode in ipairs({ "profile", "disable", "logout", "reset" }) do
		local h = Fixture(); h:Item(); h:Loot(nil)
		if mode == "profile" then h.a.db.profile = {}
		elseif mode == "disable" then h.a.isEnabled = false
		elseif mode == "logout" then h.a.isLoggingOut = true
		else h.a:ResetQuestStarterItems() end
		h:Tick(); Equal(#h.events, 0); Equal(h.a.questStarterItems, nil)
	end
end, { offline = true })
QT:RegisterTest("quest starter queue and retry scans remain bounded", function()
	local h = Fixture()
	for id = 1, 100 do h:Loot(nil, "You receive loot: " .. LINK:gsub("item:123:", "item:" .. id .. ":") .. ".") end
	Equal(h.requests, 16); h:Tick(); local scans = h.scans
	for _ = 1, 100 do h:Tick(0.001) end
	Equal(h.scans, scans)
end, { offline = true })
QT:RegisterTest("quest starter localization uses item titles not quest titles", function()
	local h = Fixture(); h:Item(); h:Loot(nil); h:Tick()
	local event = h.events[1]; event.eventType, event.eventFacts, event.questId = event.kind, event.extra.eventFacts, event.id
	h.a.API.GetQuestStarterItemName = function() return "Local Item" end
	Equal(h.a:LocalizeAnnouncementEvent(event), "Quest-starting item found: Local Item")
	h.a.API.GetQuestStarterItemName = function() return nil end
	Equal(h.a:LocalizeAnnouncementEvent(event), event.text)
	Equal(h.a:DecodeAnnouncementFacts("1:enUS:i:123:1:"), nil)
	Equal(h.a:GetAnnouncementOptionKey(event.kind), "announceQuestStarterItems")
end, { offline = true })
_G.QuestTogether:RecordTestModule("scripts/regression_quest_starter_items.lua")
