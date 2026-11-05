-- Party-owned data must outlive the windows that happen to display it. These
-- scenarios use real coordinators, native outcomes and asynchronous delivery.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual

local function Await(net, seconds, predicate, message)
	local deadline = net.now + seconds
	while net.now < deadline do
		if predicate() then return end
		net:Advance(0.5)
	end
	assert(predicate(), message)
end

local function Party(count, quests, options)
	local net, peers = QT:CreateTestNetwork(options or { fps = 10 }), {}
	for index = 1, count do
		local peer = net:AddPeer("Sync" .. index .. "-Realm", { group = "sync-party" })
		peer.db.profile.questTrackerMode = "hidden"
		peer.db.profile.compareAutoRefresh = false
		peer.progress = index
		local rows = {}
		for id = 1, quests do rows[id] = { questID = id, title = "Shared quest " .. id } end
		net:SetQuestLog(peer, rows)
		function peer:ReadQuestCompareObjectives(id)
			return {
				{ questId = id, objectiveIndex = 1, text = "Supplies collected: " .. self.progress .. "/10",
					kind = "item", current = self.progress, required = 10, finished = false },
				{ questId = id, objectiveIndex = 2, text = "Scouts found: 0/3", kind = "monster",
					current = 0, required = 3, finished = false },
			}
		end
		peers[index] = peer
	end
	for _, peer in ipairs(peers) do net:StartPeer(peer) end
	return net, peers
end

local function Detail(viewer, name, id)
	local member = viewer:GetPartyQuestSyncMember(name)
	return member and member.objectiveDetails and member.objectiveDetails[id], member
end

local function Ready(viewer, name, count)
	local member = viewer:GetPartyQuestSyncMember(name)
	if not member or member.state ~= "ready" then return false end
	for id = 1, count do
		local record = member.objectiveDetails and member.objectiveDetails[id]
		if not member.entries[id] or not record or not record.hasEntry or not record.objectives
			or #record.objectives ~= 2 then return false end
	end
	return true
end

local function Announce(peer, value, stamp, questId)
	peer.progress = value
	assert(peer:Emit("ANN", {
		eventType = "QUEST_PROGRESS", senderName = peer.name, classFile = "MAGE", questId = tostring(questId or 1),
		text = "Supplies collected: " .. value .. "/10", occurredAt = stamp or peer.API.GetServerTime(),
		eventFacts = peer:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "item", false, value, 10),
	}, { { distribution = "PARTY", requiresGroup = true } }))
end

