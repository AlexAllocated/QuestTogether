-- Receiver-side presentation only. Original text remains in every ANN packet for
-- older peers; the optional trailing field contains facts, never executable text.
local QT = _G.QuestTogether
local L = QT.Translate
local locales = {
	enUS = true,
	deDE = true,
	frFR = true,
	esES = true,
	esMX = true,
	ptBR = true,
	ruRU = true,
	itIT = true,
	koKR = true,
	zhCN = true,
	zhTW = true,
}
local aliases = { enGB = "enUS" }
local prefixes = {
	QUEST_ACCEPTED = "Quest Accepted: ",
	QUEST_COMPLETED = "Quest Completed: ",
	QUEST_READY_TO_TURN_IN = "Ready to Turn In: ",
	QUEST_REMOVED = "Quest Removed: ",
	WORLD_QUEST_ENTERED = "World Quest Entered: ",
	WORLD_QUEST_LEFT = "Left World Quest: ",
	WORLD_QUEST_COMPLETED = "World Quest Completed: ",
	BONUS_OBJECTIVE_ENTERED = "Bonus Objective Entered: ",
	BONUS_OBJECTIVE_LEFT = "Left Bonus Objective: ",
	BONUS_OBJECTIVE_COMPLETED = "Bonus Objective Completed: ",
}
local progressEvents = { QUEST_PROGRESS = true, WORLD_QUEST_PROGRESS = true, BONUS_OBJECTIVE_PROGRESS = true }

local function Integer(addon, value, minimum, maximum)
	local n = addon:SafeToNumber(value)
	if n and n >= minimum and n <= maximum and n == math.floor(n) then
		return n
	end
end

function QT:GetEventLocale()
	local locale = self.localizationTestLocale or self.locale or "enUS"
	locale = aliases[locale] or locale
	return locales[locale] and locale or "enUS"
end

function QT:GetLocalizedEventPrefix(eventType)
	local prefix = prefixes[eventType]
	return prefix and self.TranslateForLocale(prefix, self:GetEventLocale()) or nil
end

function QT:DecodeAnnouncementFacts(value)
	if not self:CanAccessValue(value) or type(value) ~= "string" or #value > 80 then
		return nil
	end
	local locale, kind, index, current, required = value:match("^1:([a-zA-Z]+):([qcplo]):(%d*):(%d*):(%d*)$")
	if not locales[locale] then
		return nil
	end
	local fact = { locale = locale, kind = kind }
	if kind == "q" then
		if index ~= "" or current ~= "" or required ~= "" then
			return nil
		end
	elseif kind == "l" then
		fact.current = Integer(self, current, 1, 1000)
		if index ~= "" or required ~= "" or not fact.current then
			return nil
		end
	else
		fact.index = Integer(self, index, 1, 100)
		fact.current = Integer(self, current, 0, kind == "p" and 100 or (kind == "o" and 1 or 1000000000))
		if not fact.index or not fact.current then
			return nil
		end
		if required ~= "" then
			if kind ~= "c" then
				return nil
			end
			fact.required = Integer(self, required, 1, 1000000000)
			if not fact.required or fact.current > fact.required then
				return nil
			end
		end
	end
	return fact
end

function QT:BuildAnnouncementFacts(eventType, index, objectiveType, finished, current, required)
	local kind = prefixes[eventType] and "q" or nil
	if eventType == "PLAYER_LEVEL_UP" then
		kind, current, index, required = "l", Integer(self, current, 1, 1000), nil, nil
		if not current then
			return nil
		end
	elseif progressEvents[eventType] then
		index = Integer(self, index, 1, 100)
		if not index then
			return nil
		end
		current = Integer(self, current, 0, 1000000000)
		required = Integer(self, required, 1, 1000000000)
		if self:CanAccessValue(objectiveType) and objectiveType == "progressbar" then
			if not current or current > 100 then
				return nil
			end
			kind, required = "p", nil
		elseif current then
			kind = "c"
			if required and current > required then
				required = nil
			end
		else
			-- Text-only legacy objectives cannot safely yield numeric facts.
			-- Their completion state still has a localized representation.
			if not self:CanAccessValue(finished) or type(finished) ~= "boolean" then
				return nil
			end
			kind, current, required = "o", finished and 1 or 0, nil
		end
	end
	if not kind then
		return nil
	end
	return table.concat({ "1", self:GetEventLocale(), kind, index or "", current or "", required or "" }, ":")
end

