-- Party membership owns accepted quest data and background refreshes. Views
-- subscribe to these records; opening or closing a view does not own the sync.
local QT = _G.QuestTogether
local REFRESH_SECONDS, MAX_QUESTS = 30, 100
local lifecycle = {
	QUEST_ACCEPTED = true,
	QUEST_REMOVED = true,
	QUEST_READY_TO_TURN_IN = true,
	QUEST_COMPLETED = true,
	WORLD_QUEST_COMPLETED = true,
	BONUS_OBJECTIVE_COMPLETED = true,
}
local completed = { QUEST_COMPLETED = true, WORLD_QUEST_COMPLETED = true, BONUS_OBJECTIVE_COMPLETED = true }

local function Now(a)
	return a:GetPartyQuestCompareTime()
end
local function Allowed(a)
	if not a.isEnabled or a.isLoggingOut then return false end
	local communication = rawget(a, "communicationState")
	if communication and communication.departing then return false end
	local getter = a.API and a.API.IsInRaid
	if type(getter) ~= "function" then return false end
	local ok, raid = pcall(getter)
	return ok and a:CanAccessValue(raid) and raid == false and #(a.partyMemberOrder or {}) <= 5
end
local function LifetimeCurrent(a, state)
	local db = rawget(a, "db")
	return state.profile == (db and db.profile)
		and state.worldGeneration == (rawget(a, "commsWorldGeneration") or 0)
end
local function Current(a, state, member)
	return Allowed(a) and rawget(a, "partyQuestSyncState") == state
		and LifetimeCurrent(a, state)
		and state.members[member.name] == member and not member.retired
		and a:IsGroupedSender(member.name) and not a:IsIgnoredPlayerName(member.name)
end
local function Notify(a)
	if a.QueuePartyQuestCompareRender then a:QueuePartyQuestCompareRender() end
	if a.QueueQuestFocusRefresh then a:QueueQuestFocusRefresh() end
end
local function CancelRequest(a, member)
	local id = member.requestId
	member.requestId, member.requesting, member.refreshToken = nil, nil, nil
	if id then
		local pending = a.pendingQuestCompareRequests and a.pendingQuestCompareRequests[id]
		a:ClearPendingQuestCompare(id, pending)
	end
end
local function Retire(a, state, member)
	state.members[member.name], member.retired = nil, true
	CancelRequest(a, member)
	a:ReleasePartyQuestProgress(member)
	a:CancelPartyQuestCompletionRequest(member)
	member.detailTokens, member.objectiveDetails, member.events, member.clocks = {}, {}, {}, {}
end
local function Count(records)
	local count = 0
	for _ in pairs(records) do count = count + 1 end
	return count
end

-- Changes to a certified summary revoke its revision. An event can establish
-- ownership of its own quest, but cannot establish absence in an incomplete log.
local function ApplyEvent(a, member, event)
	local id = a:NormalizeQuestID(event.questId)
	local entry, kind = member.entries[id], event.eventType
	if kind == "QUEST_REMOVED" or completed[kind] then
		a:UpdatePartyQuestMemberEntry(member, id, nil)
	elseif kind == "QUEST_ACCEPTED" then
		if not entry and Count(member.entries) >= MAX_QUESTS then
			member.state = "unknown"
			return
		end
		a:UpdatePartyQuestMemberEntry(member, id, { questId = id, questTitle = entry and entry.questTitle or "" })
	elseif kind == "QUEST_READY_TO_TURN_IN" then
		if not entry and Count(member.entries) >= MAX_QUESTS then
			member.state = "unknown"
			return
		end
		local copy = {}
		for key, value in pairs(entry or {}) do copy[key] = value end
		copy.questId, copy.questTitle, copy.isComplete = id, copy.questTitle or "", true
		a:UpdatePartyQuestMemberEntry(member, id, copy)
	end
	-- Even an idempotent lifecycle event is new evidence relative to a response
	-- being assembled; never certify a locally reconstructed list with its token.
	member.revision = nil
end

local function SyncDetails(a, state, member)
	for id in pairs(member.detailTokens) do
		if not member.entries[id] or not member.supportsObjectives then
			member.detailTokens[id], member.objectiveDetails[id] = nil, nil
			a:ReleasePartyQuestProgress(member, id)
		end
	end
	if not member.supportsObjectives then return end
	for id in pairs(member.entries) do
		if not member.detailTokens[id] then
			local token = {}
			member.detailTokens[id] = token
			local function Valid()
				return Current(a, state, member) and member.detailTokens[id] == token
			end
			local function Updated(detail)
				if not Valid() then return end
				member.objectiveDetails[id] = detail
				if detail.hasEntry and (not member.sampledAt
					or (detail.updatedAt and detail.updatedAt >= member.sampledAt)) then
					a:UpdatePartyQuestMemberEntry(member, id, detail.entry)
				end
				Notify(a)
			end
			local detail = a:AcquirePartyQuestProgress(member.name, id, member, Updated, true, Valid, { background = true })
			if detail then
				Updated(detail)
			else
				member.detailTokens[id] = nil
			end
		end
	end
