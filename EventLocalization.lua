-- Receiver-side presentation only. Preserve the original ANN text on the wire;
-- localized titles and bounded cache waits belong to the receiving client.
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
local TITLE_WAIT_SECONDS, MAX_TITLE_WAITERS = 2, 32

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
	local locale, kind, index, current, required = value:match("^1:([a-zA-Z]+):([qcplos]):(%d*):(%d*):(%d*)$")
	if not locales[locale] then
		return nil
	end
	local fact = { locale = locale, kind = kind }
	if kind == "q" then
		if index ~= "" or current ~= "" or required ~= "" then
			return nil
		end
	elseif kind == "l" or kind == "s" then
		fact.current = Integer(self, current, kind == "s" and 0 or 1, kind == "s" and 10000 or 1000)
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
	if eventType == "PLAYER_LEVEL_UP" or eventType == "SCAN_STATUS" then
		local scan = eventType == "SCAN_STATUS"
		kind, current, index, required = scan and "s" or "l", Integer(self, current, scan and 0 or 1, scan and 10000 or 1000), nil, nil
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

function QT:NotifyLocalizedQuestTitleChanged(questID)
	local focus = rawget(self, "questFocusState")
	if focus and focus.id == questID then self:QueueQuestFocusRefresh() end
	-- Cache reads and load events publish the same notification. Each view owns
	-- its deferred render and rechecks its current session before touching UI.
	if self.OnPartyQuestTitleChanged then self:OnPartyQuestTitleChanged(questID) end
	if self.OnPartyFocusTitleChanged then self:OnPartyFocusTitleChanged(questID) end
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
	-- Enable clears saved trackers; the ready flag proves this session rebuilt
	-- them. Task quests may have no normal quest-log row or native title cache.
	if self:GetRuntimeFlag("questTrackerReady", false) and self.db and self.db.global then
		local tracked = self:GetPlayerTracker()[id]
		if tracked and tracked.titleLocale == self:GetEventLocale() then
			title = self:SafeTrimString(tracked.title, "")
			if title ~= "" and #title <= 512 and not self:IsPlaceholderQuestTitle(id, title) then return title end
		end
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
	local previousTitle = entry.title
	entry.time, entry.title = now, title ~= "" and title or nil
	if entry.title and entry.title ~= previousTitle then self:NotifyLocalizedQuestTitleChanged(id) end
	if title == "" and type(api.RequestLocalizedQuestTitle) == "function" then
		local session = self.partyQuestCompareSession
		local inCompare = false
		for _, member in ipairs(session and session.members or {}) do
			if member.entries[id] then inCompare = true; break end
		end
		if not inCompare then session = nil end
		local attempts = session and session.titleRequests and session.titleRequests[id]
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
		if #cache.requests < 10 and not requested and (not attempts or attempts.count < 2) then
			cache.requests[#cache.requests + 1] = { id = id, time = now }
			if session then
				session.titleRequests = session.titleRequests or {}
				session.titleRequests[id] = { count = (attempts and attempts.count or 0) + 1, time = now }
			end
			local requestedOK, accepted = pcall(api.RequestLocalizedQuestTitle, id)
			entry.requestedAt = requestedOK and accepted ~= false and now or nil
		end
	end
	return entry.title
end

function QT:InvalidateLocalizedQuestTitle(questID)
	local id = Integer(self, questID, 1, 1000000000)
	local cache = rawget(self, "localizedQuestTitles")
	local entry = id and cache and cache.entries[id]
	if not entry or entry.title then return false end
	entry.time = -math.huge
	return true
end

function QT:ResetLocalizedQuestTitles()
	local cache = rawget(self, "localizedQuestTitles")
	self.localizedQuestTitles = nil
	for _, waiting in pairs(cache and cache.waiting or {}) do
		self:CancelRuntimeWorkOwner(waiting.owner)
		waiting.events = nil
	end
end

local function FinishAnnouncements(addon, cache, key, waiting)
	if cache.waiting[key] ~= waiting or not waiting.owner.active
		or rawget(addon, "localizedQuestTitles") ~= cache then return end
	local events = waiting.events
	cache.waiting[key], cache.waitingCount, waiting.events = nil, cache.waitingCount - #events, nil
	addon:CancelRuntimeWorkOwner(waiting.owner)
	if not addon.isEnabled or addon.isLoggingOut then return end
	-- The miss cache normally lasts five seconds. Re-read once at completion so
	-- tooltip data loaded without a quest-load event can satisfy the two-second wait.
	addon:InvalidateLocalizedQuestTitle(waiting.questID)
	-- Recheck current display options, ignores, group/scope and nearby frames.
	-- Never retain a nameplate or repeat network acceptance/forwarding here.
	for _, event in ipairs(events) do
		if rawget(addon, "localizedQuestTitles") ~= cache or not addon.isEnabled or addon.isLoggingOut then return end
		addon:HandleAnnouncementEvent(event, false, true)
	end
end

function QT:QueueLocalizedAnnouncement(event, waitingForTitle)
	if not self.isEnabled or self.isLoggingOut then return false end
	local cache = rawget(self, "localizedQuestTitles")
	local id = Integer(self, event.questId, 1, 1000000000)
	if not id or not cache then return false end
	local sender = self:NormalizeMemberName(event.senderName) or event.senderName
	local key = sender .. "\000" .. id
	local waiting = cache.waiting and cache.waiting[key]
	local now = self:SafeToNumber(self.API.GetTime()) or 0
	if waiting then
		-- Keep progress and newly resolved titles behind this sender's earlier
		-- event. Appending never moves the original deadline or adds a timer.
		if now >= waiting.startedAt and now < waiting.deadline and cache.waitingCount < MAX_TITLE_WAITERS then
			waiting.events[#waiting.events + 1] = event
			cache.waitingCount = cache.waitingCount + 1
			return true
		end
		-- An overflow or elapsed deadline cannot let this event overtake its
		-- predecessors. Other players and quests remain independent.
		FinishAnnouncements(self, cache, key, waiting)
		if rawget(self, "localizedQuestTitles") == cache and self.isEnabled and not self.isLoggingOut then
			self:HandleAnnouncementEvent(event, false, true)
		end
		return true
	end
	if not waitingForTitle or self:IsWorkBlocked("quest_snapshot_refresh") then return false end
	local entry = cache.entries[id]
	-- A failed, unavailable, or budget-limited load should not delay presentation.
	if not entry or not entry.requestedAt or now < entry.requestedAt or now - entry.requestedAt >= TITLE_WAIT_SECONDS
		or (cache.waitingCount or 0) >= MAX_TITLE_WAITERS then return false end
	cache.waiting, cache.waitingCount = cache.waiting or {}, (cache.waitingCount or 0) + 1
	cache.waitingSerial = (cache.waitingSerial or 0) + 1
	waiting = {
		events = { event }, questID = id, owner = self:NewRuntimeWorkOwner(), sequence = cache.waitingSerial,
		startedAt = entry.requestedAt, deadline = entry.requestedAt + TITLE_WAIT_SECONDS,
		workKey = "localized_announcement:" .. cache.waitingSerial,
	}
	cache.waiting[key] = waiting
	local queued = self:ScheduleRuntimeWork("announcement_presentation", waiting.workKey, function()
		FinishAnnouncements(self, cache, key, waiting)
	end, { owner = waiting.owner, delay = TITLE_WAIT_SECONDS - (now - entry.requestedAt), reason = "localized_announcement_wait" })
	if not queued then
		cache.waiting[key], cache.waitingCount = nil, cache.waitingCount - 1
		self:CancelRuntimeWorkOwner(waiting.owner)
	end
	return queued == true
end

function QT:QUEST_DATA_LOAD_RESULT(_, questID, success)
	local id = Integer(self, questID, 1, 1000000000)
	local cache = rawget(self, "localizedQuestTitles")
	if not id or not cache or not self:CanAccessValue(success) or type(success) ~= "boolean" then return end
	local entry = cache.entries[id]
	if entry then entry.requestedAt = nil end
	local ready = {}
	for key, waiting in pairs(cache.waiting or {}) do
		if waiting.questID == id then
			ready[#ready + 1] = { key = key, waiting = waiting }
		end
	end
	table.sort(ready, function(a, b) return a.waiting.sequence < b.waiting.sequence end)
	for _, row in ipairs(ready) do
		local key, waiting = row.key, row.waiting
		self:ScheduleRuntimeWork("announcement_presentation", waiting.workKey, function()
			FinishAnnouncements(self, cache, key, waiting)
		end, { owner = waiting.owner, mode = "nextFrame", reason = "localized_quest_title_loaded" })
	end
	if not success then return end
	-- Retain positive cache entries and load budgets, but still notify views:
	-- another surface may already have resolved this title before the event.
	self:InvalidateLocalizedQuestTitle(id)
	self:NotifyLocalizedQuestTitleChanged(id)
end

-- Presentation resolver only. Keep GetQuestTitle snapshot-only for scan/plate
-- paths; these guarded native reads belong to explicit text presentation.
function QT:GetQuestDisplayTitle(questID, fallbackTitle)
	local title = self:GetLocalizedQuestTitle(questID)
	if title then return title end
	local fallback = self:NormalizeQuestLinkTitleText(fallbackTitle, questID)
	if fallback ~= "" then return fallback end
	return self:GetQuestTitle(questID)
end

function QT:GetMonitoredQuestCountText(count)
	return string.format(L("Quests monitored by QuestTogether: %d"), count)
end

function QT:LocalizeAnnouncementEvent(event)
	if event.eventType == "LOOKING_FOR_QUEST_PARTNERS" then
		return L("Looking for questing partners") .. " :)"
	end
	-- Objective indexes are not stable across quest stages. Preserve the sender's
	-- readable objective and counts instead of inventing a generic translation
	-- or borrowing the receiver's potentially unrelated objective description.
	if progressEvents[event.eventType] then
		return event.text
	end
	local facts = self:DecodeAnnouncementFacts(event.eventFacts)
	local prefix = prefixes[event.eventType]
	if event.eventType == "SCAN_STATUS" and facts and facts.kind == "s" then
		return self:GetMonitoredQuestCountText(facts.current)
	end
	if event.eventType == "PLAYER_LEVEL_UP" and facts and facts.kind == "l" then
		return L("Level ") .. tostring(facts.current)
	end
	local id = Integer(self, event.questId, 1, 1000000000)
	if not id or not prefix then
		return event.text
	end
	if prefix and facts and facts.kind ~= "q" then
		return event.text
	end
	if prefix then
		-- Event type already identifies these labels. Optional facts can be
		-- omitted by older senders or packet fitting; recognize only exact known
		-- prefixes, never guess a title by splitting arbitrary translated prose.
		local sourceTitle, sourceLocale
		local text = self:SafeTrimString(event.text, "")
		for locale in pairs(locales) do
			if not facts or facts.locale == locale then
				local sourcePrefix = self.TranslateForLocale(prefix, locale)
				if text:sub(1, #sourcePrefix) == sourcePrefix and #text > #sourcePrefix then
					sourceTitle = text:sub(#sourcePrefix + 1)
					sourceLocale = locale
					break
				end
			end
		end
		if not facts and not sourceTitle then return event.text end
		local localTitle = self:GetLocalizedQuestTitle(id)
		local title = localTitle or sourceTitle
		local origin = facts and facts.locale or sourceLocale
		return title and (self.TranslateForLocale(prefix, self:GetEventLocale()) .. title) or event.text,
			not localTitle and origin ~= nil and origin ~= self:GetEventLocale()
	end
end
