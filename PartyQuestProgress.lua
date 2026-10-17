-- One interest-owned objective store for PQL and the focus HUD. Incoming events
-- are applied before display filters; snapshots repair missing detail, not pace it.
local QT = _G.QuestTogether
local progress = { QUEST_PROGRESS = true, WORLD_QUEST_PROGRESS = true, BONUS_OBJECTIVE_PROGRESS = true }
local completed = { QUEST_COMPLETED = true, WORLD_QUEST_COMPLETED = true, BONUS_OBJECTIVE_COMPLETED = true }
local function Now(a)
	return a:GetPartyQuestCompareTime()
end
local function Store(a)
	local s = rawget(a, "partyQuestProgress")
	if not s then
		s = {}
		a.partyQuestProgress = s
	end
	return s
end
local function Key(name, id)
	return name .. ":" .. id
end
local function Listening(a, r, listener)
	return (not listener.requiresGroup or a:IsGroupedSender(r.name)) and (not listener.current or listener.current())
end
local function Current(a, r)
	if not a.isEnabled or a.isLoggingOut or Store(a)[r.key] ~= r or a:IsIgnoredPlayerName(r.name) then
		return false
	end
	for _, listener in pairs(r.listeners) do
		if Listening(a, r, listener) then
			return true
		end
	end
	return false
end
local function Notify(a, r)
	for owner, listener in pairs(r.listeners) do
		if Listening(a, r, listener) then
			listener.callback(r, owner)
		end
	end