end

function QT:GetPartyQuestSyncMember(name)
	name = self:NormalizeMemberName(name)
	local state = rawget(self, "partyQuestSyncState")
	local member = state and name and state.members[name]
	return member and Current(self, state, member) and member or nil
end

function QT:RefreshPartyQuestSyncMember(name, force)
	local member = self:GetPartyQuestSyncMember(name)
	if not member then return false end
	local now, state = Now(self), self.partyQuestSyncState
	if force then member.nextRequest, member.forceRefresh = 0, true end
	if member.requestId or member.requesting or now < (member.nextRequest or 0) then return false end
	-- Summary, detail and history transfers share a peer's available bandwidth.
	-- A forced UI refresh makes this due without retiring another useful fetch.
	for _, pending in pairs(rawget(self, "pendingQuestCompareRequests") or {}) do
		if pending.targetName == member.name then return false end
	end
	force, member.forceRefresh = member.forceRefresh == true, nil
	local token, entries, done, startSerial = {}, {}, false, member.serial
	member.refreshToken, member.requesting, member.refreshStatus = token, true, "loading"
	member.lastRequest, member.nextRequest, member.lastError = now, now + REFRESH_SECONDS, nil
	if not member.sampledAt then member.state = "loading" end
	local function Valid()
		return Current(self, state, member) and member.refreshToken == token
	end
	local function Failed(reason)
		done = true
		if not Valid() then return end
		member.requestId, member.requesting, member.refreshToken = nil, nil, nil
		member.refreshStatus, member.lastError, member.nextRequest = reason, reason, Now(self) + REFRESH_SECONDS
		member.events, member.eventOverflow = {}, nil
		if not member.sampledAt then member.state = reason == "timeout" and "timeout" or "unavailable" end
		Notify(self)
	end
	local sent, requestId = self:RequestQuestCompare(member.name, {
		background = not force,
		routes = self:GetQuestCompareRoutes(member.name, true),
		isCurrent = Valid,
		knownRevision = not force and member.revision or nil,
		previousEntries = not force and member.revision and member.entries or nil,
		onEntry = function(entry)
			if not Valid() then return end
			local id = self:NormalizeQuestID(entry.questId)
			if id and (entries[id] or Count(entries) < MAX_QUESTS) then entries[id] = entry end
		end,
		onDone = function(supportsShareRequests, supportsObjectives, classFile, revision, supportsQuestHistory)
			done = true
			if not Valid() then return end
			member.requestId, member.requesting, member.refreshToken = nil, nil, nil
			if member.eventOverflow then
				-- The bounded journal cannot reconcile this response safely. Keep
				-- the accepted live observations and ask for a newer baseline.
				member.events, member.eventOverflow = {}, nil
				member.refreshStatus, member.nextRequest = "stale", Now(self) + 1
				Notify(self)
				return
			end
			self:SetPartyQuestMemberSnapshot(member, entries, revision, Now(self))
			member.state, member.refreshStatus, member.lastError = "ready", "ready", nil
			member.supportsShareRequests, member.supportsObjectives = supportsShareRequests, supportsObjectives
			member.supportsQuestHistory = supportsQuestHistory == true
			if classFile and classFile ~= "" then member.classFile = classFile end
			local replay = {}
			for _, observed in pairs(member.events) do
				if observed.serial > startSerial then replay[#replay + 1] = observed end
			end
			table.sort(replay, function(a, b) return a.serial < b.serial end)
			for _, observed in ipairs(replay) do
				if observed.reset and observed.event.eventType == "QUEST_READY_TO_TURN_IN" then
					ApplyEvent(self, member, { questId = observed.event.questId, eventType = "QUEST_ACCEPTED" })
				end
				ApplyEvent(self, member, observed.event)
			end
			member.events, member.nextRequest = {}, Now(self) + REFRESH_SECONDS
			if self.ReconcilePartyQuestProgress then self:ReconcilePartyQuestProgress(member, member.entries) end
			SyncDetails(self, state, member)
			local session = rawget(self, "partyQuestCompareSession")
			if session and session.byName[member.name] == member then self:LoadPartyQuestObjectives(member) end
			Notify(self)
		end,
		onTimeout = function() Failed("timeout") end,
	})
	member.requesting = nil
	if sent and not done and Valid() then
		member.requestId = requestId
	elseif not sent and not done then
		Failed("unavailable")
	end
	return sent == true
end

function QT:ObservePartyQuestSyncEvent(event, sender, context)
	if not lifecycle[event.eventType] then return end
	local member = self:GetPartyQuestSyncMember(sender)
	local id = self:NormalizeQuestID(event.questId)
	if not member or not id then return end
	local stamp = self:SafeToNumber(event.occurredAt) or 0
	local sequence, epoch = self:SafeToNumber(context and context.sequence) or 0, context and context.session
	local prior = member.clocks[id]
	if prior and (stamp < prior.stamp or (stamp == prior.stamp and epoch == prior.epoch
		and sequence > 0 and sequence <= prior.sequence)) then return end
	if not prior and Count(member.clocks) >= MAX_QUESTS then
		local oldestID, oldest
		for questID, clock in pairs(member.clocks) do
			if not oldest or clock.serial < oldest then oldestID, oldest = questID, clock.serial end
		end
		member.clocks[oldestID] = nil
	end
	member.serial = member.serial + 1
	member.clocks[id] = { stamp = stamp, sequence = sequence, epoch = epoch, serial = member.serial }
	if member.requestId or member.requesting then
		if member.events[id] or Count(member.events) < MAX_QUESTS then
			local reset = event.eventType ~= "QUEST_READY_TO_TURN_IN" or (member.events[id] and member.events[id].reset)
			member.events[id] = { serial = member.serial, reset = reset,
				event = { questId = id, eventType = event.eventType } }
		else
			member.eventOverflow = true
		end
	end
	ApplyEvent(self, member, event)
	member.nextRequest = math.min(member.nextRequest or 0, Now(self) + 1)
	SyncDetails(self, self.partyQuestSyncState, member)
	Notify(self)
end

function QT:UpdatePartyQuestSync()
	if not Allowed(self) then
		self:ResetPartyQuestSync()
		self:ReconcilePartyQuestCompareSources()
		return
	end
	local own = self:NormalizeMemberName(self:GetPlayerFullName())
	if not own then self:ResetPartyQuestSync(); return end
	local state = rawget(self, "partyQuestSyncState")
	if state and not LifetimeCurrent(self, state) then self:ResetPartyQuestSync(); state = nil end
	if not state then
		local db = rawget(self, "db")
		state = { members = {}, profile = db and db.profile, worldGeneration = rawget(self, "commsWorldGeneration") or 0 }
		self.partyQuestSyncState = state
	end
	local wanted, names = {}, {}
	for _, name in ipairs(self.partyMemberOrder or {}) do
		name = self:NormalizeMemberName(name)
		if name and name ~= own and not wanted[name] and self:IsGroupedSender(name) and not self:IsIgnoredPlayerName(name)
			and #names < 4 then
			wanted[name], names[#names + 1] = true, name
		end
	end
	for name, member in pairs(state.members) do
		if not wanted[name] then Retire(self, state, member) end
	end
	for index, name in ipairs(names) do
		local member = state.members[name]
		if not member then
			member = { syncOwned = true, name = name, isLocal = false, entries = {}, state = "loading",
				objectiveDetails = {}, detailTokens = {}, events = {}, clocks = {}, serial = 0,
				nextRequest = Now(self) + index * 0.3, classFile = self:GetGroupedSenderClassFile(name) }
			state.members[name] = member
		end
		SyncDetails(self, state, member)
		self:RefreshPartyQuestSyncMember(name)
	end
	self:ReconcilePartyQuestCompareSources()
end

function QT:ResetPartyQuestSync()
	local state = rawget(self, "partyQuestSyncState")
	self.partyQuestSyncState = nil
	for _, member in pairs(state and state.members or {}) do Retire(self, state, member) end
end

function QT:GetPartyQuestSyncDiagnostics()
	local result = { members = 0, quests = 0, objectiveSnapshots = 0, pendingSummaries = 0,
		refreshFailures = 0, oldestSnapshotAge = 0 }
	local state, now = rawget(self, "partyQuestSyncState"), Now(self)
	for _, member in pairs(state and state.members or {}) do
		result.members = result.members + 1
		result.quests = result.quests + Count(member.entries)
		if member.requestId or member.requesting then result.pendingSummaries = result.pendingSummaries + 1 end
		if member.lastError then result.refreshFailures = result.refreshFailures + 1 end
		if member.sampledAt then result.oldestSnapshotAge = math.max(result.oldestSnapshotAge, now - member.sampledAt) end
		for _, detail in pairs(member.objectiveDetails) do
			if detail.hasEntry then result.objectiveSnapshots = result.objectiveSnapshots + 1 end
		end
	end
	return result
end
