-- SPDX-License-Identifier: GPL-3.0-only
-- See LICENSING.md for scope and preserved third-party notices.
local QT = _G.QuestTogether
local L = QT.Translate
local function Copy(value)
	local result = {}; for key, item in pairs(value or {}) do result[key] = item end; return result
end
local function IDs(values)
	local ids = {}; for id in pairs(values or {}) do ids[#ids + 1] = id end; table.sort(ids); return ids
end
local function Related(graph, root, backwards)
	local links, seen, queue = {}, {}, { root }
	for _, edge in ipairs(graph.edges or {}) do
		if not edge.negative and (edge.kind == "prerequisite_all" or edge.kind == "prerequisite_any" or edge.kind == "unlock") then
			local from, to = edge.from, edge.to
			if backwards then from, to = to, from end
			links[from] = links[from] or {}; links[from][#links[from] + 1] = to
		end
	end
	local cursor = 1
	while cursor <= #queue do
		local id = queue[cursor]; cursor = cursor + 1
		for _, nextID in ipairs(links[id] or {}) do
			if nextID ~= root and graph.nodes[nextID] and not seen[nextID] then
				seen[nextID], queue[#queue + 1] = true, nextID
			end
		end
	end
	-- Native quest-line membership provides an order, not prerequisite proof.
	-- These positions describe only the fictional teammates' sample logs.
	if graph.membershipOnly then
		local before = true
		for _, id in ipairs(graph.order or {}) do
			if id == root then before = false elseif before == backwards then seen[id] = true end
		end
	end
	return seen
end

function QT:ConfigurePartyQuestChainPreview(preview)
	local owner, paint = self, self.RenderPartyQuestCompare
	preview.chainPreview, preview.liveQuestData, preview.isEnabled = true, true, true
	preview.db, preview.chainPreviewJobs = { profile = {} }, {}
	preview.options.compareGroupByChain = self:GetOption("compareGroupByChain") == true
	preview.options.compareHideFutureQuestNames = self:GetOption("compareHideFutureQuestNames") ~= false
	-- Explicit read adapters only: never inherit the live addon, its provider,
	-- scheduler, completion cache, saved options, or native focus controller.
	for _, key in ipairs({
		"Delay", "GetQuestChainClient", "GetAddOnMetadata", "CanReadNativeQuestChains", "GetMapInfo",
		"GetBestMapForUnit", "GetQuestLineInfo", "GetQuestLineQuests", "GetQuestChainQuestTitle",
		"RequestQuestChainQuestData", "RequestQuestLinesForMap", "GetQuestChainCurrentMapID",
		"GetPlayerMapID", "GetCharacterQuestHistoryStatus", "GetQuestChainUnitInfo", "GetActiveTrackedQuestID",
		"GetQuestDifficultyLevel", "GetQuestDifficultyColor", "GetQuestGroupRecommended",
	}) do preview.API[key] = owner.API[key] end
	for _, method in ipairs({
		"NormalizeQuestID", "ReadCharacterQuestHistoryStatus", "AttachPartyQuestChains", "CancelPartyQuestChains",
		"SetPartyQuestChainMetadataInterest", "SetPartyQuestChainSelection", "QueuePartyQuestChainRefresh",
		"OpenPartyQuestChain", "TogglePartyQuestChain", "ClosePartyQuestChain", "TogglePartyQuestChainGroup",
		"ExpandPartyQuestChain", "ResolvePartyQuestChainRowID", "GetPartyQuestChainDisplayTitle",
		"GetPartyQuestChainStatus", "DescribePartyQuestChainRequirements", "AppendPartyQuestChainSection",
		"DecoratePartyQuestChainRows", "GetPartyQuestChainActions", "GetPartyQuestChainDiagnostics",
		"RevalidateQuestChainProvider", "CancelQuestChainProvider", "GetQuestChainProviderCapability",
		"SetQuestChainMetadataInterest", "RequestQuestChainMetadata", "GetQuestChainQuestInfo",
		"GetQuestChainStarterLocations", "OnQuestChainDataEvent", "GetQuestChainGraph", "EvaluateQuestChainRequirements",
		"PreparePartyQuestShareRequirements", "RefreshPartyQuestShareRequirements",
	}) do preview[method] = self[method] end
	local openChain, closeChain = preview.OpenPartyQuestChain, preview.ClosePartyQuestChain
	function preview:OpenPartyQuestChain(id, origin)
		local opened = openChain(self, id, origin)
		if opened then self.partyQuestCompareSession.autoOpenChain = nil end
		return opened
	end
	function preview:ClosePartyQuestChain()
		local closed, origin = closeChain(self)
		if closed then self.partyQuestCompareSession.autoOpenChain = nil end
		return closed, origin
	end

	function preview:ScheduleRuntimeWork(category, key, callback, options)
		local session = self.partyQuestCompareSession
		if not session or type(self.API.Delay) ~= "function" then return false end
		local identity = category .. ":" .. key
		local work = { owner = options and options.owner }
		self.chainPreviewJobs[identity] = work
		local run
		run = function()
			if self.partyQuestCompareSession ~= session or self.chainPreviewJobs[identity] ~= work
				or (work.owner and work.owner.active == false) then return end
			if owner.isLoggingOut then return end
			-- A temporary restriction suspends the same guarded work item. Dropping
			-- it would strand chain pending flags or a partially indexed provider.
			if self:IsRuntimeRestricted() or self:IsWorkBlocked(category) then self.API.Delay(0.25, run); return end
			self.chainPreviewJobs[identity] = nil
			callback()
		end
		self.API.Delay(options and options.delay or 0, run)
		return true
	end
	function preview:CancelRuntimeWorkOwner(workOwner)
		for key, work in pairs(self.chainPreviewJobs) do
			if work.owner == workOwner then self.chainPreviewJobs[key] = nil end
		end
	end
	function preview:ScheduleDeferredWork(category, key, callback, delay)
		return self:ScheduleRuntimeWork(category, key, callback, { delay = delay })
	end
	function preview:GetPartyQuestChainCharacterEvidence(member)
		if member.isLocal and self.API.GetQuestChainUnitInfo then
			local ok, value = pcall(self.API.GetQuestChainUnitInfo, "player")
			if ok and type(value) == "table" then return value end
		end
		return { classFile = member.classFile }
	end
	function preview:SetPartyQuestCompletionInterest(ids, source)
		local session = self.partyQuestCompareSession
		if not session then return end
		session.historyInterestOwners = session.historyInterestOwners or {}
		session.historyInterestOwners[source or "visible"] = Copy(ids)
		-- This method also runs while painting visible rows. It only records
		-- demand; bounded native history reads happen on later frames and publish
		-- evidence exclusively into the preview's local member.
		if session.previewHistoryPending then return end
		local own, now, needsRead = session.members[1], self:GetPartyQuestCompareTime(), false
		for _, interested in pairs(session.historyInterestOwners) do
			for _, id in ipairs(interested) do
				local evidence = own.questHistory[id]
				if not evidence or now < evidence.sampledAt or now >= evidence.sampledAt + 30 then needsRead = true end
			end
		end
		if not needsRead then return end
		session.previewHistoryPending = true
		self:ScheduleDeferredWork("quest_snapshot_refresh", "preview_local_history", function()
			session.previewHistoryPending = nil
			local read, wanted = 0, {}
			local sampledAt = self:GetPartyQuestCompareTime()
			for _, interested in pairs(session.historyInterestOwners) do
				for _, id in ipairs(interested) do wanted[id] = true end
			end
			for _, id in ipairs(IDs(wanted)) do
				local evidence = own.questHistory[id]
				if read < 32 and (not evidence or sampledAt < evidence.sampledAt or sampledAt >= evidence.sampledAt + 30) then
					own.questHistory[id] = { status = self:ReadCharacterQuestHistoryStatus(id), sampledAt = sampledAt }
					read = read + 1
				end
			end
			self:QueuePartyQuestCompareRender()
		end, 0)
	end

	local function Feedback(action)
		local session = preview.partyQuestCompareSession
		if not session or preview:IsWorkBlocked("foreign_frame_mutation") then return false end
		session.message = L("Preview only: ") .. action .. L(". No quest or message was sent.")
		preview:QueuePartyQuestCompareRender()
		return true
	end
	preview.focusController = nil
	function preview:GetPartyQuestFocusID(name)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		return member and (member.isLocal and self.previewFocus or member.focusQuestId) or nil
	end
	function preview:GetPartyQuestFollowTarget() return self.previewFollowing end
	function preview:GetPartyFollowingText()
		return self.previewFollowing and string.format(L("Following: %s"), self.previewFollowing) or ""
	end
	function preview:RequestPartyQuestFocus(name, id)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		if not member or not member.entries[id] or self:IsWorkBlocked("foreign_frame_mutation") then return false end
		self.previewFollowing, self.previewFocus = not member.isLocal and name or nil, id
		return Feedback(L("Focus quest"))
	end
	preview.SelectPartyQuestFocus = preview.RequestPartyQuestFocus
	function preview:FollowPartyQuestFocus(name)
		local session = self.partyQuestCompareSession
		local member = session and session.byName[name]
		return member and not member.isLocal and self:RequestPartyQuestFocus(name, member.focusQuestId) or false
	end
	function preview:PopulatePartyFocusMenu(root, name)
		local session, frame = self.partyQuestCompareSession, self.partyQuestCompareWindow
		local member = session and session.byName[name]
		if not member or member.isLocal then return end
		root:CreateTitle(self:GetPartyFocusLabel(name))
		root:CreateButton(self:GetPartyQuestFollowTarget() == name and L("Stop following") or L("Follow quest focus"), function()
			if self.partyQuestCompareSession ~= session or session.byName[name] ~= member
				or not frame or not frame:IsShown() then return false end
			if self:GetPartyQuestFollowTarget() == name then return self:StopPartyQuestFollow() end
			return self:FollowPartyQuestFocus(name)
		end)
	end
	function preview:StopPartyQuestFollow()
		if not self.partyQuestCompareSession or self:IsWorkBlocked("foreign_frame_mutation") then return false end
		self.previewFollowing = nil; return Feedback(L("Stop following"))
	end
	function preview:ApplyPartyQuestFocus()
		if self.previewFollowing then return self:FollowPartyQuestFocus(self.previewFollowing) end
	end
	function preview:OnPartyNavigationTrackingChanged() end
	function preview:SamplePartyNavigation() end
	function preview:ReconcilePartyQuestFollow() end
	function preview:OpenPingWaypoint() return Feedback(L("Set waypoint")) end
	function preview:ShowQuestChainGiver(_, valid)
		return (not valid or valid()) and Feedback(L("Find quest giver")) or false
	end

	local function Title(id)
		local info = preview:GetQuestChainQuestInfo(id)
		return preview:NormalizeQuestDisplayTitleText(info and info.title or (L("Quest ") .. id))
	end
	function preview:BuildChainPreviewMembers(session, state)
		local snapshot = self.questChainProviderSnapshot
		if not snapshot or snapshot.state ~= "ready" then return end
		if session.previewRevision == snapshot.revision and session.previewGeneration == snapshot.generation then return end
		session.previewRevision, session.previewGeneration = snapshot.revision, snapshot.generation
		local now, own, seen = self:GetPartyQuestCompareTime(), session.members[1], {}
		local bestID, bestSize = session.localQuestOrder[1], 0
		self.questCatalog, self.questOrder = {}, {}
		for _, id in ipairs(session.localQuestOrder) do
			self.questCatalog[id] = { title = own.entries[id].questTitle }
			self.questOrder[#self.questOrder + 1] = id
		end
		for index = 2, #session.members do
			local member = session.members[index]
			member.entries, member.questHistory, member.focusQuestId = {}, {}, 0
			member.state = index == 5 and "timeout" or "ready"
			member.sampledAt = now
		end
		local function Active(member, id, ready)
			if not id then return end
			local original = own.entries[id]
			member.entries[id] = { questId = id, questTitle = original and original.questTitle or Title(id),
				isComplete = ready == true, isPushable = original and original.isPushable or false }
			if member.focusQuestId == 0 then member.focusQuestId = id end
		end
		for _, root in ipairs(session.localQuestOrder) do
			-- Graph reads are bounded cached model queries, outside rendering. The
			-- provider's asynchronous index is never scanned by a paint callback.
			local graph = self:GetQuestChainGraph(root, { limit = 80 })
			if graph then
				local order = graph.order or IDs(graph.nodes)
				if #order > bestSize then bestID, bestSize = root, #order end
				if not seen[graph.key] then
					seen[graph.key] = true
					local before, after = Related(graph, root, true), Related(graph, root, false)
					local earlier, later, branch
					for _, id in ipairs(order) do
						if before[id] then earlier = id end
						if after[id] and not later then later = id end
						if id ~= root and not before[id] and not after[id] and not branch then branch = id end
						if not self.questCatalog[id] then
							self.questCatalog[id] = { title = Title(id) }; self.questOrder[#self.questOrder + 1] = id
						end
					end
					local positions = { earlier, root, later, branch }
					for index = 2, #session.members do
						local member, position = session.members[index], positions[index - 1]
						local completed = position and Related(graph, position, true) or {}
						for _, id in ipairs(order) do
							local status = completed[id] or (index == 4 and not later) and true
							member.questHistory[id] = { status = status and "completed" or "incomplete", sampledAt = now }
						end
						Active(member, position, index == 3)
					end
				end
			end
		end
		if session.autoOpenChain and bestID then
			state.rootQuestID, state.selectedQuestID, state.originRowId = bestID, bestID, "quest:" .. bestID
			-- Retail membership can arrive after the first ready-but-empty snapshot.
			if bestSize > 1 or snapshot.kind ~= "retail" then session.autoOpenChain = nil end
		end
	end
	function preview:PreparePartyQuestChains(session, state)
		if self.partyQuestCompareSession ~= session or state.retired then return end
		self:BuildChainPreviewMembers(session, state)
		return owner.PreparePartyQuestChains(self, session, state)
	end
	function preview:QueuePartyQuestCompareRender()
		self:QueuePartyQuestChainRefresh()
	end
	function preview:RenderPartyQuestCompare()
		local session = self.partyQuestCompareSession
		if not session or self:IsWorkBlocked("foreign_frame_mutation") then return end
		paint(self)
		local status = self:GetQuestChainProviderCapability()
		local label = not session.snapshotUnavailable and #session.localQuestOrder == 0
			and L("CHAIN PREVIEW · Your quest log is empty. Accept a quest, then Refresh to preview its relationships.")
			or status.state == "loading" and L("CHAIN PREVIEW · Loading your quest relationships…")
			or L("CHAIN PREVIEW · Your quest log and real quest relationships + 4 simulated teammates · All actions are simulated · Refresh rebuilds the sample")
		self.partyQuestCompareWindow.summary:SetText(label .. (session.message and ("\n" .. session.message) or ""))
	end
	function preview:StartNavigationObserver()
		local observer = self.chainPreviewObserver
		if not observer then
			observer = self:CreateOwnedWindowFrame("Frame", nil, self.partyQuestCompareWindow)
			self.chainPreviewObserver = observer
			observer:SetScript("OnEvent", function(_, event, ...)
				if self.partyQuestCompareSession and not self:IsRuntimeRestricted() then self:OnQuestChainDataEvent(event, ...) end
			end)
		end
		for _, event in ipairs({ "ADDON_LOADED", "QUEST_DATA_LOAD_RESULT", "QUESTLINE_UPDATE" }) do
			if observer.RegisterEvent then pcall(observer.RegisterEvent, observer, event) end
		end
		observer:Show()
	end
	function preview:CancelPartyQuestCompare()
		self:CancelPartyQuestChains(self.partyQuestCompareSession)
		self.partyQuestCompareSession, self.partyNavigationState, self.chainPreviewJobs = nil, nil, {}
		if self.chainPreviewObserver then
			if self.chainPreviewObserver.UnregisterAllEvents then self.chainPreviewObserver:UnregisterAllEvents() end
			self.chainPreviewObserver:Hide()
		end
	end
	function preview:RefreshPartyQuestCompare()
		if self:IsWorkBlocked("quest_snapshot_refresh") then return false end
		local previous = self.partyQuestCompareSession
		local entries = owner:BuildQuestCompareEntries()
		if not entries and previous then
			previous.message = L("Snapshot unavailable")
			self:QueuePartyQuestCompareRender()
			return false
		end
		self:CancelPartyQuestCompare()
		local own = { name = owner:GetPlayerFullName(), classFile = owner:GetPlayerClassFile(), isLocal = true,
			state = entries and "ready" or "unavailable", entries = {}, questHistory = {}, focusQuestId = 0, sampledAt = self:GetPartyQuestCompareTime() }
		local session = { playerName = own.name, members = { own }, byName = { [own.name] = own },
			search = previous and previous.search or "", offset = 0, localQuestOrder = {}, autoOpenChain = true,
			snapshotUnavailable = not entries, message = not entries and L("Snapshot unavailable") or nil }
		for _, source in ipairs(entries or {}) do
			local id = self:NormalizeQuestID(source.questId)
			if id and not own.entries[id] then own.entries[id] = Copy(source); session.localQuestOrder[#session.localQuestOrder + 1] = id end
		end
		for index, name in ipairs({ "Aria", "Borin", "Celia", "Dara" }) do
			name = name .. " (" .. L("Simulated") .. ")"
			if name == own.name then name = name .. " (QT)" end
			local member = { name = name, classFile = ({ "MAGE", "WARRIOR", "HUNTER", "ROGUE" })[index],
				state = "ready", entries = {}, questHistory = {}, sampledAt = self:GetPartyQuestCompareTime(),
				supportsShareRequests = true, supportsQuestHistory = true, focusQuestId = 0 }
			session.members[#session.members + 1], session.byName[name] = member, member
		end
		self.partyQuestCompareSession, self.partyNavigationState = session, { peers = {} }
		local focus
		if self.API.GetActiveTrackedQuestID then
			local ok, id = pcall(self.API.GetActiveTrackedQuestID)
			if ok then focus = self:NormalizeQuestID(id) end
		end
		self.previewFocus, self.previewFollowing, self.incompleteData, self.statuses = focus and own.entries[focus] and focus or 0, nil, false, {}
		self.questCatalog, self.questOrder = {}, Copy(session.localQuestOrder)
		for id, entry in pairs(own.entries) do self.questCatalog[id] = { title = entry.questTitle } end
		local state = self:AttachPartyQuestChains(session)
		state.rootQuestID, state.selectedQuestID = session.localQuestOrder[1], session.localQuestOrder[1]
		state.originRowId = state.rootQuestID and ("quest:" .. state.rootQuestID)
		self:StartNavigationObserver()
		self.partyQuestCompareWindow.horizontalOffset = 0
		self:QueuePartyQuestCompareRender()
		return true
	end
end
