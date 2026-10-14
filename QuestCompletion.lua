local QuestTogether = _G.QuestTogether
local MAX_INTEREST = 100
local MAX_QUERY = 32
local HISTORY_LIFETIME = 60
local HISTORY_STATUS = { active = true, completed = true, incomplete = true, repeatable = true, unknown = true }

local function QuestID(value)
	return type(value) == "number" and value >= 1 and value <= 1000000000 and value % 1 == 0 and value or nil
end

-- History is separate from the certified active-log snapshot. A missing history
-- field in an older peer's response never certifies an unfinished quest.
function QuestTogether:ValidateQuestHistoryQuery(records)
	if type(records) ~= "table" or #records < 1 or #records > MAX_QUERY then
		return nil
	end
	local ids, seen = {}, {}
	for _, row in ipairs(records) do
		local id = type(row) == "table" and QuestID(row.questId)
		if not id or seen[id] then
			return nil
		end
		seen[id], ids[#ids + 1] = true, id
	end
	return ids, seen
end

function QuestTogether:ReadCharacterQuestHistoryStatus(id)
	local getter = self.API.GetCharacterQuestHistoryStatus
	if not QuestID(id) or type(getter) ~= "function" or self:IsWorkBlocked("quest_snapshot_refresh") then
		return "unknown"
	end
	local ok, status = pcall(getter, id)
	return ok and self:CanAccessValue(status) and type(status) == "string" and HISTORY_STATUS[status] and status or "unknown"
end

function QuestTogether:CancelPartyQuestCompletionRequest(member)
	local id = member and member.historyRequestId
	if member then
		member.historyRequestToken = nil
	end
	if id then
		member.historyRequestId = nil
		if self.pendingQuestCompareRequests then
			self.pendingQuestCompareRequests[id] = nil
		end
		self:CancelCommRequest(id, "cancelled")
	end
end

function QuestTogether:SetPartyQuestCompletionInterest(questIDs)
	local session = rawget(self, "partyQuestCompareSession")
	if not session then
		return
	end
	local order, ids = {}, {}
	for _, value in ipairs(questIDs or {}) do
		local id = QuestID(value)
		if id and not ids[id] and #order < MAX_INTEREST then
			ids[id], order[#order + 1] = true, id
		end
	end
	session.historyInterests, session.historyInterestOrder = ids, order
	for _, member in ipairs(session.members) do
		local pending = member.historyRequestId and self:GetPendingQuestCompare(member.historyRequestId)
		if pending then
			local interested = false
			for _, row in ipairs(pending.historyQuestIds or {}) do
				interested = interested or ids[row.questId] == true
			end
			if not interested then
				self:CancelPartyQuestCompletionRequest(member)
			end
		end
		for id in pairs(member.questHistory or {}) do
			if not ids[id] then
				member.questHistory[id] = nil
			end
		end
	end
end

function QuestTogether:IsPartyQuestCompletionViewActive(session)
	local frame = rawget(self, "partyQuestCompareWindow")
	if not self.isEnabled or self.isLoggingOut or rawget(self, "partyQuestCompareSession") ~= session
		or not frame or not self:CanMutateOwnedUI(frame) then
		return false
	end
	local ok, visible = pcall(frame.IsVisible, frame)
	return ok and self:CanAccessValue(visible) and visible == true
end

function QuestTogether:GetPartyQuestAbsenceState(member, questID)
	if member.state ~= "ready" then
		return member.state == "loading" and "Loading" or "Unknown"
	end
	local evidence = member.questHistory and member.questHistory[questID]
	local now = self.API.GetTime()
	if evidence and now >= evidence.sampledAt and now < evidence.sampledAt + HISTORY_LIFETIME then
		if evidence.status == "completed" then
			return "Completed"
		elseif evidence.status == "incomplete" or evidence.status == "repeatable" then
			return "Missing"
		elseif evidence.status == "active" then
			-- The character acquired this quest after the installed snapshot.
			return "Unknown"
		end
	end
	return "Absent"
end

function QuestTogether:UpdatePartyQuestCompletion()
	local session = rawget(self, "partyQuestCompareSession")
	if not session then
		return
	end
	if not self:IsPartyQuestCompletionViewActive(session) or self:IsWorkBlocked("quest_snapshot_refresh") then
		for _, member in ipairs(session.members) do
			self:CancelPartyQuestCompletionRequest(member)
		end
		return
	end
	local now = self.API.GetTime()
	if now < (session.nextHistoryUpdate or 0) then
		return
	end
	session.nextHistoryUpdate = now + 1
	local localBudget, requested, changed = 8, false, false
	for _, member in ipairs(session.members) do
		if member.state == "ready" and not self:IsIgnoredPlayerName(member.name) then
			member.questHistory = member.questHistory or {}
			local records = {}
			for _, id in ipairs(session.historyInterestOrder or {}) do
				local previous = member.questHistory[id]
				local fresh = previous and now >= previous.sampledAt and now < previous.sampledAt + HISTORY_LIFETIME
				if previous and not fresh then
					member.questHistory[id] = nil
					changed = true
				end
				if not member.entries[id] and not fresh then
					if member.isLocal and localBudget > 0 then
						localBudget = localBudget - 1
						member.questHistory[id] = { status = self:ReadCharacterQuestHistoryStatus(id), sampledAt = now }
						changed = true
					elseif not member.isLocal and #records < MAX_QUERY then
						records[#records + 1] = { questId = id }
					end
				end
			end
			if not requested and not member.isLocal and member.supportsQuestHistory and not member.historyRequestId
				and #records > 0 and now >= (member.nextHistoryRequest or 0)
				and (session.mode == "target" or self:IsGroupedSender(member.name)) then
				requested = true
				member.nextHistoryRequest = now + 15
				local generation = member.historyGeneration or 0
				local token = {}
				member.historyRequestToken = token
				local function Current()
					return self.isEnabled and not self.isLoggingOut and self.partyQuestCompareSession == session
						and member.historyRequestToken == token
						and self:IsPartyQuestCompletionViewActive(session)
						and session.byName[member.name] == member and (member.historyGeneration or 0) == generation
						and not self:IsIgnoredPlayerName(member.name)
						and (session.mode == "target" or self:IsGroupedSender(member.name))
				end
				local ok, requestId = self:RequestQuestCompare(member.name, {
					historyQuestIds = records,
					routes = { { distribution = "WHISPER", target = member.name, requiresGroup = session.mode ~= "target" } },
					isCurrent = Current,
					onHistory = function(states)
						if not Current() then
							return
						end
						member.historyRequestId, member.historyRequestToken = nil, nil
						local receivedAt, serverTime = self.API.GetTime(), self:GetAnnouncementServerTime()
						for _, row in ipairs(states) do
							if session.historyInterests[row.questId] and not member.entries[row.questId] then
								local age = serverTime and row.sampledAt and serverTime - row.sampledAt
								if age and age >= -2 and age < HISTORY_LIFETIME then
									member.questHistory[row.questId] = { status = row.status, sampledAt = receivedAt - math.max(0, age) }
								end
							end
						end
						self:QueuePartyQuestCompareRender()
					end,
					onTimeout = function()
						if Current() then
							member.historyRequestId, member.historyRequestToken = nil, nil
						end
					end,
				})
				if ok and member.historyRequestToken == token then
					member.historyRequestId = requestId
				elseif not ok and member.historyRequestToken == token then
					member.historyRequestToken = nil
				end
			end
		end
	end
	if changed then
		self:QueuePartyQuestCompareRender()
	end
end

function QuestTogether:HandleQuestHistoryResponse(data, pending)
	local ids, requested = self:ValidateQuestHistoryQuery(pending.historyQuestIds)
	if not ids or data.supportsQuestHistory ~= true or data.unchanged or data.revision or data.objectiveQuestId
		or type(data.historyStates) ~= "table" or data.count ~= #ids or #data.historyStates ~= #ids
		or (data.entries and #data.entries > 0) then
		return false
	end
	local seen = {}
	for _, row in ipairs(data.historyStates) do
		local id = QuestID(row.questId)
		if not id or not requested[id] or seen[id] or not HISTORY_STATUS[row.status]
			or (row.sampledAt ~= nil and (type(row.sampledAt) ~= "number" or row.sampledAt < 1000000000
				or row.sampledAt >= 100000000000 or row.sampledAt % 1 ~= 0)) then
			return false
		end
		seen[id] = true
	end
	self:ClearPendingQuestCompare(data.requestId, pending)
	if pending.receiver and pending.receiver.onHistory then
		pending.receiver.onHistory(data.historyStates)
	end
	return true
end

function QuestTogether:ProgressQuestHistoryResponse(job, budget)
	if self:IsWorkBlocked("quest_snapshot_refresh") then
		return nil, "restricted", 0
	end
	local ids = self:ValidateQuestHistoryQuery(job.data.historyQuestIds)
	if not ids then
		return nil, "invalid", 0
	end
	job.historyStates = job.historyStates or {}
	local used = 0
	while #job.historyStates < #ids and used < budget do
		local id = ids[#job.historyStates + 1]
		job.historyStates[#job.historyStates + 1] = {
			questId = id, status = self:ReadCharacterQuestHistoryStatus(id), sampledAt = self:GetAnnouncementServerTime(),
		}
		used = used + 1
	end
	if #job.historyStates < #ids then
		return nil, "pending", used
	end
	return {}, nil, used
end
