local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local QUEST_COMPARE_MAX_ENTRIES = 100
local function SafeNumber(a, v)
	return a:SafeToNumber(v)
end
local function SafeAddonString(a, v, fallback)
	return a:SafeToString(v, fallback)
end
local function Current(a, request)
	return a.isEnabled
		and not a.isLoggingOut
		and not a:IsIgnoredPlayerName(request.targetName)
		and (not request.requiresGroup or a:IsGroupedSender(request.targetName))
		and (not request.receiver or not request.receiver.isCurrent or request.receiver.isCurrent())
end
function QuestTogether:BuildQuestCompareEntries()
	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then
		return nil, "restricted"
	end
	local entries = {}
	local numQuestLogEntries = SafeNumber(self, self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries())
	if not numQuestLogEntries or numQuestLogEntries < 0 or numQuestLogEntries ~= math.floor(numQuestLogEntries) then
		return nil
	end
	-- Bound reads as well as retained packets. Headers count as rows, so leave
	-- ample room above the maximum number of shareable quest entries.
	if numQuestLogEntries > QUEST_COMPARE_MAX_ENTRIES * 5 then
		return nil, "limit"
	end
	local seenQuestIds = {}

	for questLogIndex = 1, numQuestLogEntries do
		local questInfo = self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if type(questInfo) ~= "table" or not self:CanAccessTable(questInfo) then
			return nil
		end
		if not self:CanAccessValue(questInfo.isHeader) or not self:CanAccessValue(questInfo.isHidden) then
			return nil
		end
		local questId = self:NormalizeQuestID(questInfo.questID)
		if not questInfo.isHeader and not questId then
			return nil
		end
		if not questInfo.isHeader and not questInfo.isHidden then
			local questTitle = self:SafeTrimString(questInfo.title, "")
			if questTitle == "" then
				return nil
			end
			-- Duplicate IDs can indicate rows shifted during the scan. A receiver
			-- deduplicates IDs, so advertising duplicates would never complete.
			if seenQuestIds[questId] then
				return nil
			end
			seenQuestIds[questId] = true
			if #entries >= QUEST_COMPARE_MAX_ENTRIES then
				return nil, "limit"
			end
			local shareableLabel = self:GetQuestShareableStatusLabel(questId)
			local isPushable
			if shareableLabel == "Yes" then
				isPushable = true
			elseif shareableLabel == "No" then
				isPushable = false
			end
			-- Blizzard's quest tracker uses QuestMixin:IsComplete(), backed by
			-- C_QuestLog.IsComplete. GetInfo/legacy title flags can disagree (for
			-- example delivery quests), so keep their flag only as a fallback.
			local complete = self:CanAccessValue(questInfo.isComplete) and questInfo.isComplete == true or false
			if type(self.API.IsQuestComplete) == "function" then
				local ok, value = pcall(self.API.IsQuestComplete, questId)
				if ok and self:CanAccessValue(value) and type(value) == "boolean" then
					complete = value
				end
			end
			entries[#entries + 1] = {
				questId = SafeAddonString(self, questId, ""),
				questTitle = questTitle,
				isComplete = complete,
				isPushable = isPushable,
			}
		end
	end
	local finalCount = SafeNumber(self, self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries())
	if finalCount ~= numQuestLogEntries then
		return nil
	end

	return entries
end