function QT:GetLocalizedQuestTitle(questID)
	local id = Integer(self, questID, 1, 1000000000)
	if not id then
		return nil
	end
	-- These snapshots are addon-owned and already hold the client's local title.
	local snapshot = self.GetQuestSnapshot and self:GetQuestSnapshot(id)
	local title = snapshot and self:SafeTrimString(snapshot.title, "") or ""
	if title ~= "" and not self:IsPlaceholderQuestTitle(id, title) then
		return title
	end
	local api = self.API or {}
	if type(api.GetLocalizedQuestTitle) ~= "function" then
		return nil
	end
	local now = self:SafeToNumber(api.GetTime and api.GetTime()) or 0
	local cache = rawget(self, "localizedQuestTitles")
	if not cache then
		cache = { entries = {}, order = {}, requests = {} }
		self.localizedQuestTitles = cache
	end
	local entry = cache.entries[id]
	if entry and now >= entry.time and now - entry.time < (entry.title and 300 or 5) then
		return entry.title
	end
	if self:IsWorkBlocked("quest_snapshot_refresh") then
		return nil
	end
	local ok, rawTitle = pcall(api.GetLocalizedQuestTitle, id)
	title = ok and self:SafeTrimString(rawTitle, "") or ""
	if #title > 512 or self:IsPlaceholderQuestTitle(id, title) then
		title = ""
	end
	if not entry then
		if #cache.order >= 256 then
			cache.entries[table.remove(cache.order, 1)] = nil
		end
		cache.order[#cache.order + 1] = id
		entry = {}
		cache.entries[id] = entry
	end
	entry.time, entry.title = now, title ~= "" and title or nil
	if title == "" and type(api.RequestLocalizedQuestTitle) == "function" then
		-- A bounded rolling window prevents bursts at fixed-window boundaries
		-- and retains per-ID throttling even if the display cache evicts an entry.
		local requested = false
		for i = #cache.requests, 1, -1 do
			local request = cache.requests[i]
			if now < request.time or now - request.time >= 30 then
				table.remove(cache.requests, i)
			elseif request.id == id then
				requested = true
			end
		end
		if #cache.requests < 10 and not requested then
			cache.requests[#cache.requests + 1] = { id = id, time = now }
			pcall(api.RequestLocalizedQuestTitle, id)
		end
	end
	return entry.title
end

function QT:LocalizeAnnouncementEvent(event)
	if event.eventType == "LOOKING_FOR_QUEST_PARTNERS" then
		return L("Looking for questing partners") .. " :)"
	end
	local facts = self:DecodeAnnouncementFacts(event.eventFacts)
	local prefix = prefixes[event.eventType]
	if facts and facts.locale == self:GetEventLocale() then
		return event.text
	end
	if event.eventType == "PLAYER_LEVEL_UP" and facts and facts.kind == "l" then
		return L("Level ") .. tostring(facts.current)
	end
	local id = Integer(self, event.questId, 1, 1000000000)
	if not id or (not prefix and not progressEvents[event.eventType]) then
		return event.text
	end
	if prefix and facts and facts.kind ~= "q" then
		return event.text
	end
	if prefix then
		-- Event type already identifies these labels. Optional facts can be
		-- omitted by older senders or packet fitting; recognize only exact known
		-- prefixes, never guess a title by splitting arbitrary translated prose.
		local sourceTitle
		local text = self:SafeTrimString(event.text, "")
		for locale in pairs(locales) do
			if not facts or facts.locale == locale then
				local sourcePrefix = self.TranslateForLocale(prefix, locale)
				if text:sub(1, #sourcePrefix) == sourcePrefix and #text > #sourcePrefix then
					sourceTitle = text:sub(#sourcePrefix + 1)
					break
				end
			end
		end
		if not facts and not sourceTitle then return event.text end
		local title = self:GetLocalizedQuestTitle(id) or sourceTitle
		return title and (self.TranslateForLocale(prefix, self:GetEventLocale()) .. title) or event.text
	end
	if not facts or (facts.kind ~= "c" and facts.kind ~= "p" and facts.kind ~= "o") then
		return event.text
	end
	local title = self:GetLocalizedQuestTitle(id)
	-- Progress prose cannot safely be split into a quest title and objective.
	-- Preserve readable source text when local data cannot supply the title.
	if not title then
		return event.text
	end
	-- Objective indexes are not stable identities across stages. Do not borrow
	-- another player's objective text or counters, or replace numbers in prose.
	local progress
	if facts.kind == "p" then
		progress = string.format(L("Objective %d: %d%%"), facts.index, facts.current)
	elseif facts.kind == "c" and facts.required then
		progress = string.format(L("Objective %d: %d/%d"), facts.index, facts.current, facts.required)
	elseif facts.kind == "c" then
		progress = string.format(L("Objective %d: %d"), facts.index, facts.current)
	elseif facts.current == 1 then
		progress = string.format(L("Objective %d: Complete"), facts.index)
	else
		progress = string.format(L("Objective %d: Progress updated"), facts.index)
	end
	return title .. " — " .. progress
end
