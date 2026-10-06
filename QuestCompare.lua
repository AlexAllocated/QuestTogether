local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether

local SHARE_LIFETIME = 60
local SHARE_COOLDOWN = 5
local GROUP_ROUTES = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local SHARE_STATUS = {
	request = true,
	pending = true,
	sent = true,
	declined = true,
	unavailable = true,
	expired = true,
}
local STATUS_TEXT = {
	pending = "Awaiting confirmation",
	sent = "Share attempted",
	declined = "Request declined",
	unavailable = "Sharing unavailable",
	expired = "Request expired",
	request = "Request sent",
}

local function PlayerName(addon)
	return addon:NormalizeMemberName(addon:GetPlayerFullName())
end

local function EntryMap(addon, entries)
	local result = {}
	for _, entry in ipairs(entries or {}) do
		local id = addon:NormalizeQuestID(entry.questId)
		if id then
			result[id] = entry
		end
	end
	return result
end

function QuestTogether:CancelPartyQuestCompare()
	local session = self.partyQuestCompareSession
	self:CancelPartyQuestObjectiveRequests(session)
	self.partyQuestCompareSession = nil
	for _, member in ipairs(session and session.members or {}) do
		if member.requestId and self.pendingQuestCompareRequests then
			self.pendingQuestCompareRequests[member.requestId] = nil
		end
	end
end

function QuestTogether:CancelIgnoredPlayerQuestCompare()
	local state = self.partyQuestShareState
	local removedIncoming = false
	for key, request in pairs(state and state.incoming or {}) do
		if self:IsIgnoredPlayerName(request.sender) then
			state.incoming[key] = nil
			removedIncoming = true
		end
	end
	for key, request in pairs(state and state.outgoing or {}) do
		if self:IsIgnoredPlayerName(request.target) then
			state.outgoing[key] = nil
		end
	end
	local prompt = self.partyQuestSharePrompt
	if prompt and prompt.request and self:IsIgnoredPlayerName(prompt.request.sender) then
		-- This is an addon-owned, unprotected frame. Remove the old sender's
		-- prompt immediately; displaying another prompt still uses deferred work.
		prompt.request = nil
		prompt:Hide()
	end
	if removedIncoming then
		self:QueuePartyQuestSharePrompt()
	end
	local session = self.partyQuestCompareSession
	if not session then
		return
	end
	if session.mode == "target" and self:IsIgnoredPlayerName(session.targetName) then
		self:CancelPartyQuestCompare()
		if self.partyQuestCompareWindow then
			self.partyQuestCompareWindow:Hide()
		end
		return
	end
	for _, member in ipairs(session.members) do
		if not member.isLocal and self:IsIgnoredPlayerName(member.name) then
			if member.requestId and self.pendingQuestCompareRequests then
				self.pendingQuestCompareRequests[member.requestId] = nil
			end
			for _, detail in pairs(member.objectiveDetails or {}) do
				if detail.requestId then self.pendingQuestCompareRequests[detail.requestId] = nil end
			end
			member.objectiveDetails, member.objectiveRequestQuestId = {}, nil
			member.entries, member.state, member.supportsShareRequests = {}, "unavailable", nil
		end
	end
	self:QueuePartyQuestCompareRender()
end

function QuestTogether:ResetPartyQuestCompare()
	self:ClosePartyQuestComparePreview()
	self:CancelPartyQuestCompare()
	self.partyQuestShareState = nil
	if self.partyQuestCompareWindow then
		self.partyQuestCompareWindow:Hide()
	end
	if self.partyQuestSharePrompt then
		self.partyQuestSharePrompt:Hide()
	end
end

function QuestTogether:TogglePartyQuestCompare()
	if self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local closed = false
	for _, controller in ipairs({ self, rawget(self, "partyQuestComparePreview") }) do
		local frame = rawget(controller, "partyQuestCompareWindow")
		if frame and not self.LibChev.CanMutateOwnedRegion(frame) then return false end
		if frame and frame:IsShown() then
			controller:CancelPartyQuestCompare()
			frame:Hide()
			closed = true
		end
	end
	if closed then return true end
	return self:OpenPartyQuestCompare()
end

