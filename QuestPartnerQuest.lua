local QT = _G.QuestTogether
local LIFETIME = 65

local function QuestID(addon, value)
	local id = addon:SafeToNumber(value)
	return id and id >= 1 and id <= 1000000000 and id == math.floor(id) and id or nil
end

local function Now(addon)
	return addon:SafeToNumber(addon.API.GetTime and addon.API.GetTime())
end

-- Focus is an independently sampled topic paired with the LFQP revision.
function QT:BuildQuestPartnerQuestPayload(state, looking)
	local questID
	if looking and self:CanPublishPlayerLocation() and not self:IsRuntimeRestricted() then
		local getter = self.API.GetActiveTrackedQuestID
		if self:CanAccessValue(getter) and type(getter) == "function" then
			local ok, value = pcall(getter)
			if ok then
				questID = QuestID(self, value)
			end
		end
	end
	local payload = { session = state.partnerSession, sequence = state.partnerSequence, questID = questID or 0 }
	local title = ""
	if questID then
		title = self:GetLocalizedQuestTitle(questID) or self:GetQuestTitle(questID)
		title = self:SafeTrimString(title, ""):gsub("[%c]", " ")
		if self:IsPlaceholderQuestTitle(questID, title) then
			title = ""
		end
	end
	payload.title = title
	return payload, questID
end

function QT:BroadcastQuestPartnerQuest(state, looking)
	local payload, questID = self:BuildQuestPartnerQuestPayload(state, looking)
	-- Stay silent for clients without a tracked quest unless withdrawing one.
	local now = Now(self)
	local last = state.lastPartnerQuestOnAt
	local withdrawalLifetime = rawget(self, "geographicCommsState") and 600 or LIFETIME
	if not questID and (not now or not last or now < last or now - last >= withdrawalLifetime) then
		return false
	end
	local sent = self:Publish("QTLQ", payload, nil, {
		owner = state,
		onComplete = function(accepted)
			if accepted and self:GetQTPlayerPresenceState() == state then
				self:RecordQuestPartnerQuestPublication(payload)
			end
		end,
	})
	-- A partially successful route can still publish data. Keep sending clears on
	-- subsequent LFG heartbeats even if the overall send reported failure.
	return sent
end

function QT:HandleQuestPartnerQuestMessage(payload, sender, observation)
	if not self.isEnabled or type(payload) ~= "table" then
		return false
	end
	local session, sequence, id, title = payload.session, payload.sequence, payload.questID, payload.title or ""
	if
		type(session) ~= "string"
		or #session > 64
		or type(sequence) ~= "number"
		or sequence < 1
		or sequence > 2147483647
		or type(id) ~= "number"
		or (id ~= 0 and not QuestID(self, id))
	then
		return false
	end
	title = self:SafeTrimString(title, ""):gsub("[%c]", " ")
	local name, now = self:NormalizeMemberName(sender), Now(self)
	if not name or not now or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	observation = self:ResolvePeerObservation(name, "QTLQ", observation)
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	self:PruneQuestPartnerQuests(now)
	-- This packet alone cannot renew LFG status or restore a departed identity.
	local record = {
		session = session,
		sequence = sequence,
		questID = id,
		title = id ~= 0 and title ~= "" and title or nil,
		receivedAt = now,
	}
	if not self:CommitQuestPartnerObservation("quest", name, record, observation, false, true) then
		return false
	end
	return true
end

function QT:GetPlayerPartnerQuestID(name)
	name = self:NormalizeMemberName(name)
	if not name or not self:IsPlayerLookingForQuestPartners(name) then
		return nil
	end
	if self:IsSelfSender(name) then
		if self:IsRuntimeRestricted() then
			return nil
		end
		local getter = self.API.GetActiveTrackedQuestID
		if not self:CanAccessValue(getter) or type(getter) ~= "function" then
			return nil
		end
		local ok, value = pcall(getter)
		return ok and QuestID(self, value) or nil
	end
	local state, now = rawget(self, "qtPlayerPresenceState"), Now(self)
	local record = state and state.partnerQuests and state.partnerQuests[name]
	local status = state and state.questPartners and state.questPartners[name]
	if
		record
		and status
		and now
		and now >= record.receivedAt
		and now - record.receivedAt < (record.lifetime or LIFETIME)
		and record.session == status.session
		and record.sequence == status.sequence
	then
		return QuestID(self, record.questID), record.title
	end
end