function QuestTogether:BuildRevisionedQuestCompareEntries(objectiveQuestId)
	local entries, reason = self:BuildQuestCompareResponseEntries(objectiveQuestId)
	if not entries or objectiveQuestId then
		return entries, reason
	end
	local fields = {}
	for _, entry in ipairs(entries) do
		fields[#fields + 1] = table.concat({
			tostring(entry.questId),
			tostring(#(entry.questTitle or "")) .. ":" .. (entry.questTitle or ""),
			entry.isComplete and "1" or "0",
			entry.isPushable == nil and "?" or (entry.isPushable and "1" or "0"),
		}, ",")
	end
	table.sort(fields)
	local fingerprint = table.concat(fields, ";")
	local previous, now = rawget(self, "questCompareLocalRevision"), self.API.GetTime()
	local generation = rawget(self, "commsWorldGeneration") or 0
	if
		previous
		and previous.generation == generation
		and now >= previous.createdAt
		and previous.fingerprint == fingerprint
	then
		return previous.entries
	end
	self.questCompareRevisionSequence = (rawget(self, "questCompareRevisionSequence") or 0) + 1
	local revision = string.format(
		"%.0f-%.0f-%d-%.0f",
		self:GetAnnouncementServerTime() or 0,
		math.floor(now * 1000),
		self.API.Random(1, 1000000000),
		self.questCompareRevisionSequence
	)
	local copy = {}
	for index, entry in ipairs(entries) do
		copy[index] = {
			questId = entry.questId,
			questTitle = entry.questTitle,
			isComplete = entry.isComplete,
			isPushable = entry.isPushable,
		}
	end
	copy.revision = revision
	self.questCompareLocalRevision =
		{ entries = copy, fingerprint = fingerprint, createdAt = now, generation = generation }
	return copy
end

function QuestTogether:GetPendingQuestCompare(id)
	return self.pendingQuestCompareRequests and self.pendingQuestCompareRequests[id]
end
function QuestTogether:ClearPendingQuestCompare(id, pending)
	if self.pendingQuestCompareRequests and self.pendingQuestCompareRequests[id] == pending then
		self.pendingQuestCompareRequests[id] = nil
	end
	self:CancelCommRequest(id, "completed")
end