function QuestTogether:OpenPartyQuestCompare(preferredName)
	if not self.isEnabled then
		self:Print(L("Enable QuestTogether to compare party quests."))
		return false
	end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		self:Print(L("Quest comparison is unavailable while restricted. Try again when restrictions end."))
		return false
	end
	if not self:CreatePartyQuestCompareWindow() then
		return false
	end
	-- Opening the party view explicitly leaves a previous two-player session.
	self:CancelPartyQuestCompare()
	self:RefreshPartyRoster()
	if not self:RefreshPartyQuestCompare(preferredName) then
		return false
	end
	self.partyQuestCompareWindow:Show()
	return true
end

function QuestTogether:OpenPlayerQuestCompare(name)
	if not self.isEnabled then
		self:Print(L("Enable QuestTogether to compare quests."))
		return false
	end
	if self:IsWorkBlocked("foreign_frame_mutation") then
		self:Print(L("Quest comparison is unavailable while restricted. Try again when restrictions end."))
		return false
	end
	if not self:CanAccessValue(name) or type(name) ~= "string" then
		return false
	end
	local targetName = self:NormalizeMemberName(self:SafeTrimString(name, ""))
	if not targetName or targetName == "" or targetName == PlayerName(self) or self:IsIgnoredPlayerName(targetName) then
		return false
	end
	if not self:CreatePartyQuestCompareWindow() then
		return false
	end
	self:CancelPartyQuestCompare()
	self:RefreshPartyRoster()
	if not self:RefreshPartyQuestCompare(nil, targetName) then
		return false
	end
	self.partyQuestCompareWindow:Show()
	return true
end

