-- Party membership owns cached objective data; views only own subscriptions.
-- Incoming events are applied before display filters. Paced snapshots warm the
-- cache and repair missed updates even when neither quest view is open.
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
local function PartyOwned(a, r)
	return r.partyOwner and a:GetPartyQuestSyncMember(r.name) == r.partyOwner
end
local function Current(a, r)
	if not a.isEnabled or a.isLoggingOut or Store(a)[r.key] ~= r or a:IsIgnoredPlayerName(r.name) then
		return false
	end
	if r.partyOwner then return PartyOwned(a, r) == true end
	for _, listener in pairs(r.listeners) do
		if Listening(a, r, listener) then
			return true
		end
	end
	return false
end
local function Viewed(a, r)
	for _, listener in pairs(r.listeners) do
		if not listener.background and Listening(a, r, listener) then return true end
	end
	return false
end
local function Interval(a, r)
	return Viewed(a, r) and 30 or 120
end
local function Retire(a, r)
	Store(a)[r.key] = nil
	if r.requestId and a.pendingQuestCompareRequests then
		a:ClearPendingQuestCompare(r.requestId, a.pendingQuestCompareRequests[r.requestId])
	end
	r.requestId, r.requesting, r.entry, r.objectives = nil, nil, nil, nil
	r.state, r.events, r.clocks, r.listeners = "unknown", {}, {}, {}
end
local function Notify(a, r)
	for owner, listener in pairs(r.listeners) do
		if Listening(a, r, listener) then
			listener.callback(r, owner)
		end
	end
end
local function SameSummary(a, b)
	return a == b or (a and b and (a.questTitle or "") == (b.questTitle or "")
		and (a.isComplete == true) == (b.isComplete == true) and a.isPushable == b.isPushable)
end

-- A newer complete log can invalidate an older detail request without an ANN
-- (for example when that event was dropped). Only a data change cancels this
-- work; closing a view never establishes such a barrier.
function QT:ReconcilePartyQuestProgress(member, entries)
	for _, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		if r.partyOwner == member then
			local entry = entries[r.questId]
			local previous = r.entry
			if r.hasSummary then previous = r.summaryEntry end
			local changed = (r.hasSummary or r.hasEntry) and not SameSummary(previous, entry)
			local first = not r.hasSummary
			local reset = changed or (first and (not entry or entry.isComplete == true))
			if reset then
				r.generation = (r.generation or 0) + 1
				if r.requestId and self.pendingQuestCompareRequests then
					self:ClearPendingQuestCompare(r.requestId, self.pendingQuestCompareRequests[r.requestId])
				end
				r.requestId, r.requesting, r.events, r.lastRequest, r.pendingMilestone = nil, nil, {}, nil, nil
				r.entry, r.objectives, r.hasEntry = entry, nil, entry == nil
				r.state = entry and "loading" or "ready"
				r.notice = not entry and "Not in log" or entry.isComplete and "Ready" or nil
				r.nextRequest = entry and 0 or Now(self) + 120
			end
			if first and entry and not r.entry then r.entry = entry end
			r.summaryEntry, r.hasSummary = entry, true
			if reset or first then Notify(self, r) end
			if not entry then
				-- An event may have created background interest before the first
				-- log snapshot. Confirmed absence retires that interest as well.
				r.listeners[member] = nil
				member.objectiveDetails[r.questId], member.detailTokens[r.questId] = nil, nil
				if not next(r.listeners) then r.detachedAt = Now(self) end
			end
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
		or (PartyOwned(self, r) and Now(self) < (self.partyQuestProgressNextRequest or 0))
	then
		return
	end
	-- Detached views retain their accepted data and in-flight request, but only
	-- the party's background interests or an active view schedule further reads.
	if not next(r.listeners) then return end
	if PartyOwned(self, r) then
		for _, pending in pairs(rawget(self, "pendingQuestCompareRequests") or {}) do
			if pending.targetName == r.name then return end
		end
	end
	-- Serialize detail transfers per peer, across both views. A busy peer does
	-- not prevent another party member from answering.
	for _, other in pairs(Store(self)) do
		if other ~= r and other.name == r.name and (other.requestId or other.requesting) then
			return
		end
	end
	r.lastRequest, r.nextRequest, r.requesting = Now(self), Now(self) + Interval(self, r), true
	if PartyOwned(self, r) then self.partyQuestProgressNextRequest = Now(self) + 0.5 end
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
		background = PartyOwned(self, r) and not Viewed(self, r) or nil,
		objectiveQuestId = r.questId,
		isCurrent = Valid,
		routes = self:GetQuestCompareRoutes(r.name, grouped),
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
			r.nextRequest, r.pendingMilestone = Now(self) + Interval(self, r), nil
			r.refreshError = nil
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
			r.nextRequest, r.refreshError = Now(self) + 30, "timeout"
			if not r.hasEntry and not r.objectives and not r.notice then
				r.state = "unknown"
			end
			Notify(self, r)
		end,
	})
	r.requesting = nil
	if sent and not done then
		r.requestId = id
	elseif not sent and not done then
		r.state = (r.hasEntry or r.objectives or r.notice) and "ready" or "unknown"
		r.refreshError = "unavailable"
		Notify(self, r)
	end
