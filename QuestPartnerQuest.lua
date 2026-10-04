local QT = _G.QuestTogether
local LIFETIME, MAX_PEERS = 65, 256

local function QuestID(addon, value)
	local id = addon:SafeToNumber(value)
	return id and id >= 1 and id <= 1000000000 and id == math.floor(id) and id or nil
end

local function Now(addon)
	return addon:SafeToNumber(addon.API.GetTime and addon.API.GetTime())
end

-- QTLF and LOC have strict legacy decoders. A separate, small optional packet
-- keeps older peers' partner status and map dots working unchanged. Its sequence
-- must match QTLF before we display it, including when transport reorders them.
function QT:BroadcastQuestPartnerQuest(state, looking)
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
	-- Stay silent for clients without a tracked quest unless withdrawing one.
	local now = Now(self)
	local last = state.lastPartnerQuestOnAt
	if not questID and (not now or not last or now < last or now - last >= LIFETIME) then
		return false
	end
	local payload = string.format("1,%s,%d,%d", state.partnerSession, state.partnerSequence, questID or 0)
	local title = ""
	if questID then
		title = self:GetLocalizedQuestTitle(questID) or self:GetQuestTitle(questID)
		title = self:SafeTrimString(title, ""):gsub("[%c]", " ")
		if self:IsPlaceholderQuestTitle(questID, title) then
			title = ""
		end
		title = self:EscapePayload(title)
		-- Omit exceptionally long titles rather than split UTF-8 characters or
		-- percent escapes. The receiver can still resolve the unchanged quest ID.
		if #payload + 1 + #title > 250 then
			title = ""
		end
	end
	local sent = self:SendWireMessageToAnnouncementRoutes(
		self:SerializeWireMessage("QTLQ", payload .. "," .. title),
		"quest partner tracked quest"
	)
	-- A partially successful route can still publish data. Keep sending clears on
	-- subsequent LFG heartbeats even if the overall send reported failure.
	if questID then
		state.lastPartnerQuestOnAt = now
	end
	return sent
end

function QT:PruneQuestPartnerQuests(now)
	local state = rawget(self, "qtPlayerPresenceState")
	for name, record in pairs(state and state.partnerQuests or {}) do
		if
			not now
			or now < record.receivedAt
			or now - record.receivedAt >= LIFETIME
			or self:IsIgnoredPlayerName(name)
		then
			state.partnerQuests[name] = nil
		end
	end
end

function QT:HandleQuestPartnerQuestMessage(payload, sender)
	if not self.isEnabled or not self:CanAccessValue(payload) or type(payload) ~= "string" or #payload > 250 then
		return false
	end
	local session, sequence, id, title = payload:match("^1,(%d+%-%d+),(%d+),(%d+),([^,]*)$")
	if not session then
		session, sequence, id = payload:match("^1,(%d+%-%d+),(%d+),(%d+)$")
	end
	title = self:SafeTrimString(self:UnescapePayload(title or ""), ""):gsub("[%c]", " ")
	sequence, id = self:SafeToNumber(sequence), self:SafeToNumber(id)
	if
		not session
		or #session > 40
		or not sequence
		or sequence < 1
		or sequence > 2147483647
		or not id
		or (id ~= 0 and not QuestID(self, id))
	then
		return false
	end
	local name, now = self:NormalizeMemberName(sender), Now(self)
	if not name or not now or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then
		return false
	end
	self:PruneQuestPartnerQuests(now)
	local state = self:GetQTPlayerPresenceState()
	state.partnerQuests = state.partnerQuests or {}
	local previous = state.partnerQuests[name]
	if previous and previous.session == session and previous.sequence >= sequence then
		return false
	end
	local retired = previous and previous.retired or {}
	for _, oldSession in ipairs(retired) do
		if oldSession == session then
			return false
		end
	end
	if previous and previous.session ~= session then
		retired[#retired + 1] = previous.session
		if #retired > 4 then
			table.remove(retired, 1)
		end
	end
	if not previous then
		local count, oldest, oldestAt = 0, nil, math.huge
		for peer, record in pairs(state.partnerQuests) do
			count = count + 1
			if record.receivedAt < oldestAt then
				oldest, oldestAt = peer, record.receivedAt
			end
		end
		if count >= MAX_PEERS then
			state.partnerQuests[oldest] = nil
		end
	end
	-- This packet alone cannot renew LFG status or restore a departed identity.
	state.partnerQuests[name] = {
		session = session,
		sequence = sequence,
		questID = id,
		title = id ~= 0 and title ~= "" and title or nil,
		receivedAt = now,
		retired = retired,
	}
	return true
end

function QT:GetPlayerPartnerQuestID(name)
	name = self:NormalizeMemberName(name)
	if not name or not self:IsPlayerLookingForQuestPartners(name) then
		return nil
	end
	if self:IsSelfSender(name) then
		if self:IsRuntimeRestricted() then return nil end
		local getter = self.API.GetActiveTrackedQuestID
		if not self:CanAccessValue(getter) or type(getter) ~= "function" then return nil end
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
		and now - record.receivedAt < LIFETIME
		and record.session == status.session
		and record.sequence == status.sequence
	then
		return QuestID(self, record.questID), record.title
	end
end
