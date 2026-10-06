local QT = _G.QuestTogether
local L = QT.Translate

-- Detail snapshots are requested only for the expanded quest. Keep them separate
-- from the ownership snapshot: a partial detail reply cannot certify a quest log.
function QT:CleanQuestCompareObjectiveText(value)
	local text = self:SafeTrimString(value, "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
	return self:SanitizeAnnouncementText(
		text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", ""):gsub("[%c]", " ")
	)
end

local function Counter(addon, value)
	local n = addon:SafeToNumber(value)
	return n and n >= 0 and n <= 1000000000 and n == math.floor(n) and n or nil
end

function QT:ReadQuestCompareObjectives(questId)
	if self:IsWorkBlocked("quest_snapshot_refresh") then
		return nil
	end
	local index = self:GetQuestLogIndexForQuest(questId)
	if not index then
		return nil
	end
	local count = self.API.GetNumQuestLeaderBoards and self:SafeToNumber(self.API.GetNumQuestLeaderBoards(index))
	-- The existing client adapter also returns zero for unavailable reads. Do not
	-- turn that into evidence of completion or a confirmed empty objective list.
	if not count or count < 1 or count > 20 or count ~= math.floor(count) then
		return nil
	end
	local rows = {}
	for i = 1, count do
		local ok, text, kind, finished, current, required =
			pcall(self.GetNormalizedQuestObjectiveInfo, self, questId, i, false)
		if not ok then
			return nil
		end
		text, kind = self:CleanQuestCompareObjectiveText(text), self:SafeTrimString(kind, "")
		if text == "" or #kind > 32 or kind:find("[^%a]") then
			return nil
		end
		if not self:CanAccessValue(finished) or type(finished) ~= "boolean" then
			finished = nil
		end
		current, required = Counter(self, current), Counter(self, required)
		if kind == "progressbar" then
			required = 100
			if current and current > 100 then
				current = nil
			end
		end
		rows[i] = {
			questId = questId,
			objectiveIndex = i,
			text = text,
			kind = kind,
			finished = finished,
			current = current,
			required = required,
		}
	end
	if self:GetQuestLogIndexForQuest(questId) ~= index then
		return nil
	end
	local finalCount = self:SafeToNumber(self.API.GetNumQuestLeaderBoards(index))
	if finalCount ~= count then
		return nil
	end
	return rows
end

function QT:BuildQuestCompareResponseEntries(questId)
	local entries, reason = self:BuildQuestCompareEntries()
	if not entries or not questId then
		return entries, reason
	end
	for _, entry in ipairs(entries) do
		if self:NormalizeQuestID(entry.questId) == questId then
			local copy = {}
			for key, value in pairs(entry) do
				copy[key] = value
			end
			local objectives = self:ReadQuestCompareObjectives(questId)
			copy.objectiveCount = objectives and #objectives or nil
			local packets = { copy }
			for _, row in ipairs(objectives or {}) do
				packets[#packets + 1] = row
			end
			return packets
		end
	end
	return {}
end

function QT:CancelPartyQuestObjectiveRequests(session, questId)
	for _, member in ipairs(session and session.members or {}) do
		for id, detail in pairs(member.objectiveDetails or {}) do
			if not questId or id == questId then
				if detail.requestId and self.pendingQuestCompareRequests then
					self.pendingQuestCompareRequests[detail.requestId] = nil
				end
				member.objectiveDetails[id] = nil
				if member.objectiveRequestQuestId == id then
					member.objectiveRequestQuestId = nil
				end
			end
		end
	end
end

function QT:LoadPartyQuestObjectives(member)
	local session = self.partyQuestCompareSession
	if
		not session
		or member.state ~= "ready"
		or member.isLocal
		or member.objectiveRequestQuestId
		or not member.supportsObjectives
		or self:IsIgnoredPlayerName(member.name)
	then
		return
	end
	member.objectiveDetails = member.objectiveDetails or {}
	local ids = {}
	for id in pairs(session.expandedQuestIds or {}) do
		if member.entries[id] and not member.objectiveDetails[id] then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local id = ids[1]
	if not id then
		return
	end
	local detail = { questId = id, state = "loading" }
	member.objectiveDetails[id], member.objectiveRequestQuestId = detail, id
	local entry
	local function Current()
		return self.isEnabled
			and self.partyQuestCompareSession == session
			and session.expandedQuestIds[id]
			and member.objectiveDetails[id] == detail
			and not self:IsIgnoredPlayerName(member.name)
			and (session.mode == "target" or self:IsGroupedSender(member.name))
	end
	local function Continue()
		member.objectiveRequestQuestId = nil
		self:LoadPartyQuestObjectives(member)
		self:QueuePartyQuestCompareRender()
	end
	-- One outstanding objective request per peer prevents an older responder's
	-- per-requester queue from replacing another expanded quest's reply.
	local routes = { { distribution = "WHISPER", target = member.name, requiresGroup = session.mode == "party" } }
	local sent, requestId = self:RequestQuestCompare(member.name, {
		objectiveQuestId = id,
		routes = routes,
		onEntry = function(data)
			if Current() then
				entry = data
			end
		end,
		onDone = function()
			if not Current() then
				return
			end
			detail.state, detail.objectives = "ready", entry and entry.objectives
			member.entries[id] = entry
			Continue()
		end,
		onTimeout = function()
			if Current() then
				detail.state = "unknown"
				Continue()
			end
		end,
	})
	detail.requestId = requestId
	if not sent then
		detail.state = "unknown"
		Continue()
	end
end

function QT:TogglePartyQuestObjectives(questId)
	local session = self.partyQuestCompareSession
	if not session or self:IsWorkBlocked("foreign_frame_mutation") then
		return
	end
	session.expandedQuestIds = session.expandedQuestIds or {}
	if session.expandedQuestIds[questId] then
		session.expandedQuestIds[questId] = nil
		self:CancelPartyQuestObjectiveRequests(session, questId)
	else
		session.expandedQuestIds[questId] = true
	end
	for _, member in ipairs(session.members) do
		self:LoadPartyQuestObjectives(member)
	end
	self:RefreshLocalPartyQuestCompare()
	self:QueuePartyQuestCompareRender()
end

local function Progress(row)
	if row.kind == "progressbar" and row.current then
		return tostring(row.current) .. "%"
	end
	if row.current and row.required and row.required > 0 then
		return row.current .. "/" .. row.required
	end
	return row.finished == true and L("Complete") or row.finished == false and L("In progress") or L("Unknown")
end

function QT:GetPartyQuestReadiness(quest)
	local ready, missing, unknown, total = 0, 0, 0, #self.partyQuestCompareSession.members
	for i, member in ipairs(self.partyQuestCompareSession.members) do
		if member.state ~= "ready" then
			unknown = unknown + 1
		elseif quest.cells[i] == "Ready" then
			ready = ready + 1
		elseif quest.cells[i] == "Missing" then
			missing = missing + 1
		elseif quest.cells[i] ~= "Have" then
			unknown = unknown + 1
		end
	end
	if total > 0 and ready == total then
		return L("Everyone ready"), "Ready"
	end
	local text = string.format(L("%d/%d ready"), ready, total)
	if missing > 0 then
		text = text .. " · " .. string.format(L("%d missing"), missing)
	end
	if unknown > 0 then
		text = text .. " · " .. string.format(L("%d unknown"), unknown)
	end
	return text, unknown > 0 and "Unknown" or missing > 0 and "Missing" or "Have"
end

function QT:BuildPartyQuestCompareDisplayRows(quests)
	local session, rows = self.partyQuestCompareSession, {}
	for _, quest in ipairs(quests) do
		quest.partySummary, quest.partySummaryState = self:GetPartyQuestReadiness(quest)
		rows[#rows + 1] = quest
		if session.expandedQuestIds and session.expandedQuestIds[quest.questId] then
			for _, member in ipairs(session.members) do
				local detail, entry =
					member.objectiveDetails and member.objectiveDetails[quest.questId], member.entries[quest.questId]
				local notice
				if member.state ~= "ready" then
					notice = member.state == "loading" and L("Loading") or L("Unknown")
				elseif not entry then
					notice = L("Missing")
				elseif not member.isLocal and not member.supportsObjectives then
					notice = L("Update QuestTogether for objective details.")
				elseif not detail or detail.questId ~= quest.questId or detail.state == "loading" then
					notice = L("Loading")
				elseif detail.state ~= "ready" then
					notice = L("Unknown")
				elseif not detail.objectives or #detail.objectives == 0 then
					notice = L("No objective details available.")
				end
				rows[#rows + 1] = {
					questId = quest.questId,
					kind = "member",
					classFile = member.classFile,
					title = member.isLocal and L("You") or member.name,
					cells = {},
					hint = notice,
				}
				if not notice then
					for _, objective in ipairs(detail.objectives) do
						-- Each player's wording stays attached to their own data. Index
						-- equality does not prove identical objectives across clients.
						rows[#rows + 1] = {
							questId = quest.questId,
							kind = "objective",
							classFile = member.classFile,
							title = objective.text,
							cells = {},
							hint = Progress(objective),
							complete = objective.finished == true,
							fraction = objective.finished == true and 1
								or (
									objective.current
										and objective.required
										and objective.required > 0
										and math.max(0, math.min(1, objective.current / objective.required))
									or nil
								),
						}
					end
				end
			end
		end
	end
	return rows
end