-- A response is one immutable object. No rows become visible until all fragments,
-- schema checks and the requested revision have been validated.
function QuestTogether:HandleQuestCompareResponse(data, sender)
	local pending = self:GetPendingQuestCompare(data.requestId)
	if not pending or pending.targetName ~= sender or not Current(self, pending) then
		return false
	end
	if pending.historyQuestIds then
		return self:HandleQuestHistoryResponse(data, pending)
	elseif data.historyStates then
		return false
	end
	if data.objectiveQuestId ~= pending.objectiveQuestId then
		return false
	end
	local entries, order = {}, {}
	if data.unchanged then
		if
			pending.objectiveQuestId
			or not pending.previousEntries
			or data.revision ~= pending.knownRevision
			or data.count ~= #pending.previousOrder
			or (data.entries and #data.entries > 0)
		then
			return false
		end
		entries, order = pending.previousEntries, pending.previousOrder
	else
		if type(data.entries) ~= "table" or #data.entries > 100 or data.count ~= #data.entries then
			return false
		end
		if pending.objectiveQuestId and #data.entries > 1 then
			return false
		end
		for _, row in ipairs(data.entries) do
			local id = self:NormalizeQuestID(row.questId)
			if
				not id
				or entries[id]
				or (pending.objectiveQuestId and id ~= pending.objectiveQuestId)
				or type(row.questTitle) ~= "string"
				or row.questTitle == ""
			then
				return false
			end
			if row.objectives then
				if not pending.objectiveQuestId or row.objectiveCount ~= #row.objectives then
					return false
				end
				for index, objective in ipairs(row.objectives) do
					if
						objective.questId ~= id
						or objective.objectiveIndex ~= index
						or not objective.text
						or objective.text == ""
						or (objective.current and (objective.current < 0 or objective.current % 1 ~= 0))
						or (objective.required and (objective.required < 0 or objective.required % 1 ~= 0))
					then
						return false
					end
				end
			elseif row.objectiveCount then
				return false
			end
			row.senderName = sender
			row.classFile = data.classFile
			entries[id], order[#order + 1] = row, id
		end
	end
	self:ClearPendingQuestCompare(data.requestId, pending)
	for _, id in ipairs(order) do
		if pending.receiver then
			pending.receiver.onEntry(entries[id])
		elseif self.PrintQuestCompareMessage then
			self:PrintQuestCompareMessage(sender, entries[id], data.classFile)
		end
	end
	if pending.receiver then
		pending.receiver.onDone(true, true, data.classFile, data.revision, data.supportsQuestHistory == true)
	elseif self.PrintQuestCompareDone then
		self:PrintQuestCompareDone(sender, #order, data.classFile)
	end
	return true
end

function QuestTogether:RequestQuestCompare(speakerName, receiver)
	local target = self:NormalizeMemberName(speakerName)
	if not self.isEnabled or not target or self:IsIgnoredPlayerName(target) then
		return false
	end
	if receiver and receiver.historyQuestIds and (receiver.objectiveQuestId or receiver.knownRevision
		or not self:ValidateQuestHistoryQuery(receiver.historyQuestIds)) then
		return false
	end
	if self:IsSelfSender(target) then
		-- Local completion reads have their own bounded runtime cadence; do not
		-- route a history-only receiver through the active-log callbacks.
		if receiver and receiver.historyQuestIds then
			return false
		end
		local entries = self:BuildQuestCompareEntries()
		if not entries then
			return false
		end
		for _, entry in ipairs(entries) do
			if receiver then
				receiver.onEntry(entry)
			else
				self:PrintQuestCompareMessage(target, entry, self:GetPlayerClassFile())
			end
		end
		if receiver then
			receiver.onDone(true, true, self:GetPlayerClassFile())
		else
			self:PrintQuestCompareDone(target, #entries, self:GetPlayerClassFile())
		end
		return true
	end
	local id = self:BuildChannelRequestId("qcmp")
	local routes = receiver and receiver.routes or { { distribution = "WHISPER", target = target } }
	local pending = {
		targetName = target,
		receiver = receiver,
		startedAt = self.API.GetTime(),
		objectiveQuestId = receiver and receiver.objectiveQuestId,
		historyQuestIds = receiver and receiver.historyQuestIds,
		requiresGroup = routes[1] and routes[1].requiresGroup,
		classFile = self:GetGroupedSenderClassFile(target),
	}
	if
		receiver
		and type(receiver.knownRevision) == "string"
		and #receiver.knownRevision <= 64
		and receiver.previousEntries
		and not receiver.objectiveQuestId
	then
		local entries, order = {}, {}
		for key, entry in pairs(receiver.previousEntries) do
			local qid = self:NormalizeQuestID(key)
			if qid and type(entry) == "table" and self:NormalizeQuestID(entry.questId) == qid then
				local copy = {}
				for k, v in pairs(entry) do
					copy[k] = v
				end
				entries[qid], order[#order + 1] = copy, qid
			end
		end
		if #order <= 100 then
			pending.knownRevision, pending.previousEntries, pending.previousOrder =
				receiver.knownRevision, entries, order
		end
	end
	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	self.pendingQuestCompareRequests[id] = pending
	local function Active()
		return self:GetPendingQuestCompare(id) == pending and Current(self, pending)
	end
	local function Expire()
		if self:GetPendingQuestCompare(id) ~= pending then
			return
		end
		self.pendingQuestCompareRequests[id] = nil
		if receiver then
			receiver.onTimeout()
		elseif self.isEnabled then
			self:PrintConsoleAnnouncement(
				string.format(L("Quest comparison timed out (%d quests received)."), 0),
				target,
				pending.classFile,
				"QUEST_PROGRESS"
			)
		end
	end
	local ok = self:Request("QCMP", {
		requestId = id,
		targetName = target,
		objectiveQuestId = pending.objectiveQuestId,
		knownRevision = pending.knownRevision,
		partyOnly = pending.requiresGroup == true,
		historyQuestIds = pending.historyQuestIds,
	}, routes, { owner = pending, isCurrent = Active, onExpire = Expire })
	if not ok then
		self.pendingQuestCompareRequests[id] = nil
		return false
	end
	if not receiver and self.PrintQuestCompareStart then
		self:PrintQuestCompareStart(target, pending.classFile)
	end
	return true, id
end

function QuestTogether:HandleQuestCompareRequest(data)
	local sender = self:NormalizeMemberName(data.requesterName)
	if
		not self.isEnabled
		or not sender
		or self:IsIgnoredPlayerName(sender)
		or self:NormalizeMemberName(data.targetName) ~= self:NormalizeMemberName(self:GetPlayerFullName())
	then
		return false
	end
	if data.historyQuestIds and (data.objectiveQuestId or data.knownRevision
		or not self:ValidateQuestHistoryQuery(data.historyQuestIds)) then
		return false
	end
	local now = self.API.GetTime()
	local cache = rawget(self, "questCompareResponseCache")
	if not cache then
		cache = {}
		self.questCompareResponseCache = cache
	end
	local key = sender .. ":" .. data.requestId
	local existing = cache[key]
	if existing and now >= existing.startedAt and now < existing.expiresAt then
		return true
	end
	local count = 0
	for id, row in pairs(cache) do
		if now < row.startedAt or now >= row.expiresAt then
			cache[id] = nil
		else
			count = count + 1
		end
	end
	if count >= 16 then
		return false
	end
	local job = {
		data = data,
		targetName = sender,
		requiresGroup = data.partyOnly == true,
		startedAt = now,
		expiresAt = now + 180,
		nextAttempt = now,
		attempts = 0,
		generation = rawget(self, "commsWorldGeneration") or 0,
	}
	cache[key] = job
	self:ProgressQuestCompareResponses(now)
	return true
end
function QuestTogether:ProgressQuestCompareResponses(now)
	local cache = rawget(self, "questCompareResponseCache")
	local historyBudget = 16
	for key, job in pairs(cache or {}) do
		if
			now < job.startedAt
			or now >= job.expiresAt
			or not Current(self, job)
			or job.generation ~= (rawget(self, "commsWorldGeneration") or 0)
		then
			cache[key] = nil
		elseif not job.submitted and now >= job.nextAttempt then
			job.nextAttempt = now + 1
			local entries, reason
			if job.data.historyQuestIds then
				local used
				entries, reason, used = self:ProgressQuestHistoryResponse(job, math.min(8, historyBudget))
				historyBudget = historyBudget - used
			else
				entries, reason = self:BuildRevisionedQuestCompareEntries(job.data.objectiveQuestId)
			end
			if entries then
				local unchanged = entries.revision ~= nil and entries.revision == job.data.knownRevision
				local response = {
					requestId = job.data.requestId,
					snapshotId = self:BuildChannelRequestId("snapshot"),
					revision = entries.revision,
					unchanged = unchanged,
					classFile = self:GetPlayerClassFile(),
					objectiveQuestId = job.data.objectiveQuestId,
					count = job.historyStates and #job.historyStates or #entries,
					entries = unchanged and {} or entries,
					supportsQuestHistory = true,
					historyStates = job.historyStates,
				}
				job.expiresAt = job.startedAt + 600
				local ok, status = self:Respond(
					"QCRS",
					response,
					{ { distribution = "WHISPER", target = job.targetName, requiresGroup = job.requiresGroup } },
					{
						owner = job,
						startedAt = job.startedAt,
						expires = job.expiresAt,
						isCurrent = function()
							return self.questCompareResponseCache == cache
								and Current(self, job)
								and job.generation == (rawget(self, "commsWorldGeneration") or 0)
						end,
						onComplete = function(accepted, result)
							job.result = result
							job.accepted = accepted
							if result ~= "capacity" and cache[key] == job then
								cache[key] = nil
							end
						end,
					}
				)
				if ok then
					job.submitted = true
				elseif status == "oversize" or status == "invalid" then
					job.submitted = true
					job.result = status
					self:RecordCommsDiagnostic("failedComparisons", status)
					self:Respond(
						"ERROR",
						{ requestId = job.data.requestId, operation = "QCMP", code = status },
						{ { distribution = "WHISPER", target = job.targetName } },
						{ owner = job }
					)
					cache[key] = nil
				end
			elseif reason ~= "restricted" and reason ~= "pending" then
				job.attempts = job.attempts + 1
				if job.attempts >= 5 then
					job.submitted = true
					job.result = reason or "unavailable"
					self:Respond(
						"ERROR",
						{ requestId = job.data.requestId, operation = "QCMP", code = job.result },
						{ { distribution = "WHISPER", target = job.targetName } },
						{ owner = job }
					)
					cache[key] = nil
				end
			end
		end
	end
end