function QuestTogether:RefreshPartyQuestCompare(preferredName, targetName)
	local previous = self.partyQuestCompareSession
	if not targetName and previous and previous.mode == "target" then
		targetName = previous.targetName
	end
	if targetName and self:IsIgnoredPlayerName(targetName) then
		self:CancelIgnoredPlayerQuestCompare()
		return false
	end
	self:CancelPartyQuestCompare()
	if not self.isEnabled then
		return false
	end
	local ownName = PlayerName(self)
	if not ownName then
		return false
	end
	local session = {
		playerName = ownName,
		members = {},
		byName = {},
		offset = 0,
		mode = targetName and "target" or "party",
		targetName = targetName,
		expandedQuestIds = previous and previous.expandedQuestIds or {},
		search = previous and previous.search or "",
	}
	self.partyQuestCompareSession = session
	local names = { ownName }
	if targetName then
		names[#names + 1] = targetName
	elseif preferredName ~= ownName and self.partyMembers[preferredName] then
		names[#names + 1] = preferredName
	end
	if not targetName then
		for _, name in ipairs(self.partyMemberOrder or {}) do
			if name ~= ownName and name ~= preferredName then
				names[#names + 1] = name
			end
		end
	end
	for _, name in ipairs(names) do
		local member = { name = name, entries = {}, state = "loading", isLocal = name == ownName }
		member.classFile = member.isLocal and self:GetPlayerClassFile() or self:GetGroupedSenderClassFile(name)
		session.members[#session.members + 1] = member
		session.byName[name] = member
	end
	self:RefreshLocalPartyQuestCompare()
	local route = self:GetGroupAnnouncementDistribution()
	for _, member in ipairs(session.members) do
		if not member.isLocal then
			local function Current()
				return self.isEnabled
					and self.partyQuestCompareSession == session
					and not self:IsIgnoredPlayerName(member.name)
					and (session.mode == "target" or self:IsGroupedSender(member.name))
			end
			local sent, requestId
			local routes
			if self:IsGroupedSender(member.name) then
				routes = route and { { distribution = route } } or nil
			elseif session.mode == "target" then
				-- The request helper upgrades this legacy route to a whisper when
				-- the peer advertises direct controls. Unrelated groups never receive it.
				routes = { { distribution = "CHANNEL", requiresChannelJoin = true } }
			end
			if routes and not self:IsIgnoredPlayerName(member.name) then
				sent, requestId = self:RequestQuestCompare(member.name, {
					routes = routes,
					onEntry = function(entry)
						if not Current() then
							return
						end
						member.entries[self:NormalizeQuestID(entry.questId)] = entry
						if entry.classFile and entry.classFile ~= "" then member.classFile = entry.classFile end
						self:QueuePartyQuestCompareRender()
					end,
					onDone = function(supportsShareRequests, supportsObjectives, classFile)
						if not Current() then
							return
						end
						member.state = "ready"
						member.supportsShareRequests = supportsShareRequests
						member.supportsObjectives = supportsObjectives
						if classFile and classFile ~= "" then member.classFile = classFile end
						self:LoadPartyQuestObjectives(member)
						self:QueuePartyQuestCompareRender()
					end,
					onTimeout = function()
						if not Current() then
							return
						end
						member.state = "timeout"
						self:QueuePartyQuestCompareRender()
					end,
				})
			end
			member.requestId = requestId
			if not sent then
				member.state = "unavailable"
			end
		end
	end
	self:QueuePartyQuestCompareRender()
	return true
end

function QuestTogether:RefreshLocalPartyQuestCompare(delaySeconds)
	local session = self.partyQuestCompareSession
	if not session or not self.isEnabled then
		return
	end
	local member = session.byName[session.playerName]
	member.state = "loading"
	self:QueuePartyQuestCompareRender()
	-- Keep this read in the map-sensitive work class. A render alone cannot
	-- wake an unavailable local snapshot when the map or combat restriction ends.
	self:ScheduleDeferredWork("quest_snapshot_refresh", "party_compare_local", function()
		if self.partyQuestCompareSession ~= session or not self.isEnabled then
			return
		end
		local entries = self:BuildQuestCompareEntries()
		member.entries = EntryMap(self, entries)
		member.state = entries and "ready" or "unavailable"
		member.objectiveDetails = {}
		for id in pairs(session.expandedQuestIds or {}) do
			member.objectiveDetails[id] = { questId = id, state = "ready",
				objectives = member.entries[id] and self:ReadQuestCompareObjectives(id) or nil }
		end
		self:QueuePartyQuestCompareRender()
	end, delaySeconds or 0, "party compare local snapshot")
end

function QuestTogether:OnPartyQuestLogChanged()
	self:RefreshLocalPartyQuestCompare(0.2)
end

function QuestTogether:GetPartyQuestLeaderName()
	if self:IsWorkBlocked("foreign_frame_mutation") then return nil end
	local getter = self.API and self.API.GetPartyVisualLeaderUnit
	if type(getter) ~= "function" then return nil end
	local ok, unit = pcall(getter)
	if not ok or not self:CanAccessValue(unit) or type(unit) ~= "string"
		or not (unit == "player" or unit:match("^party[1-4]$") or unit:match("^raid%d+$")) then return nil end
	local named, name = pcall(self.GetUnitFullName, self, unit)
	if not named or not self:CanAccessValue(name) or type(name) ~= "string" then return nil end
	return self:NormalizeMemberName(name)
end

function QuestTogether:OnPartyQuestRosterChanged()
	if self.partyQuestCompareSession then
		self:RefreshPartyQuestCompare()
	end
	local state = self.partyQuestShareState
	for key, request in pairs(state and state.incoming or {}) do
		if not self:IsGroupedSender(request.sender) then
			state.incoming[key] = nil
		end
	end
	for _, request in pairs(state and state.outgoing or {}) do
		if not self:IsGroupedSender(request.target) then
			request.status = "unavailable"
		end
	end
	self:QueuePartyQuestSharePrompt()
end

-- Absence is evidence only after the complete snapshot arrives. Partial lists,
-- timeouts and restricted local reads must never become a false "Missing".
function QuestTogether:BuildPartyQuestDiffRows()
	local session = self.partyQuestCompareSession
	if not session then
		return {}
	end
	local own = session.byName[session.playerName]
	local targetCanShare = session.mode ~= "target"
		or (self:IsGroupedSender(session.targetName) and not self:IsIgnoredPlayerName(session.targetName))
	local union, rows = {}, {}
	for _, member in ipairs(session.members) do
		for id, entry in pairs(member.entries) do
			if not union[id] or member.isLocal then
				union[id] = entry
			end
		end
	end
	for id, entry in pairs(union) do
		local localTitle = self:GetLocalizedQuestTitle(id)
		local row = { questId = id, title = localTitle or entry.questTitle, needsLocalTitle = not localTitle, cells = {}, missing = 0 }
		for i, member in ipairs(session.members) do
			local quest = member.entries[id]
			row.cells[i] = quest and (quest.isComplete and "Ready" or "Have")
				or (member.state == "ready" and "Missing" or (member.state == "loading" and "Loading" or "Unknown"))
			if row.cells[i] == "Missing" then
				row.missing = row.missing + 1
			end
		end
		if own.entries[id] then
			if row.missing > 0 and own.entries[id].isPushable == true then
				row.action = "share"
			end
		elseif own.state == "ready" then
			for _, member in ipairs(session.members) do
				if member.state == "ready" and member.entries[id] and member.entries[id].isPushable == true then
					row.hint = L("Owner needs an update")
					if member.supportsShareRequests then
						row.action, row.owner, row.hint = "request", member.name, nil
						break
					end
				end
			end
		end
		if not targetCanShare and (row.action or row.hint) then
			row.action, row.owner, row.hint = nil, nil, L("Join a party together to share quests.")
		end
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		if (a.missing > 0) ~= (b.missing > 0) then
			return a.missing > 0
		end
		if a.title ~= b.title then
			return a.title < b.title
		end
		return a.questId < b.questId
	end)
	return self:FilterPartyQuestCompareRows(rows)
end

function QuestTogether:OpenPartyQuestJournal(questId)
	local session = self.partyQuestCompareSession
	local own = session and session.byName[session.playerName]
	if self:IsWorkBlocked("foreign_frame_mutation") or not own or not own.entries[questId] then return false end
	-- The shared journal adapter rechecks native ownership before opening.
	return self:OpenQuestJournalFromChatLog(questId)
end

function QuestTogether:SharePartyDiffQuest(questId)
	local session = self.partyQuestCompareSession
	if
		session
		and session.mode == "target"
		and (not self:IsGroupedSender(session.targetName) or self:IsIgnoredPlayerName(session.targetName))
	then
		session.message = L("Join a party together to share quests.")
		self:QueuePartyQuestCompareRender()
		return false
	end
	local index, reason = self:GetQuestShareAvailability(questId)
	local ok = index and self.API.PushQuestToParty(index) == true
	if session then
		session.message = ok and L("Share attempted. WoW checks each player's eligibility.")
			or reason
			or L("Unable to share that quest.")
	end
	self:QueuePartyQuestCompareRender()
	return ok == true
end

function QuestTogether:GetPartyQuestShareState()
	if not self.partyQuestShareState then
		self.partyQuestShareState = {
			incoming = {},
			outgoing = {},
			recent = {},
			peers = {},
			outgoingCooldowns = {},
			sequence = 0,
		}
	end
	return self.partyQuestShareState
end

function QuestTogether:SendPartyQuestShareMessage(target, questId, requestId, status)
	local route = self:GetGroupAnnouncementDistribution()
	if not route or not self:IsGroupedSender(target) or self:IsIgnoredPlayerName(target) then
		return false
	end
	local fields = { "1", requestId, target, tostring(questId), status }
	for i = 2, #fields do
		fields[i] = self:EscapePayload(fields[i])
	end
	return self:SendWireMessageToAnnouncementRoutes(
		self:SerializeWireMessage("QSHR", table.concat(fields, ",")),
		"party quest share",
		self:GetTargetedCommRoutes(target, { { distribution = route } })
	)
end

function QuestTogether:GetPartyQuestShareRequestCooldown(target)
	local state = self.partyQuestShareState
	local expires = state and state.outgoingCooldowns and state.outgoingCooldowns[target]
	return expires and math.max(0, expires - self.API.GetTime()) or 0
end

function QuestTogether:RequestPartyQuestShare(questId, target)
	if
		not self.isEnabled
		or not self:IsGroupedSender(target)
		or self:IsIgnoredPlayerName(target)
		or self:IsWorkBlocked("quest_share")
	then
		return false
	end
	if self:GetPartyQuestShareRequestCooldown(target) > 0 then
		if self.partyQuestCompareSession then
			self.partyQuestCompareSession.message = L("Please wait before requesting another quest from this player.")
		end
		self:QueuePartyQuestCompareRender()
		return false
	end
	local eligible = false
	for _, row in ipairs(self:BuildPartyQuestDiffRows()) do
		if row.questId == questId and row.action == "request" and row.owner == target then
			eligible = true
		end
	end
	-- Re-read local ownership: the user may already have accepted this quest.
	local entries = self:BuildQuestCompareEntries()
	if not eligible or not entries or EntryMap(self, entries)[questId] then
		return false
	end
	local state, now = self:GetPartyQuestShareState(), self.API.GetTime()
	local count = 0
	for key, request in pairs(state.outgoing) do
		if
			now >= request.expires
			or (request.questId == questId and request.status ~= "request" and request.status ~= "pending")
		then
			state.outgoing[key] = nil
		else
			count = count + 1
			if request.questId == questId then
				-- The selected player may have changed since the request began.
				-- Refresh the same waiting state that disables the row action.
				self:QueuePartyQuestCompareRender()
				return false
			end
		end
	end
	if count >= 20 then
		return false
	end
	local id = self:BuildChannelRequestId("share")
	local request = { target = target, questId = questId, expires = now + SHARE_LIFETIME, status = "request" }
	state.outgoing[id] = request
	if not self:SendPartyQuestShareMessage(target, questId, id, "request") then
		state.outgoing[id] = nil
		if self.partyQuestCompareSession then
			self.partyQuestCompareSession.message = L("Could not send the share request. Try again.")
		end
		self:QueuePartyQuestCompareRender()
		return false
	end
	if self.partyQuestCompareSession then
		self.partyQuestCompareSession.message = nil
	end
	local cooldownExpires = now + SHARE_COOLDOWN
	state.outgoingCooldowns[target] = cooldownExpires
	-- Only update our UI at expiry. Never retry or delay a sharing action.
	self.API.Delay(SHARE_COOLDOWN, function()
		if self.partyQuestShareState == state and state.outgoingCooldowns[target] == cooldownExpires then
			state.outgoingCooldowns[target] = nil
			self:QueuePartyQuestCompareRender()
		end
	end)
	self.API.Delay(SHARE_LIFETIME, function()
		if self.partyQuestShareState ~= state or state.outgoing[id] ~= request then
			return
		end
		if request.status == "request" or request.status == "pending" then
			request.status = "expired"
		end
		self:QueuePartyQuestCompareRender()
	end)
	self:QueuePartyQuestCompareRender()
	return true
end

function QuestTogether:GetPartyQuestShareStatus(questId)
	local state = self.partyQuestShareState
	local session = self.partyQuestCompareSession
	for _, request in pairs(state and state.outgoing or {}) do
		if request.questId == questId then
			local pending = request.status == "request" or request.status == "pending"
			local waiting = pending and self.API.GetTime() < request.expires
			if waiting and session and session.mode == "target" and request.target ~= session.targetName then
				-- A pending request blocks this quest for every target. Keep that
				-- owner visible without attributing their later result to this player.
				return L("Waiting for ") .. request.target, true
			end
			if
				not session
				or session.mode ~= "target"
				or (request.target == session.targetName and self:IsGroupedSender(session.targetName))
			then
				return L(STATUS_TEXT[pending and not waiting and "expired" or request.status]), waiting
			end
		end
	end
end

function QuestTogether:HandlePartyQuestShareMessage(payload, sender, route)
	if
		not self.isEnabled
		or (not GROUP_ROUTES[route] and route ~= "WHISPER")
		or (route == "WHISPER" and not self:IsGroupedSender(sender))
		or sender == PlayerName(self)
		or self:IsIgnoredPlayerName(sender)
	then
		return false
	end
	if type(payload) ~= "string" or #payload > 255 then
		return false
	end
	local version, requestId, target, rawId, status = payload:match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
	if version ~= "1" then
		return false
	end
	requestId, target = self:UnescapePayload(requestId), self:NormalizeMemberName(self:UnescapePayload(target))
	local questId = self:SafeToNumber(self:UnescapePayload(rawId))
	if not questId or questId <= 0 or questId > 2147483647 or questId ~= math.floor(questId) then
		return false
	end
	if not target or requestId == "" or #requestId > 100 or not SHARE_STATUS[status] then
		return false
	end
	-- Group messages addressed to somebody else still identify their actual
	-- sender as a QT user. Recognition grants no share or response authority.
	self:RecordQTPlayerPresence(sender, true)
	if target ~= PlayerName(self) or not self:IsGroupedSender(sender) then
		return false
	end
	if route == "WHISPER" then self:RememberDirectCommPeer(sender, true) end
	local state, now = self:GetPartyQuestShareState(), self.API.GetTime()
	if status ~= "request" then
		local request = state.outgoing[requestId]
		if
			not request
			or request.target ~= sender
			or request.questId ~= questId
			or now >= request.expires
			or (request.status ~= "request" and request.status ~= "pending")
		then
			return false
		end
		request.status = status
		self:QueuePartyQuestCompareRender()
		return true
	end
	local key = sender .. ":" .. requestId
	local recentCount, pendingCount = 0, 0
	for name, expiry in pairs(state.peers) do
		if expiry <= now then
			state.peers[name] = nil
		end
	end
	for id, expiry in pairs(state.recent) do
		if expiry <= now then
			state.recent[id] = nil
		else
			recentCount = recentCount + 1
		end
	end
	for _ in pairs(state.incoming) do
		pendingCount = pendingCount + 1
	end
	if state.recent[key] then
		return false
	end
	-- Remember rejected requests too: replaying them must not become a later
	-- approval. Bounds and rate limits reject new requests with a terminal reply.
	if recentCount < 128 then
		state.recent[key] = now + 120
	end
	if recentCount >= 128 or pendingCount >= 10 or (state.peers[sender] or 0) > now then
		self:SendPartyQuestShareMessage(sender, questId, requestId, "unavailable")
		return false
	end
	state.peers[sender] = now + SHARE_COOLDOWN
	local index = self:GetQuestShareAvailability(questId)
	if not index then
		self:SendPartyQuestShareMessage(sender, questId, requestId, "unavailable")
		return false
	end
	state.sequence = state.sequence + 1
	local request = {
		key = key,
		sender = sender,
		questId = questId,
		requestId = requestId,
		expires = now + SHARE_LIFETIME,
		order = state.sequence,
	}
	state.incoming[key] = request
	if self:GetOption("autoAcceptPartyShareRequests") == true then
		-- This is a single attempt, never a delayed/retried share after restrictions.
		if self:ConfirmPartyQuestShare(request, false, true) then
			return true
		end
		if state.incoming[key] ~= request then
			return false
		end
	end
	self:SendPartyQuestShareMessage(sender, questId, requestId, "pending")
	self.API.Delay(SHARE_LIFETIME, function()
		if self.partyQuestShareState == state and state.incoming[key] == request then
			self:FinishPartyQuestShare(request, "expired")
		end
	end)
	self:QueuePartyQuestSharePrompt()
	return true
end

function QuestTogether:GetNextPartyQuestShareRequest()
	local state, nextRequest = self.partyQuestShareState, nil
	for _, request in pairs(state and state.incoming or {}) do
		if
			self.API.GetTime() < request.expires
			and self:IsGroupedSender(request.sender)
			and not self:IsIgnoredPlayerName(request.sender)
			and (not nextRequest or request.order < nextRequest.order)
		then
			nextRequest = request
		end
	end
	return nextRequest
end

function QuestTogether:FinishPartyQuestShare(request, status)
	local state = self.partyQuestShareState
	if not state or state.incoming[request.key] ~= request then
		return false
	end
	state.incoming[request.key] = nil
	self:SendPartyQuestShareMessage(request.sender, request.questId, request.requestId, status)
	self:QueuePartyQuestSharePrompt()
	return true
end

function QuestTogether:ConfirmPartyQuestShare(request, alwaysAllow, automatic)
	local state = self.partyQuestShareState
	if not request or not state or state.incoming[request.key] ~= request then
		return false
	end
	if
		not self.isEnabled
		or self.API.GetTime() >= request.expires
		or not self:IsGroupedSender(request.sender)
		or self:IsIgnoredPlayerName(request.sender)
	then
		self:FinishPartyQuestShare(request, "expired")
		return false
	end
	local index = self:GetQuestShareAvailability(request.questId)
	if not index then
		self:FinishPartyQuestShare(request, "unavailable")
		return false
	end
	if not automatic and alwaysAllow == true then
		self:SetOption("autoAcceptPartyShareRequests", true)
	end
	if self.API.PushQuestToParty(index) ~= true then
		if not automatic then
			self:FinishPartyQuestShare(request, "unavailable")
		end
		return false
	end
	self:FinishPartyQuestShare(request, "sent")
	return true
end
