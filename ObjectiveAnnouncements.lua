-- Aggregate local progress before any output; receiver events stay immutable.
local QT = _G.QuestTogether
local WINDOW_SECONDS, MAX_PENDING = 0.5, 256
local WORK_CLASS = "objective_announcement"
local progressEvents = { QUEST_PROGRESS = true, WORLD_QUEST_PROGRESS = true, BONUS_OBJECTIVE_PROGRESS = true }
local milestoneEvents = {
	QUEST_READY_TO_TURN_IN = true,
	QUEST_COMPLETED = true,
	WORLD_QUEST_COMPLETED = true,
	BONUS_OBJECTIVE_COMPLETED = true,
}

local function State(addon)
	local state = rawget(addon, "objectiveAnnouncementState")
	if not state then
		state = { pending = {}, count = 0, sequence = 0, owner = addon:NewRuntimeWorkOwner() }
		addon.objectiveAnnouncementState = state
	end
	return state
end

local function Key(questID, index)
	return tostring(questID) .. ":" .. tostring(index)
end

local function Remove(addon, state, entry)
	if state.pending[entry.key] ~= entry then return false end
	state.pending[entry.key] = nil
	state.count = state.count - 1
	addon:CancelRuntimeWork(WORK_CLASS, entry.key)
	return true
end

local function Current(addon, entry)
	local quest = addon:GetPlayerTracker()[entry.questID]
	-- WatchQuest replaces the display snapshot on a rescan but preserves this
	-- owned milestone history. Removal/reacceptance starts a new history table.
	return quest and quest.objectiveProgressHighWater == entry.lifetime
		and addon:GetObjectiveProgressIdentity(quest.objectives and quest.objectives[entry.index]) == entry.identity
end

local function Dispatch(addon, state, entry)
	if not Remove(addon, state, entry) then return false end
	if not addon.isEnabled or addon.isLoggingOut or not Current(addon, entry) then return false end
	return addon:DispatchAnnouncementEvent(entry.event)
end

function QT:ResetObjectiveAnnouncements()
	local state = rawget(self, "objectiveAnnouncementState")
	self.objectiveAnnouncementState = nil
	if state then
		self:CancelRuntimeWorkOwner(state.owner)
		state.pending, state.count = {}, 0
	end
end

function QT:CancelObjectiveAnnouncements(questID, index)
	local state = rawget(self, "objectiveAnnouncementState")
	if not state then return end
	questID = self:NormalizeQuestID(questID)
	if not questID then return end
	for _, entry in pairs(state.pending) do
		if entry.questID == questID and (index == nil or entry.index == index) then Remove(self, state, entry) end
	end
end

function QT:FlushObjectiveAnnouncements(questID)
	local state = rawget(self, "objectiveAnnouncementState")
	questID = self:NormalizeQuestID(questID)
	if not state or not questID then return end
	local entries = {}
	for _, entry in pairs(state.pending) do
		if entry.questID == questID then entries[#entries + 1] = entry end
	end
	table.sort(entries, function(a, b) return a.sequence < b.sequence end)
	for _, entry in ipairs(entries) do Dispatch(self, state, entry) end
end

function QT:PublishPreparedAnnouncement(event, extraData)
	if not self.isEnabled or self.isLoggingOut or type(event) ~= "table" then return false end
	local questID = self:NormalizeQuestID(event.questId)
	if not progressEvents[event.eventType] then
		if milestoneEvents[event.eventType] then
			self:FlushObjectiveAnnouncements(questID)
		elseif event.eventType == "QUEST_REMOVED" then
			self:CancelObjectiveAnnouncements(questID)
		end
		return self:DispatchAnnouncementEvent(event)
	end

	local facts = self:DecodeAnnouncementFacts(event.eventFacts)
	local quest = questID and self:GetPlayerTracker()[questID]
	local identity = facts and facts.index and quest
		and self:GetObjectiveProgressIdentity(quest.objectives and quest.objectives[facts.index])
	if questID and ((self.pendingQuestRemovals and self.pendingQuestRemovals[questID])
		or (self.retiredQuestIds and self.retiredQuestIds[questID])) then return false end
	-- Preview/manual events and old producers without objective facts have no
	-- safe aggregation key. Preserve their normal immediate publication.
	if not facts or not facts.index or not quest or not quest.objectiveProgressHighWater or not identity then
		return self:DispatchAnnouncementEvent(event)
	end
	local state, key = State(self), Key(questID, facts.index)
	local entry = state.pending[key]
	if entry and (entry.lifetime ~= quest.objectiveProgressHighWater or entry.identity ~= identity
		or entry.event.eventType ~= event.eventType) then
		Remove(self, state, entry)
		entry = nil
	end
	local finished = (facts.kind == "c" and facts.required and facts.current >= facts.required)
		or (facts.kind == "p" and facts.current == 100) or (facts.kind == "o" and facts.current == 1)
	if self:CanAccessTable(extraData) and type(extraData) == "table"
		and self:CanAccessValue(extraData.objectiveFinished) and extraData.objectiveFinished == true then
		finished = true
	end
	if entry then
		-- Replace the whole captured record, including source time, facts and
		-- coordinates. Never rebuild an old observation at its later send time.
		entry.event = event
	elseif finished or state.count >= MAX_PENDING then
		self:FlushObjectiveAnnouncements(questID)
		return self:DispatchAnnouncementEvent(event)
	else
		state.sequence = state.sequence + 1
		entry = {
			key = key, questID = questID, index = facts.index, identity = identity,
			lifetime = quest.objectiveProgressHighWater, event = event, sequence = state.sequence,
		}
		state.pending[key], state.count = entry, state.count + 1
		local queued = self:ScheduleRuntimeWork(WORK_CLASS, key, function()
			if rawget(self, "objectiveAnnouncementState") ~= state or state.pending[key] ~= entry then return end
			-- Removal may precede turn-in in the same frame. Its resolver owns
			-- cancellation; an authoritative turn-in can still flush this record.
			if self.pendingQuestRemovals and self.pendingQuestRemovals[questID] then return end
			if self.retiredQuestIds and self.retiredQuestIds[questID] then Remove(self, state, entry); return end
			Dispatch(self, state, entry)
		end, { mode = "bounded", delay = WINDOW_SECONDS, owner = state.owner, reason = "objective_progress" })
		if not queued then return Dispatch(self, state, entry) end
	end
	if finished then self:FlushObjectiveAnnouncements(questID) end
	return true
end