QT:RegisterTest("party sync prepares all five clients before either quest view opens", function()
	local net, peers = Party(5, 3, { fps = 5, seed = 37 })
	local started = net.now
	local backgroundPackets = { QCMP = 0, QCRS = 0 }
	-- The party path must work even while the launch-era custom-channel problem
	-- also affects unrelated background traffic.
	net.sendRule = function(packet, _, sender)
		local operation = sender:DecodeCommFrame(packet.wire).operation
		if backgroundPackets[operation] then
			backgroundPackets[operation] = backgroundPackets[operation] + 1
			Equal(sender:GetTransportState().inFlight.priority, "background",
				"unviewed party requests and replies must yield to interactive traffic")
		end
		return (packet.route == "CHANNEL" or packet.route == "WHISPER") and 7 or 0
	end
	Await(net, 100, function()
		for _, viewer in ipairs(peers) do
			for _, remote in ipairs(peers) do
				if remote ~= viewer and not Ready(viewer, remote.name, 3) then return false end
			end
		end
		return true
	end, "every party member must warm its cache without a PQL session or POT hover")
	assert(backgroundPackets.QCMP > 0 and backgroundPackets.QCRS > 0)
	for _, viewer in ipairs(peers) do
		Equal(viewer.partyQuestCompareSession, nil)
		Equal(viewer.questFocusState, nil)
		local records = 0
		for _ in pairs(viewer.partyQuestProgress) do records = records + 1 end
		Equal(records, 12, "retain one detail record per remote quest")
		for _, remote in ipairs(peers) do
			if remote ~= viewer then
				local record = Detail(viewer, remote.name, 1)
				Equal(record.objectives[1].current, remote.progress)
				local owner = {}
				Equal(viewer:AcquirePartyQuestProgress(remote.name, 1, owner, function() end, true), record)
				assert(record.hasEntry and not record.requestId, "a fresh cached hover must not start another fetch")
				viewer:ReleasePartyQuestProgress(owner)
				Equal(Detail(viewer, remote.name, 1), record, "closing the last view must retain the party cache")
			end
		end
		local bytes = 0
		for _, packet in ipairs(viewer.sent) do bytes = bytes + #packet.wire + #packet.prefix + 40 end
		assert(bytes <= 800 * (net.now - started) + 1600, "party prefetch must conserve transport byte budget")
		assert(#viewer.sent <= 4 * (net.now - started) + 4, "party prefetch must conserve transport packet budget")
	end
	local viewer, remote, owner = peers[1], peers[2], {}
	local retained = Detail(viewer, remote.name, 1)
	for id = 1000, 1255 do
		viewer:AcquirePartyQuestProgress(remote.name, id, owner, function() end, true)
		viewer:ReleasePartyQuestProgress(owner)
	end
	local count = 0
	for _, record in pairs(viewer.partyQuestProgress) do
		if record.name == remote.name then count = count + 1 end
	end
	assert(count <= 128, "temporary absent-quest hovers must have a fixed cache bound")
	Equal(Detail(viewer, remote.name, 1), retained, "hover churn cannot evict party-owned quest details")
	assert(viewer:RefreshPartyQuestCompare(nil, nil, true))
	Equal(viewer.partyQuestCompareSession.byName[remote.name], viewer:GetPartyQuestSyncMember(remote.name),
		"PQL must subscribe to the party's existing member record")
	viewer:TogglePartyQuestObjectives(1)
	Equal(viewer.partyQuestCompareSession.byName[remote.name].objectiveDetails[1], retained)
	viewer:CancelPartyQuestCompare()
	Equal(Detail(viewer, remote.name, 1), retained, "closing PQL cannot discard the shared data")
end, { offline = true })

QT:RegisterTest("hidden party data accepts announcements and repairs a lost update periodically", function()
	local net, peers = Party(2, 1)
	local viewer, remote = peers[1], peers[2]
	Await(net, 40, function() return Ready(viewer, remote.name, 1) end, "initial hidden party cache did not load")
	local record = Detail(viewer, remote.name, 1)
	Announce(remote, 4)
	Await(net, 10, function() return record.objectives[1].current == 4 end, "hidden cache ignored a live announcement")
	local dropped = 0
	net.deliveryRule = function(packet, receiver)
		if receiver == viewer and viewer:DecodeCommFrame(packet.wire).operation == "ANN" then
			dropped = dropped + 1
			return { drop = true }
		end
	end
	Announce(remote, 7)
	net:Advance(5)
	assert(dropped > 0)
	Equal(record.objectives[1].current, 4, "the repair scenario must really miss the announcement")
	Await(net, 150, function() return record.objectives[1].current == 7 end, "periodic sync must repair lost progress without opening UI")
	Equal(Detail(viewer, remote.name, 1), record)
	Equal(viewer.partyQuestCompareSession, nil)
	Equal(viewer.questFocusState, nil)
	-- Reordering must not retire the log entry in one store while the newer
	-- objective survives in the other.
	net.deliveryRule = nil
	local stamp = remote.API.GetServerTime()
	Announce(remote, 8, stamp + 10)
	Await(net, 10, function() return record.objectives[1].current == 8 end, "new progress did not arrive")
	assert(remote:Emit("ANN", { eventType = "QUEST_REMOVED", senderName = remote.name,
		classFile = "MAGE", questId = "1", text = "", occurredAt = stamp + 5 },
		{ { distribution = "PARTY", requiresGroup = true } }))
	net:Advance(3)
	Equal(Detail(viewer, remote.name, 1), record, "an older lifecycle event cannot replace newer progress")
	assert(viewer:GetPartyQuestSyncMember(remote.name).entries[1], "summary ordering must agree with objective ordering")
	Equal(record.objectives[1].current, 8)
end, { offline = true })

QT:RegisterTest("the first party summary invalidates an earlier detail snapshot before PQL subscribes", function()
	local net, peers = Party(2, 1)
	local viewer, remote = peers[1], peers[2]
	viewer:UpdatePartyQuestSync()
	local member = viewer:GetPartyQuestSyncMember(remote.name)
	member.nextRequest = net.now + 60
	local record = viewer:AcquirePartyQuestProgress(remote.name, 1, {}, function() end, true)
	Await(net, 20, function() return record.hasEntry end, "foreground detail must finish before the first summary")
	Equal(member.sampledAt, nil)
	Equal(record.entry.isComplete, false)
	remote.questLog[1].isComplete = true
	assert(viewer:RefreshPartyQuestSyncMember(remote.name, true))
	Await(net, 20, function() return member.sampledAt ~= nil end, "new ready summary did not arrive")
	assert(member.entries[1].isComplete)
	assert(viewer:RefreshPartyQuestCompare(nil, nil, true))
	viewer:TogglePartyQuestObjectives(1)
	assert(member.entries[1].isComplete, "PQL cannot reinstall an obsolete cached detail over the first summary")
	assert(record.entry == nil or record.entry.isComplete, "old detail readiness must be invalidated")
end, { offline = true })

QT:RegisterTest("confirmed party absence retires background interests created by unseen announcements", function()
	local net, peers = Party(2, 1)
	local viewer, remote = peers[1], peers[2]
	Await(net, 40, function() return Ready(viewer, remote.name, 1) end, "initial party cache did not load")
	Announce(remote, 4, nil, 99)
	Await(net, 10, function() return Detail(viewer, remote.name, 99) ~= nil end, "unseen announcement did not populate cache")
	local record, member = Detail(viewer, remote.name, 99)
	assert(record.listeners[member])
	local sampled = member.sampledAt
	assert(viewer:RefreshPartyQuestSyncMember(remote.name, true))
	Await(net, 20, function() return member.sampledAt > sampled end, "absence confirmation did not arrive")
	Equal(member.objectiveDetails[99], nil)
	Equal(next(record.listeners), nil, "confirmed absent quests cannot retain immortal background interests")
	local owner = {}
	for id = 1000, 1255 do
		viewer:AcquirePartyQuestProgress(remote.name, id, owner, function() end, true)
		viewer:ReleasePartyQuestProgress(owner)
	end
	local fresh = viewer:AcquirePartyQuestProgress(remote.name, 2000, owner, function() end, true)
	assert(fresh, "absence entries must stay evictable when new quests need a cache slot")
	assert(not fresh.requestId, "confirmed absence does not require another detail fetch")
end, { offline = true })

QT:RegisterTest("detached party requests survive the cache retention interval until their own completion", function()
	local net, peers = Party(2, 0, { fps = 5 })
	local viewer, remote = peers[1], peers[2]
	viewer:UpdatePartyQuestSync()
	local owner, requestId, calls, completed = {}, nil, 0, 0
	net.deliveryRule = function(packet, receiver)
		local frame = viewer:DecodeCommFrame(packet.wire)
		if receiver == viewer and frame.operation == "QCRS" and frame.requestId == requestId then
			return { delay = 130 }
		end
	end
	local record = viewer:AcquirePartyQuestProgress(remote.name, 99, owner, function() calls = calls + 1 end, true)
	requestId = assert(record.requestId)
	local pending = assert(viewer:GetPendingQuestCompare(requestId))
	local onDone = pending.receiver.onDone
	pending.receiver.onDone = function(...)
		completed = completed + 1
		return onDone(...)
	end
	viewer:ReleasePartyQuestProgress(owner)
	net:Advance(121)
	Equal(viewer:GetPendingQuestCompare(requestId), pending, "cache eviction must not cancel an active initial fetch")
	Await(net, 30, function() return completed == 1 end, "late data must finish after unhover without a new request")
	Equal(calls, 0, "detached views must not receive the eventual completion")
end, { offline = true })

QT:RegisterTest("abandoned party hovers finish their shared transfers and later views reuse the result", function()
	local net, peers = Party(2, 3)
	local viewer, remote = peers[1], peers[2]
	function remote:ReadQuestCompareObjectives(id)
		local rows = {}
		for index = 1, 5 do
			rows[index] = { questId = id, objectiveIndex = index,
				text = "Collect expedition supplies " .. string.rep("along the coast ", 5) .. index,
				kind = "item", current = 1, required = 5, finished = false }
		end
		return rows
	end
	net.deliveryRule = function(packet, receiver)
		local frame = viewer:DecodeCommFrame(packet.wire)
		if receiver == viewer and frame.operation == "QCRS" and frame.part > 1 then return { delay = 5 } end
	end
	Await(net, 30, function() return viewer:GetPartyQuestSyncMember(remote.name) ~= nil end, "party member not discovered")
	local owner, active, callbacks = {}, true, 0
	local record = viewer:AcquirePartyQuestProgress(remote.name, 1, owner, function() callbacks = callbacks + 1 end,
		true, function() return active end)
	Await(net, 40, function()
		local progress = record.requestId and viewer:GetCommunicationRequestProgress(record.requestId)
		return progress and progress.firstResponseAt and not record.hasEntry
	end, "slow response must be in flight before the hover ends")
	local id, before = record.requestId, callbacks
	active = false
	viewer:ReleasePartyQuestProgress(owner)
	assert(viewer:GetPendingQuestCompare(id), "unhover must not cancel party-owned data transfer")
	-- Moving to another quest subscribes a new view while the earlier transfer
	-- remains useful; neither view owns the lifetime of the party cache.
	local nextOwner = {}
	local nextRecord = viewer:AcquirePartyQuestProgress(remote.name, 2, nextOwner, function() end, true)
	viewer:ReleasePartyQuestProgress(nextOwner)
	Await(net, 60, function() return record.hasEntry and nextRecord.hasEntry end, "detached views must not prevent background completion")
	Equal(callbacks, before, "retired UI callbacks must stay retired")
	Equal(#record.objectives, 5)
	Equal(#nextRecord.objectives, 5)
	local reopened = viewer:AcquirePartyQuestProgress(remote.name, 1, {}, function() end, true)
	Equal(reopened, record)
	assert(reopened.hasEntry and not reopened.requestId, "rehover should display the completed cached snapshot immediately")
	local records = 0
	for _ in pairs(viewer.partyQuestProgress) do records = records + 1 end
	assert(records <= 3, "hover churn cannot create duplicate cached quests")
end, { offline = true })

QT:RegisterTest("party sync lifetime changes reject callbacks from retired summary requests", function()
	for _, change in ipairs({ "depart", "ignore", "disable", "profile", "world" }) do
		local net, peers = Party(2, 1)
		local viewer, remote = peers[1], peers[2]
		local member, pending
		Await(net, 10, function()
			member = viewer:GetPartyQuestSyncMember(remote.name)
			pending = member and member.requestId and viewer:GetPendingQuestCompare(member.requestId)
			return pending ~= nil
		end, "initial summary request must exist before lifetime changes")
		if change == "depart" then
			net:SetGroup(remote, nil)
			viewer:OnPartyQuestRosterChanged()
			viewer:UpdatePartyQuestSync()
		elseif change == "ignore" then
			viewer.ignored[remote.name] = true
			viewer:CancelIgnoredPlayerQuestCompare()
			viewer:UpdatePartyQuestSync()
		elseif change == "disable" then
			viewer.isEnabled = false
			viewer:ResetRuntimeCoordinator()
		elseif change == "profile" then
			viewer.db.profile = viewer:DeepCopy(viewer.db.profile)
			viewer:ResetPartyQuestSync()
		else
			viewer:EndCommsWorldSession()
		end
		Equal(viewer:GetPartyQuestSyncMember(remote.name), nil, change .. " must retire old party data")
		pending.receiver.onEntry({ questId = 999, questTitle = "Retired response", isComplete = true })
		pending.receiver.onDone(true, true, "MAGE", "retired-revision", true)
		assert(not member.entries[999], "a delayed callback cannot mutate retired party data after " .. change)
		Equal(viewer:GetPartyQuestSyncMember(remote.name), nil)
		if change == "world" then
			net:Advance(2)
			Equal(viewer:GetPartyQuestSyncMember(remote.name), nil, "runtime ticks must not restart sync outside the world")
			viewer:ResumeCommsWorldSession()
		end
		if change == "profile" or change == "world" then
			Await(net, 10, function() return viewer:GetPartyQuestSyncMember(remote.name) ~= nil end,
				"a new party lifetime must restart synchronization")
			local replacement = viewer:GetPartyQuestSyncMember(remote.name)
			assert(replacement ~= member)
			pending.receiver.onEntry({ questId = 999, questTitle = "Retired response", isComplete = true })
			pending.receiver.onDone(true, true, "MAGE", "retired-revision", true)
			assert(not replacement.entries[999], "old callbacks cannot contaminate the replacement lifetime")
		end
	end
end, { offline = true })

QT:RegisterTest("unchanged party names still rebind PQL when converting to and from a raid", function()
	local net, peers = Party(2, 1)
	local viewer, remote = peers[1], peers[2]
	Await(net, 40, function() return Ready(viewer, remote.name, 1) end, "initial party cache did not load")
	assert(viewer:RefreshPartyQuestCompare(nil, nil, true))
	local shared, roster = viewer:GetPartyQuestSyncMember(remote.name), viewer.partyRosterFingerprint
	for _, peer in ipairs(peers) do net:SetGroup(peer, "sync-party", "RAID") end
	Equal(viewer.partyRosterFingerprint, roster, "this scenario must not rely on a changed roster fingerprint")
	net:Advance(0.5)
	local raidMember = viewer.partyQuestCompareSession.byName[remote.name]
	assert(raidMember ~= shared and not raidMember.syncOwned, "PQL must leave retired small-party data after raid conversion")
	Await(net, 20, function() return raidMember.state == "ready" end, "raid PQL must retain its existing on-demand data path")
	for _, peer in ipairs(peers) do net:SetGroup(peer, "sync-party", "PARTY") end
	net:Advance(0.5)
	local partyMember = viewer.partyQuestCompareSession.byName[remote.name]
	assert(partyMember ~= raidMember and partyMember == viewer:GetPartyQuestSyncMember(remote.name),
		"returning to a party must reattach PQL to the new shared cache")
end, { offline = true })