end
function QT:AcquirePartyQuestProgress(name, id, owner, callback, requiresGroup, isCurrent, options)
	name, id = self:NormalizeMemberName(name), self:NormalizeQuestID(id)
	if not name or not id or self:IsIgnoredPlayerName(name) then
		return
	end
	local partyOwner = requiresGroup and self:GetPartyQuestSyncMember(name)
	if requiresGroup and not partyOwner then
		-- A hover can run before the first periodic tick after joining. Establish
		-- membership ownership now so even that first fetch survives unhover.
		self:UpdatePartyQuestSync()
		partyOwner = self:GetPartyQuestSyncMember(name)
	end
	local store, key = Store(self), Key(name, id)
	local r = store[key]
	if r and r.partyOwner and not PartyOwned(self, r) then Retire(self, r); r = nil end
	if not r then
		local count, oldest = 0, nil
		for _, cached in pairs(store) do
			if cached.name == name then
				count = count + 1
				if not next(cached.listeners) and not cached.requestId
					and (not oldest or (cached.updatedAt or 0) < (oldest.updatedAt or 0)) then oldest = cached end
			end
		end
		-- A full party log is at most100 quests. Leave a little room for absent
		-- quests hovered in POT, without allowing arbitrary incoming IDs to grow memory.
		if count >= 128 then
			if not oldest then return end
			Retire(self, oldest)
		end
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
		local member = partyOwner
		if member and member.state == "ready" then
			r.summaryEntry, r.hasSummary = member.entries[id], true
			r.entry = member.entries[id]
			if r.entry and r.entry.isComplete then
				r.state, r.notice, r.pendingMilestone = "ready", "Ready", true
			end
		end
		if member and member.state == "ready" and not member.entries[id] then
			r.state, r.hasEntry, r.notice = "ready", true, "Not in log"
			r.updatedAt, r.nextRequest = Now(self), Now(self) + 120
		end
		store[key] = r
	end
	r.partyOwner = r.partyOwner or partyOwner
	if r.partyOwner and r.partyOwner.entries[id] and r.hasEntry and not r.entry then
		r.hasEntry, r.state, r.notice, r.nextRequest = false, "loading", nil, 0
	end
	r.listeners[owner] = { callback = callback, requiresGroup = requiresGroup == true, current = isCurrent,
		background = options and options.background == true }
	if not (options and options.background) then
		r.lastViewed = Now(self)
		-- A newly visible record gets the faster repair cadence without replacing
		-- a pending request or throwing away its last successful snapshot.
		if r.lastRequest then r.nextRequest = math.min(r.nextRequest or 0, r.lastRequest + 30) end
		self:RequestPartyQuestProgress(r)
	end
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
				if PartyOwned(self, r) then r.detachedAt = Now(self) else Retire(self, r) end
			end
		end
	end
end
function QT:ObservePartyQuestProgress(event, sender, context)
	local id = self:NormalizeQuestID(event.questId)
	sender = self:NormalizeMemberName(sender)
	local r = sender and id and (rawget(self, "partyQuestProgress") or {})[Key(sender, id)]
	local member = sender and id and self:GetPartyQuestSyncMember(sender)
	if not r and member then
		-- Even an unviewed quest can receive a useful event before its full log
		-- arrives. Retain it and let the summary/background scan establish detail.
		r = self:AcquirePartyQuestProgress(sender, id, member, function(detail)
			member.objectiveDetails[id] = detail
			self:QueueQuestFocusRefresh()
			self:QueuePartyQuestCompareRender()
		end, true, function() return self:GetPartyQuestSyncMember(sender) == member end, { background = true })
	end
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
	return true
end
function QT:UpdatePartyQuestProgress()
	local records = {}
	local own = self:GetQuestSnapshotByQuestID()
	for _, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		records[#records + 1] = r
	end
	table.sort(records, function(a, b)
		local av, bv = Viewed(self, a), Viewed(self, b)
		if av ~= bv then return av end
		local au, bu = a.hasEntry ~= true, b.hasEntry ~= true
		if au ~= bu then return au end
		local ashared, bshared = own[a.questId] ~= nil, own[b.questId] ~= nil
		if ashared ~= bshared then return ashared end
		local an, bn = a.nextRequest or 0, b.nextRequest or 0
		if an ~= bn then return an < bn end
		return a.key < b.key
	end)
	for _, r in ipairs(records) do
		if not Current(self, r) or (not next(r.listeners) and not r.requestId and not r.requesting
			and Now(self) - (r.detachedAt or Now(self)) > 120) then
			Retire(self, r)
		else
			for owner, listener in pairs(r.listeners) do
				if not Listening(self, r, listener) then self:ReleasePartyQuestProgress(owner, r.questId) end
			end
			self:RequestPartyQuestProgress(r)
		end
	end
end
function QT:ResetPartyQuestProgress()
	for _, r in pairs(rawget(self, "partyQuestProgress") or {}) do
		Retire(self, r)
	end
	self.partyQuestProgress, self.partyQuestProgressNextRequest = nil, nil
end
