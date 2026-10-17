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
			copy.objectives = objectives
			return { copy }
		end
	end
	return {}
end

function QT:CancelPartyQuestObjectiveRequests(session, questId)
	for _, member in ipairs(session and session.members or {}) do
		self:ReleasePartyQuestProgress(member, questId)
		for id in pairs(member.objectiveDetails or {}) do
			if not questId or id == questId then
				member.objectiveDetails[id] = nil
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
	for _, id in ipairs(ids) do
		local function Current()
			return self.partyQuestCompareSession == session
				and session.byName[member.name] == member
				and session.expandedQuestIds[id] == true
		end
		local function Updated(detail)
			if not Current() then
				return
			end
			member.objectiveDetails[id] = detail
			if detail.hasEntry then
				self:UpdatePartyQuestMemberEntry(member, id, detail.entry)
			end
			self:QueuePartyQuestCompareRender()
		end
		local detail =
			self:AcquirePartyQuestProgress(member.name, id, member, Updated, session.mode == "party", Current)
		if detail then
			member.objectiveDetails[id] = detail
			Updated(detail)
		end
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

local function Progress(row, current, required)
	if row.kind == "progressbar" and current then
		return tostring(current) .. "%"
	end
	if current and required and required > 0 then
		return current .. "/" .. required
	end
	return row.finished == true and L("Complete") or row.finished == false and L("In progress") or L("Unknown")
end

function QT:GetPartyQuestReadiness(quest)
	local ready, completed, missing, absent, unknown, total = 0, 0, 0, 0, 0, #self.partyQuestCompareSession.members
	for i, member in ipairs(self.partyQuestCompareSession.members) do
		if member.state ~= "ready" then
			unknown = unknown + 1
		elseif quest.cells[i] == "Ready" then
			ready = ready + 1
		elseif quest.cells[i] == "Missing" then
			missing = missing + 1
		elseif quest.cells[i] == "Absent" then
			absent = absent + 1
		elseif quest.cells[i] == "Completed" then
			completed = completed + 1
		elseif quest.cells[i] ~= "Have" then
			unknown = unknown + 1
		end
	end
	if total > 0 and ready == total then
		return L("Everyone ready"), "Ready"
	end
	local text = string.format(L("%d/%d ready"), ready, total)
	if completed > 0 then
		local completion = string.format(L("%d completed"), completed)
		if completed == total then
			return completion, "Completed"
		end
		text = text .. " · " .. completion
	end
	if missing > 0 then
		text = text .. " · " .. string.format(L("%d missing"), missing)
	end
	if absent > 0 then
		text = text .. " · " .. string.format(L("%d not in log"), absent)
	end
	if unknown > 0 then
		text = text .. " · " .. string.format(L("%d unknown"), unknown)
	end
	return text, unknown > 0 and "Unknown" or missing > 0 and "Missing" or absent > 0 and "Absent" or "Have"
end

function QT:AppendPartyQuestObjectiveRows(rows, member, questId)
	local detail, entry = member.objectiveDetails and member.objectiveDetails[questId], member.entries[questId]
	local notice
	if detail and detail.notice and detail.notice ~= "Not in log" then
		notice = detail.notice
	elseif member.state ~= "ready" and not (detail and detail.state == "ready") then
		notice = member.state == "loading" and "Loading" or "Unknown"
	elseif detail and detail.state == "unknown" then
		notice = "Unknown"
	elseif not entry and not (detail and detail.objectives) then
		local absence = self:GetPartyQuestAbsenceState(member, questId)
		notice = absence == "Absent" and "Not in log" or absence
	elseif not member.isLocal and not member.supportsObjectives then
		notice = "Update QuestTogether for objective details."
	elseif not detail or detail.questId ~= questId or detail.state == "loading" then
		notice = "Loading"
	elseif detail.state ~= "ready" then
		notice = "Unknown"
	elseif not detail.objectives or #detail.objectives == 0 then
		-- Delivery/talk quests can be ready without any objective counters.
		-- Status comes from the quest snapshot, never from an empty detail list.
		notice = entry and (entry.isComplete and "Ready" or "In progress") or "No objective details available."
	end
	rows[#rows + 1] = {
		questId = questId,
		kind = "member",
		classFile = member.classFile,
		title = member.isLocal and L("You") or member.name,
		cells = {},
		hint = notice == "No objective details available." and L("No objective details available.")
			or notice == "Update QuestTogether for objective details." and L(
				"Update QuestTogether for objective details."
			)
			or notice and L(notice),
		status = notice,
	}
	if not notice or (detail and detail.notice == "Ready" and not detail.pendingMilestone and detail.objectives) then
		for _, objective in ipairs(detail.objectives) do
			-- Each player's wording stays attached to their own data. Index
			-- equality does not prove identical objectives across clients.
			-- Apply the same counter correction to snapshots from older peers,
			-- without modifying their cached observations.
			local current, required = self:NormalizeQuestObjectiveCounters(
				objective.kind, objective.finished, objective.current, objective.required
			)
			rows[#rows + 1] = {
				questId = questId,
				kind = "objective",
				classFile = member.classFile,
				title = objective.text,
				cells = {},
				hint = Progress(objective, current, required),
				complete = objective.finished == true,
				fraction = objective.finished == true and 1
					or (
						current
							and required
							and required > 0
							and math.max(0, math.min(1, current / required))
						or nil
					),
			}
		end
	end
end

function QT:BuildPartyQuestCompareDisplayRows(quests)
	local session, rows = self.partyQuestCompareSession, {}
	for _, quest in ipairs(quests) do
		quest.partySummary, quest.partySummaryState = self:GetPartyQuestReadiness(quest)
		rows[#rows + 1] = quest
		if session.expandedQuestIds and session.expandedQuestIds[quest.questId] then
			for _, member in ipairs(session.members) do
				self:AppendPartyQuestObjectiveRows(rows, member, quest.questId)
			end
		end
	end
	return rows
end