end
local function Apply(a, r, event)
	local kind = event.eventType
	if kind == "QUEST_REMOVED" or completed[kind] then
		r.entry, r.objectives, r.state, r.hasEntry = nil, nil, "ready", true
		r.notice = completed[kind] and "Completed" or "Missing"
		return true
	end
	if kind == "QUEST_READY_TO_TURN_IN" then
		r.notice, r.state, r.pendingMilestone = "Ready", "ready", true
		r.nextRequest = 0
		if r.entry then
			r.entry = a:DeepCopy(r.entry)
			r.entry.isComplete = true
		end
		return true
	end
	if kind == "QUEST_ACCEPTED" then
		r.objectives, r.entry, r.notice, r.state, r.hasEntry = nil, nil, nil, "loading", false
		r.pendingMilestone = nil
		r.nextRequest = 0
		return true
	end
	if not progress[kind] then
		return false
	end
	local facts = a:DecodeAnnouncementFacts(event.eventFacts)
	if
		not facts
		or not facts.index
		or facts.index > 20
		or (facts.kind ~= "c" and facts.kind ~= "p" and facts.kind ~= "o")
	then
		return false
	end
	local text = a:CleanQuestCompareObjectiveText(event.text)
	if text == "" then
		return false
	end
	-- Use the sender's wording and index, never another player's quest stage or locale.
	local objective = {
		questId = r.questId,
		objectiveIndex = facts.index,
		text = text,
		kind = facts.kind == "p" and "progressbar" or "event",
		current = facts.kind ~= "o" and facts.current or nil,
		required = facts.kind == "p" and 100 or facts.required,
		finished = facts.kind == "o" and facts.current == 1
			or facts.kind == "p" and facts.current == 100
			or facts.required ~= nil and facts.current >= facts.required,
	}
	local rows, replaced = {}, false
	for _, row in ipairs(r.objectives or {}) do
		if row.objectiveIndex == facts.index then
			-- A changed target can mean a new stage. Retire unverified siblings
			-- until a new full detail snapshot establishes the current stage.
			if a:GetObjectiveProgressIdentity(row.text) ~= a:GetObjectiveProgressIdentity(text) then
				r.objectives = {}
				r.nextRequest = 0
				break
			end
		end
	end
	for _, row in ipairs(r.objectives or {}) do
		if row.objectiveIndex == facts.index then
			rows[#rows + 1] = objective
			replaced = true
		else
			rows[#rows + 1] = row
		end
	end
	if not replaced then
		rows[#rows + 1] = objective
	end
	table.sort(rows, function(x, y)
		return x.objectiveIndex < y.objectiveIndex
	end)
	r.objectives, r.state, r.notice, r.pendingMilestone = rows, "ready", nil, nil
	return true
end
function QT:ApplyPartyQuestProgressEvent(record, event)
	return Apply(self, record, event)
end

function QT:RequestPartyQuestProgress(r)
	if
		not Current(self, r)
		or r.requestId
		or r.requesting
		or Now(self) < (r.nextRequest or 0)
		or (r.lastRequest and Now(self) < r.lastRequest + 5)
	then
		return
	end
	-- Serialize detail transfers per peer, across both views. A busy peer does
	-- not prevent another party member from answering.
	for _, other in pairs(Store(self)) do
		if other ~= r and other.name == r.name and (other.requestId or other.requesting) then
			return
		end
	end
	r.lastRequest, r.nextRequest, r.requesting = Now(self), Now(self) + 30, true
	local start, entry, done = r.serial, nil, false
	local generation = (r.generation or 0) + 1
	r.generation = generation
	local function Valid()
		return Current(self, r) and r.generation == generation
	end
	local grouped = true
	for _, listener in pairs(r.listeners) do
		if Listening(self, r, listener) and not listener.requiresGroup then
			grouped = false
		end
	end
	local sent, id = self:RequestQuestCompare(r.name, {
		objectiveQuestId = r.questId,
		isCurrent = Valid,
		routes = { { distribution = "WHISPER", target = r.name, requiresGroup = grouped } },
		onEntry = function(value)
			if Valid() then
				entry = value
			end
		end,
		onDone = function()
			done = true
			if not Valid() then
				return
			end
			r.requestId, r.requesting, r.state, r.hasEntry = nil, nil, "ready", true
			r.nextRequest, r.pendingMilestone = Now(self) + 30, nil
			r.entry, r.objectives = entry, entry and entry.objectives
			r.notice = not entry and (r.notice == "Completed" and "Completed" or "Not in log")
				or entry.isComplete and "Ready"
				or nil
			-- Events observed while this snapshot was in flight take precedence.
			for _, item in ipairs(r.events) do
				if item.serial > start then
					Apply(self, r, item.event)
				end
			end
			r.events, r.updatedAt = {}, Now(self)
			Notify(self, r)
		end,
		onTimeout = function()
			done = true
			if not Valid() then
				return
			end
			r.requestId, r.requesting, r.events = nil, nil, {}
			r.nextRequest = Now(self) + 30
			if r.serial == start or (not r.objectives and not r.notice) then
				r.state = "unknown"
				if r.notice ~= "Completed" then
					r.notice = nil
				end
			end
			Notify(self, r)
		end,
	})
	r.requesting = nil
	if sent and not done then
		r.requestId = id
	elseif not sent and not done then
		r.state = (r.objectives or r.notice) and "ready" or "unknown"
		Notify(self, r)
	end
end
function QT:AcquirePartyQuestProgress(name, id, owner, callback, requiresGroup, isCurrent)
	name, id = self:NormalizeMemberName(name), self:NormalizeQuestID(id)
	if not name or not id or self:IsIgnoredPlayerName(name) then
		return
	end
	local store, key = Store(self), Key(name, id)
	local r = store[key]
	if not r then
		r = {
			key = key,
			name = name,
			questId = id,
			state = "loading",
			listeners = {},
			events = {},
			clocks = {},
			serial = 0,
		}
		store[key] = r
	end
	r.listeners[owner] = { callback = callback, requiresGroup = requiresGroup == true, current = isCurrent }
	self:RequestPartyQuestProgress(r)
	return r
end
function QT:HasPendingPartyQuestProgress(owner)
	for _, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		if r.listeners[owner] and (r.requestId or r.requesting or r.state == "loading") then
			return true
		end
	end
	return false
end

function QT:ReleasePartyQuestProgress(owner, questId)
	for key, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		if not questId or r.questId == questId then
			r.listeners[owner] = nil
			if not next(r.listeners) then
				Store(self)[key] = nil
				if r.requestId and self.pendingQuestCompareRequests then
					self:ClearPendingQuestCompare(r.requestId, self.pendingQuestCompareRequests[r.requestId])
				end
				r.requestId, r.requesting, r.entry, r.objectives = nil, nil, nil, nil
				r.state, r.events, r.clocks = "unknown", {}, {}
			end
		end
	end
end
function QT:ObservePartyQuestProgress(event, sender, context)
	local id = self:NormalizeQuestID(event.questId)
	sender = self:NormalizeMemberName(sender)
	local r = sender and id and (rawget(self, "partyQuestProgress") or {})[Key(sender, id)]
	if not r or not Current(self, r) then
		return
	end
	local facts = self:DecodeAnnouncementFacts(event.eventFacts)
	local index = progress[event.eventType] and facts and facts.index or 0
	local stamp = self:SafeToNumber(event.occurredAt) or 0
	local sequence, epoch = self:SafeToNumber(context and context.sequence) or 0, context and context.session
	-- Order each objective separately: out-of-order updates to different rows
	-- are still useful. A lifecycle event establishes a barrier for all rows.
	local clock = r.clocks[index]
	local barrier = r.clocks[0]
	local function Older(c)
		return c
			and (stamp < c.stamp or (stamp == c.stamp and epoch == c.epoch and sequence > 0 and sequence <= c.sequence))
	end
	if index == 0 then
		for _, previous in pairs(r.clocks) do
			if Older(previous) then
				return
			end
		end
	end
	if Older(clock) or (index ~= 0 and Older(barrier)) then
		return
	end
	if not Apply(self, r, event) then
		return
	end
	r.clocks[index] = { stamp = stamp, sequence = sequence, epoch = epoch }
	r.serial = r.serial + 1
	if r.requestId or r.requesting then
		for i = #r.events, 1, -1 do
			if index == 0 or r.events[i].index == index then
				table.remove(r.events, i)
			end
		end
		if #r.events < 21 then
			r.events[#r.events + 1] = { index = index, serial = r.serial, event = self:DeepCopy(event) }
		end
	end
	r.updatedAt = Now(self)
	Notify(self, r)
end
function QT:UpdatePartyQuestProgress()
	local records = {}
	for _, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		records[#records + 1] = r
	end
	table.sort(records, function(a, b)
		return (a.nextRequest or 0) < (b.nextRequest or 0)
	end)
	for _, r in ipairs(records) do
		for owner, listener in pairs(r.listeners) do
			if not Current(self, r) or not Listening(self, r, listener) then
				self:ReleasePartyQuestProgress(owner, r.questId)
			end
		end
		self:RequestPartyQuestProgress(r)
	end
end
function QT:ResetPartyQuestProgress()
	for _, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		for owner in pairs(r.listeners) do
			self:ReleasePartyQuestProgress(owner)
		end
	end
	self.partyQuestProgress = nil
end
