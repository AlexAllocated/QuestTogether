-- End-to-end communication tests use only private peers and engine adapters.
local QT = _G.QuestTogether
local function Equal(actual, expected, detail)
	assert(actual == expected, (detail or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

QT:RegisterTest("asynchronous offline mesh whispers preserve ordinary feedback across chat windows and world departure", function()
	for _, eventFirst in ipairs({ false, true }) do
		for _, ordinary in ipairs({ false, true }) do
			for _, departing in ipairs({ false, true }) do
				local net = QT:CreateTestNetwork({ fps = 5, now = 10000, whisperNotices = true,
					whisperNoticeDelay = 3, systemEventFirst = eventFirst })
				local peer = net:AddPeer("Local Tester", { regional = true })
				net:StartPeer(peer)
				peer:InitializeMeshNetwork()
				assert(peer:RememberMeshCandidate("Absent Peer", "directory", 12))
				local function Attempts()
					local count = 0
					for _, packet in ipairs(peer.attempts) do
						if packet.target == "Absent Peer" then
							Equal(packet.result, 0, "native acceptance is separate from the later server error")
							count = count + 1
						end
					end
					return count
				end
				for _ = 1, 20 do
					if Attempts() > 0 then break end
					net:Advance(0.2)
				end
				Equal(Attempts(), 1, "actual discovery must attempt the offline native address")
				if departing then
					peer:EndCommunicationSession()
					peer.isLoggingOut = true
				end
				if ordinary then peer.ordinaryWhisperObserver("WHISPER", "Absent Peer") end
				net:Advance(4)
				for _, window in ipairs(peer.chatWindows) do
					Equal(window.visibleMessages, ordinary and 1 or 0, "each chat window preserves only ordinary feedback")
				end
				if departing then
					assert(rawget(peer, "meshNetworkState") == nil, "a delayed notice cannot restart a departed mesh")
				else
					assert(peer:IsAddonWhisperTargetUnavailable("Absent Peer"))
					local candidate = peer.meshNetworkState.candidates["Absent Peer"]
					Equal(candidate.lastRetirementReason, "unavailable")
					assert(candidate.retryAt > peer.now + 290)
				end
				net:Advance(65)
				Equal(Attempts(), 1, "the server notice must stop rediscovery even after the short send hold expires")
			end
		end
	end
end, { offline = true })

QT:RegisterTest("party quest snapshots repair over native group and targeted private routes", function()
	for _, mode in ipairs({ "PARTY", "RAID", "INSTANCE_CHAT", "private" }) do
		local net = QT:CreateTestNetwork({ fps = 20 })
		local distribution = mode ~= "private" and mode or nil
		local settings = distribution and { group = "questers", distribution = distribution } or {}
		local a, b, other = net:AddPeer("Alice-Realm", settings), net:AddPeer("Bob-Realm", settings),
			net:AddPeer("Other-Realm", settings)
		for _, peer in ipairs({ a, b, other }) do
			peer.API.IsInInstanceGroup = function() return distribution == "INSTANCE_CHAT" end
			net:SetQuestLog(peer, { { questID = 42, title = "A party quest" } })
			net:StartPeer(peer)
		end
		function b:ReadQuestCompareObjectives(id)
			local objectives = {}
			for index = 1, 4 do
				objectives[index] = { questId = id, objectiveIndex = index, text = string.rep("Objective ", 12) .. index,
					kind = "item", current = index, required = 8, finished = false }
			end
			return objectives
		end
		local responseParts, routes, done, expired, requestId = {}, {}, 0, 0, nil
		function other:HandleQuestCompareResponse(data, sender)
			assert(data.requestId ~= requestId, "an unrelated group member installed a private response")
			return QT.HandleQuestCompareResponse(self, data, sender)
		end
		local relevant = { QCMP = true, QCRS = true, FXEND = true, FXACK = true, FXMISS = true, FXSTAT = true }
		net.sendRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			if relevant[frame.operation] then
				routes[#routes + 1] = packet
				if mode ~= "private" then
					Equal(packet.route, distribution)
					Equal(packet.target, nil, "group sends must not pass a whisper target to the native API")
				elseif mode == "private" then Equal(packet.route, "WHISPER") end
			end
			return 0
		end
		net.deliveryRule = function(packet, receiver)
			local frame = a:DecodeCommFrame(packet.wire)
			if frame.operation == "QCRS" and frame.requestId == requestId and receiver == a then
				responseParts[frame.part] = (responseParts[frame.part] or 0) + 1
				if frame.part == 2 and responseParts[2] == 1 then return { drop = true } end
			end
		end
		local accepted
		accepted, requestId = a:RequestQuestCompare(b.name, { objectiveQuestId = 42,
			onEntry = function(entry) Equal(#entry.objectives, 4); Equal(entry.objectives[4].current, 4) end,
			onDone = function() done = done + 1 end, onTimeout = function() expired = expired + 1 end })
		assert(accepted)
		net:Advance(20)
		Equal(done, 1, "snapshot must finish over " .. mode)
		Equal(expired, 0)
		Equal(responseParts[2], 2)
		assert(#routes > 4)
		for _, job in ipairs(b.commTransferState.outgoing) do
			assert(job.operation ~= "QCRS" or job.requestId ~= requestId,
				"acknowledged snapshot must release its repair copy")
		end
	end
end, { offline = true })

QT:RegisterTest("mesh public discovery covers a population beyond direct neighbors with authenticated relays", function()
	local net = QT:CreateTestNetwork({ fps = 5, seed = 42, latency = 0.08, joinDelay = 0.3, directoryDelay = 0.5 })
	local peers, relayed = {}, {}
	for index = 1, 20 do
		local peer = net:AddPeer(string.format("Crowd%03d-Realm", index), {
			mapID = 12, x = 0.05 + (index % 20) / 25, y = 0.05,
		})
		peers[index], relayed[index] = peer, {}
		local origins, dispatch = relayed[index], peer.DispatchVerifiedMeshRecord
		function peer:DispatchVerifiedMeshRecord(frame, data, origin, context)
			local before = self:GetPlayerLocationState().peers[origin]
			local accepted = dispatch(self, frame, data, origin, context)
			local after = self:GetPlayerLocationState().peers[origin]
			-- Former neighbors can leave visible records after rotation. Only a
			-- different native relay carrying an authenticated publication that
			-- actually installs LOC counts as beyond-owner delivery here.
			if accepted and context.relaySender ~= origin and context.relaySender
				and after and after ~= before and after.mask ~= 0 then
				origins[origin] = true
			end
			return accepted
		end
	end
	for _, peer in ipairs(peers) do net:StartPeer(peer) end
	net:Advance(300)
	local visible, relayedPairs = 0, 0
	for index, peer in ipairs(peers) do
		local origins = 0
		for _ in pairs(relayed[index]) do origins = origins + 1 end
		assert(origins >= 1, "every reachable client must install an authenticated relayed location")
		relayedPairs = relayedPairs + origins
		visible = visible + #peer:GetVisiblePlayerLocations("map")
		local mesh, transport = peer:GetMeshNetworkMetrics(), peer:GetTransportMetrics()
		assert(mesh.neighbors <= 8 and mesh.candidates <= 512 and mesh.handshakes <= 3)
		assert((transport.meshPackets or 0) <= 602 and (transport.meshBytes or 0) <= 120400)
	end
	-- Multi-seed offline benchmarks provide substantial margin over these
	-- floors. The old neighbor-centric behavior averaged roughly six visible
	-- origins and fewer than one relayed origin per client in this scenario.
	assert(visible >= #peers * 9, "public coverage must extend beyond an eight-neighbor-sized view: " .. visible)
	assert(relayedPairs >= #peers * 3, "discovery must carry distinct authenticated relay origins: " .. relayedPairs)
end, { offline = true })

QT:RegisterTest("five player quest views and objective updates finish when whisper and channel sends are rejected", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local party, quests = {}, {}
	for id = 1, 30 do quests[id] = { questID = id, title = "A shared quest " .. id .. string.rep(" with a useful title", 3) } end
	for index = 1, 5 do
		local peer = net:AddPeer("Party" .. index .. "-Realm", { group = "questers" })
		net:SetQuestLog(peer, quests)
		peer.db.profile.compareAutoRefresh = false
		party[index] = peer
	end
	for _, peer in ipairs(party) do net:StartPeer(peer) end
	local viewer, responder = party[1], party[2]
	function responder:ReadQuestCompareObjectives(id)
		return { { questId = id, objectiveIndex = 1, text = "Supplies: 1/8", kind = "item", current = 1, required = 8,
			finished = false } }
	end
	local rejected = 0
	net.sendRule = function(packet)
		if packet.route == "WHISPER" or packet.route == "CHANNEL" then rejected = rejected + 1; return 7 end
		return 0
	end
	assert(viewer:RefreshPartyQuestCompare())
	local detail = viewer:AcquirePartyQuestProgress(responder.name, 1, {}, function() end, true)
	local complete = false
	for _ = 1, 90 do
		net:Advance(1)
		complete = detail.hasEntry == true
		for _, member in ipairs(viewer.partyQuestCompareSession.members) do
			if member.state ~= "ready" then complete = false end
		end
		if complete then break end
	end
	assert(complete, "party views must finish without a working whisper or public channel route")
	assert(rejected > 0, "the scenario must include rejected unrelated traffic")
	for _, member in ipairs(viewer.partyQuestCompareSession.members) do
		local count = 0
		for _ in pairs(member.entries) do count = count + 1 end
		Equal(count, 30)
	end
	Equal(detail.objectives[1].current, 1)
	assert(responder:Emit("ANN", { eventType = "QUEST_PROGRESS", senderName = responder.name, classFile = "MAGE",
		questId = "1", text = "Supplies: 3/8", occurredAt = responder.API.GetServerTime(),
		eventFacts = responder:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "item", false, 3, 8) },
		{ { distribution = "PARTY", requiresGroup = true } }))
	net:Advance(5)
	Equal(detail.objectives[1].current, 3)
end, { offline = true })

QT:RegisterTest("single packet group quest replies replay without rebuilding and rejected requests finish promptly", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local a = net:AddPeer("Alice-Realm", { group = "questers" })
	local b = net:AddPeer("Bob-Realm", { group = "questers" })
	local builds, done, dropped, requestId = 0, 0, false, nil
	function b:BuildRevisionedQuestCompareEntries(objectiveQuestId)
		-- Count this request's read, not the independent background summaries.
		if objectiveQuestId == 42 then builds = builds + 1 end
		return {}
	end
	net:StartPeer(a); net:StartPeer(b)
	net.deliveryRule = function(packet, receiver)
		local frame = a:DecodeCommFrame(packet.wire)
		if frame.operation == "QCRS" and frame.requestId == requestId and receiver == a and not dropped then
			Equal(frame.total, 1)
			dropped = true
			return { drop = true }
		end
	end
	local accepted
	accepted, requestId = a:RequestQuestCompare(b.name, { objectiveQuestId = 42, onEntry = function() end,
		onDone = function() done = done + 1 end, onTimeout = function() error("cached reply timed out") end })
	assert(accepted)
	net:Advance(12)
	assert(dropped)
	Equal(done, 1)
	Equal(builds, 1, "same request identity must reuse its single-packet group reply")
	local expired = 0
	net.sendRule = function(packet)
		local frame = a:DecodeCommFrame(packet.wire)
		return frame.operation == "QCMP" and 7 or 0
	end
	local accepted, id = a:RequestQuestCompare(b.name, { onEntry = function() end, onDone = function() end,
		onTimeout = function() expired = expired + 1 end })
	assert(accepted)
	net:Advance(2)
	Equal(expired, 1)
	Equal(a:GetPendingQuestCompare(id), nil)
	Equal(a.communicationState.requests[id], nil)
	net:Advance(181)
	Equal(expired, 1, "native failure and expiry must not notify the viewer twice")
	function b:HandleQuestCompareRequest() return true end
	for _, outcome in ipairs({ "ambiguous", "mixed" }) do
		local notifications = 0
		net.sendRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			if frame.operation ~= "QCMP" then return 0 end
			if outcome == "ambiguous" then return 8 end
			return packet.route == "WHISPER" and 7 or 0
		end
		local routes = a:GetQuestCompareRoutes(b.name, true)
		if outcome == "mixed" then routes[#routes + 1] = { distribution = "WHISPER", target = b.name } end
		local sent, _, _, requestId = a:Request("QCMP", { targetName = b.name }, routes,
			{ onExpire = function() notifications = notifications + 1 end })
		assert(sent)
		net:Advance(2)
		assert(a.communicationState.requests[requestId], "a possibly delivered request must remain correlated")
		Equal(notifications, 0)
		a:CancelCommRequest(requestId)
	end
end, { offline = true })

QT:RegisterTest("network fixture rounds timers to frames and defers nested callbacks", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local peer = net:AddPeer("Timer-Realm")
	local calls = {}
	peer.API.Delay(0.01, function()
		calls[#calls + 1] = net.now
		peer.API.Delay(0, function()
			calls[#calls + 1] = net.now
		end)
	end)
	Equal(#calls, 0)
	net:Step()
	Equal(#calls, 1)
	assert(calls[1] >= 100.1 - 1e-9)
	net:Step()
	Equal(#calls, 2)
	assert(calls[2] - calls[1] >= 0.1 - 1e-9)
	net:SetFPS(60)
	local start = net.now
	peer.API.Delay(0.01, function()
		calls[#calls + 1] = net.now
	end)
	net:Step()
	Equal(#calls, 3)
	assert(calls[3] - start < 0.02)
end)

QT:RegisterTest("network fixture separates accepted packets from asynchronous receipt and loss", function()
	local net = QT:CreateTestNetwork({ latency = 0 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	local received = {}
	function b:OnCommReceived(_, wire)
		received[#received + 1] = wire
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "first", "WHISPER", b.name), 0)
	Equal(net.metrics.accepted, 1)
	Equal(#received, 0, "native acceptance must not call receiver inline")
	net:Step()
	Equal(received[1], "first")
	net.deliveryRule = function()
		return { drop = true }
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "lost", "WHISPER", b.name), 0)
	net:Step()
	Equal(net.metrics.accepted, 2)
	Equal(#received, 1)
	Equal(net.metrics.dropped, 1)
	net.sendRule = function()
		return 3
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "throttled", "WHISPER", b.name), 3)
	Equal(net.metrics.accepted, 2)
	Equal(#net.pending, 0)
end)

QT:RegisterTest("network fixture reorders duplicates and respects channel readiness and audience", function()
	local net = QT:CreateTestNetwork({ fps = 20, joinDelay = 0.1 })
	local a, b, outsider = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm"), net:AddPeer("Other-Realm")
	local received = {}
	function a:OnCommReceived() end
	function b:OnCommReceived(_, wire, route, sender, id, channel)
		received[#received + 1] = { wire, route, sender, id, channel }
	end
	function outsider:OnCommReceived()
		error("unsubscribed peer received channel packet")
	end
	net:Join(a, "TestChannel")
	net:Join(b, "TestChannel")
	Equal(a.API.GetChannelName("TestChannel"), nil)
	local ruleCalls = 0
	net.sendRule = function()
		ruleCalls = ruleCalls + 1
		return 0
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "unjoined", "CHANNEL", 7), false)
	Equal(ruleCalls, 0, "a successful fault policy cannot manufacture a ready channel")
	Equal(#net.pending, 0)
	net:Advance(0.1)
	assert(a.joined.TestChannel and b.joined.TestChannel and a.joined.TestChannel ~= b.joined.TestChannel)
	net.deliveryRule = function(packet)
		return packet.wire == "slow" and { delay = 0.2 } or { delay = 0.05, copies = 2 }
	end
	a.API.SendAddonMessage(a.commPrefix, "slow", "CHANNEL", a.joined.TestChannel)
	a.API.SendAddonMessage(a.commPrefix, "fast", "CHANNEL", a.joined.TestChannel)
	net:Advance(0.2)
	Equal(#received, 3)
	Equal(received[1][1], "fast")
	Equal(received[2][1], "fast")
	Equal(received[3][1], "slow")
	Equal(received[1][4], b.joined.TestChannel, "receiver must see its own local channel ID")
	a.API.SendAddonMessage(a.commPrefix, "slow", "CHANNEL", a.joined.TestChannel)
	net:Leave(b, "TestChannel")
	net:Advance(0.2)
	Equal(#received, 3)
	a.connected = false
	local before = ruleCalls
	Equal(a.API.SendAddonMessage(a.commPrefix, "disconnected", "WHISPER", b.name), false)
	Equal(ruleCalls, before, "a successful fault policy cannot send from a disconnected peer")
	Equal(#net.pending, 0)
end)

QT:RegisterTest("network fixture separates backing realm delivery from overlapping channel directories", function()
	local net = QT:CreateTestNetwork({ directoryDelay = 0.1 })
	local a = net:AddPeer("Alice-Realm", { backingRealm = "A" })
	local b = net:AddPeer("Bob-Realm", { backingRealm = "A" })
	local c = net:AddPeer("Carol-Realm", { backingRealm = "B" })
	local received = {}
	for _, peer in ipairs({ a, b, c }) do
		net:Join(peer, "Directory", true)
		peer.OnCommReceived = function(self, _, wire) received[self.name] = wire end
	end
	Equal(a.API.SendAddonMessage(a.commPrefix, "local", "CHANNEL", a.joined.Directory), 0)
	net:Advance(0.1)
	Equal(received[a.name], "local")
	Equal(received[b.name], "local")
	Equal(received[c.name], nil, "same channel name must not bridge independent backing realms")
	net:SetChannelDirectory(a, "Directory", { b.name })
	net:SetChannelDirectory(b, "Directory", { a.name, c.name })
	for _, peer in ipairs({ a, b, c }) do
		local index = 3 -- General, custom header, then the joined channel.
		assert(index ~= peer.joined.Directory, "fixture must expose the native/display index distinction")
		Equal(peer.API.GetChannelRosterInfo(index, 1), nil)
		peer.API.SetSelectedDisplayChannel(index)
	end
	net:Advance(0.1)
	Equal(a.API.GetChannelRosterInfo(3, 1), b.name)
	Equal(a.API.GetChannelRosterInfo(3, 2), nil, "directory overrides may be incomplete")
	Equal(b.API.GetChannelRosterInfo(3, 2), c.name, "a different directory can introduce an unseen peer")
	Equal(c.API.GetChannelRosterInfo(3, 1), c.name, "default directory stays within its backing realm")
	Equal(a.API.GetChannelRosterInfo(a.joined.Directory, 1), nil, "native send ID is not a roster index")
	Equal(a.API.SendAddonMessage(a.commPrefix, "direct", "WHISPER", c.name), 0)
	net:Advance(0.1)
	Equal(received[c.name], "direct", "cross-realm direct whispers are independent of channel scope")
end)

QT:RegisterTest("network fixture directory fetches retire on suspension leave and replacement", function()
	local net = QT:CreateTestNetwork({ fps = 10, directoryDelay = 0.2 })
	local a = net:AddPeer("Alice-Realm")
	net:Join(a, "Directory", true)
	net:SetChannelDirectory(a, "Directory", { "Old-Realm" })
	a.API.SetSelectedDisplayChannel(3)
	Equal(select(5, a.API.GetChannelDisplayInfo(3)), nil, "selection does not synchronously manufacture a roster")
	net:SetChannelSuspended(a, "Directory", true)
	net:Advance(0.3)
	Equal(a.API.GetNumDisplayChannels(), 2)
	Equal(a.loadedDirectories.Directory, nil, "late load cannot restore a suspended directory")
	Equal(select(4, a.API.GetChannelName("Directory")), true)
	Equal(a.API.SendAddonMessage(a.commPrefix, "suspended", "CHANNEL", a.joined.Directory), 7)
	net:SetChannelSuspended(a, "Directory", false)
	a.API.SetSelectedDisplayChannel(1)
	a.API.SetSelectedDisplayChannel(3)
	net:Leave(a, "Directory")
	net:Join(a, "Directory", true)
	net:Advance(0.3)
	Equal(a.loadedDirectories.Directory, nil, "a fetch belongs to one membership lifetime")
	net:SetChannelDirectory(a, "Directory", false)
	a.API.SetSelectedDisplayChannel(1)
	a.API.SetSelectedDisplayChannel(3)
	net:Advance(0.3)
	Equal(select(5, a.API.GetChannelDisplayInfo(3)), nil, "unreadable differs from an empty roster")
	net:SetChannelDirectory(a, "Directory", {})
	a.API.SetSelectedDisplayChannel(1)
	a.API.SetSelectedDisplayChannel(3)
	net:Advance(0.3)
	Equal(select(5, a.API.GetChannelDisplayInfo(3)), 0)
	Equal(a.API.GetSelectedDisplayChannel(), 3)
	a.channelWindowShown = true
	Equal(a.API.IsChannelWindowShown(), true)
end)

QT:RegisterTest("network fixture whisper reachability is directional and checked again at receipt", function()
	local net = QT:CreateTestNetwork({ latency = 0.2 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	local received = {}
	for _, peer in ipairs({ a, b }) do
		peer.OnCommReceived = function(self, _, wire) received[self.name] = wire end
	end
	net:SetWhisperReachable(a, b, false)
	Equal(a.API.SendAddonMessage(a.commPrefix, "blocked", "WHISPER", b.name), 0)
	Equal(b.API.SendAddonMessage(b.commPrefix, "reply", "WHISPER", a.name), 0)
	net:Advance(0.2)
	Equal(received[a.name], "reply")
	Equal(received[b.name], nil)
	net:SetWhisperReachable(a, b, true)
	a.API.SendAddonMessage(a.commPrefix, "in-flight", "WHISPER", b.name)
	net:SetWhisperReachable(a, b, false)
	net:Advance(0.2)
	Equal(received[b.name], nil, "accepted traffic can lose its link before delivery")
	Equal(net.metrics.dropped, 1)
end)

QT:RegisterTest("network fixture channel acceptance can be refused asynchronously without an echo", function()
	local net = QT:CreateTestNetwork({ fps = 20, latency = 0.1 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	for _, peer in ipairs({ a, b }) do
		net:Join(peer, "Directory", true)
		peer.OnCommReceived = function() error("refused channel packets must not be delivered") end
	end
	local notices = {}
	local observer = net:CreateFrame(a)
	observer:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	observer:SetScript("OnEvent", function(_, event, notice, _, _, channel, _, _, _, id, base)
		notices[#notices + 1] = { event, notice, channel, id, base }
	end)
	net:SetChannelRefusal(a, "Directory", { delay = 0.15, suspend = true })
	Equal(a.API.SendAddonMessage(a.commPrefix, "refused", "CHANNEL", a.joined.Directory), 0)
	Equal(#notices, 0)
	Equal(net.metrics.accepted, 1)
	net:Advance(0.1)
	Equal(#notices, 0)
	net:Advance(0.05)
	Equal(#notices, 1)
	Equal(notices[1][2], "NOT_ALLOWED_IN_CHANNEL")
	Equal(notices[1][3], "Directory")
	Equal(notices[1][4], a.joined.Directory)
	Equal(notices[1][5], "Directory")
	Equal(net.metrics.serverRefused, 1)
	Equal(net.metrics.delivered, 0)
	Equal(a.API.GetNumDisplayChannels(), 2)
	Equal(a.API.SendAddonMessage(a.commPrefix, "now-invalid", "CHANNEL", a.joined.Directory), 7)
	net:Advance(0.2)
	Equal(#notices, 1, "native rejection does not manufacture another server acceptance/refusal")
end)

QT:RegisterTest("network fixture clocks randomness and state are private to each network", function()
	local a, b = QT:CreateTestNetwork({ seed = 91 }), QT:CreateTestNetwork({ seed = 91 })
	local peer = a:AddPeer("Clock-Realm", { clockOffset = -40, serverOffset = 7 })
	local other = b:AddPeer("Clock-Realm")
	for _ = 1, 20 do
		Equal(a:Random(2, 50), b:Random(2, 50))
	end
	Equal(peer.API.GetTime(), 60)
	Equal(peer.API.GetServerTime(), 1800000107)
	peer.db.profile.sharePlayerLocation = false
	Equal(other.db.profile.sharePlayerLocation, true)
	Equal(rawget(peer, "transportState"), nil)
	Equal(peer.transportState, nil, "live addon state cannot be inherited")
	a:Advance(1)
	assert(math.abs(peer.API.GetTime() - 61) < 1e-8)
	Equal(other.API.GetTime(), 100)
end)

QT:RegisterTest("network fixture runs the production coordinator and fences retired frame callbacks", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local peer = net:AddPeer("Runtime-Realm")
	Equal(peer.UpdatePlayerCommunications, QT.UpdatePlayerCommunications)
	Equal(peer.UpdateGeographicComms, QT.UpdateGeographicComms)
	Equal(peer.DrainTransport, QT.DrainTransport)
	net:StartPeer(peer)
	local frame = peer.runtimeCoordinatorFrame
	local stale = frame.scripts.OnUpdate
	assert(type(stale) == "function")
	net:Advance(3)
	assert((peer.apiCalls.map or 0) > 0, "coordinator should acquire actual producer observations")
	local reads = peer.apiCalls.map
	peer:ResetRuntimeCoordinator()
	stale(frame, 1)
	Equal(peer.apiCalls.map, reads, "retired coordinator must reject a captured callback")
	Equal(frame.scripts.OnUpdate, nil)
end)

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network runtime discovers local peers through real producers and asynchronous delivery", function()
	for _, fps in ipairs({ 5, 60 }) do
		local net = QT:CreateTestNetwork({ fps = fps, seed = 9, latency = 0.05, joinDelay = 0.1 })
		local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm", { x = 0.6 })
		net:StartPeer(a)
		net:StartPeer(b)
		Equal(#a:GetVisiblePlayerLocations("map"), 0)
		net:Advance(20)
		local aRows, bRows = a:GetVisiblePlayerLocations("map"), b:GetVisiblePlayerLocations("map")
		Equal(#aRows, 1)
		Equal(#bRows, 1)
		Equal(aRows[1].name, b.name)
		Equal(bRows[1].name, a.name)
		Equal(aRows[1].x, 0.6)
		Equal(bRows[1].x, 0.4)
		assert(net.metrics.accepted > 0 and net.metrics.delivered > 0)
		for _, trace in ipairs(net.trace) do
			if trace.kind == "delivered" then
				assert(trace.at > trace.packet.at, "network receipt must occur after native acceptance")
			end
		end
	end
end, { offline = true })

QT:RegisterTest("network runtime progresses communications each frame while pacing observations", function()
	local net = QT:CreateTestNetwork({ fps = 60 })
	local peer = net:AddPeer("Runtime-Realm")
	local networkTicks, observations = 0, 0
	local update, observe = peer.UpdateCommunicationRuntime, peer.UpdatePlayerCommunications
	function peer:UpdateCommunicationRuntime()
		networkTicks = networkTicks + 1
		return update(self)
	end
	function peer:UpdatePlayerCommunications()
		observations = observations + 1
		return observe(self)
	end
	net:StartPeer(peer)
	for _ = 1, 30 do
		net:Step()
	end
	Equal(networkTicks, 30)
	Equal(observations, 2)
	local oldFrame = peer.runtimeCoordinatorFrame
	local oldUpdate = oldFrame.scripts.OnUpdate
	peer:ResetRuntimeCoordinator()
	oldUpdate(oldFrame, 1)
	Equal(networkTicks, 30)
end)

QT:RegisterTest("network v3 rejects legacy prefixes and legacy bodies without side effects", function()
	local net = QT:CreateTestNetwork()
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	net:StartPeer(a)
	net:StartPeer(b)
	net:Join(a, a.announcementChannelName, true)
	local announcements = 0
	function a:HandleAnnouncementEvent()
		announcements = announcements + 1
	end
	local old = "ANN|3,QUEST_PROGRESS,,MAGE,Bob-Realm,Legacy progress,,,,,,,,,,,"
	net:Inject(a, "QuestTogether", old, "CHANNEL", b.name, { channel = a.announcementChannelName })
	net:Inject(a, "QuestTogether2", old, "CHANNEL", b.name, { channel = a.announcementChannelName })
	net:Advance(0.1)
	Equal(announcements, 0)
	Equal(a:IsKnownQTPlayer(b.name), false)
end)

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network v3 correlates and repairs a typed response through the complete runtime", function()
	for _, fps in ipairs({ 5, 60 }) do
		local net = QT:CreateTestNetwork({ fps = fps, seed = 32, latency = 0.05 })
		local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
		net:StartPeer(a)
		net:StartPeer(b)
		local calls, initialPartTwo = 0, 0
		function b:HandlePartyVisualRosterRequest(request, sender)
			local members = {}
			for index = 1, 30 do
				members[index] = { name = "Member" .. index .. "-Realm", classFile = "MAGE" }
			end
			return self:Respond(
				"QPGM",
				{ requestId = request.requestId, revision = "fixture", members = members },
				{ { distribution = "WHISPER", target = sender } },
				{ expires = self.API.GetTime() + 120 }
			)
		end
		net.deliveryRule = function(packet)
			local frame = a:DecodeCommFrame(packet.wire)
			assert(frame, "all runtime producers must use the versioned protocol")
			if frame.operation == "QPGM" and frame.part == 2 then
				initialPartTwo = initialPartTwo + 1
				if initialPartTwo == 1 then
					return { drop = true }
				end
			end
		end
		local accepted = a:Request("QPGR", { targetName = b.name }, { { distribution = "WHISPER", target = b.name } }, {
			expires = a.API.GetTime() + 120,
			onResponse = function(record, sender)
				Equal(sender, b.name)
				Equal(#record.members, 30)
				calls = calls + 1
				a:CancelCommRequest(record.requestId)
				return true
			end,
		})
		assert(accepted)
		net:Advance(45)
		Equal(calls, 1)
		Equal(initialPartTwo, 2)
		Equal(b:GetCommTransferMetrics().outgoing, 0)
		for _, peer in ipairs({ a, b }) do
			local bytes = 0
			for _, packet in ipairs(peer.sent) do
				bytes = bytes + #packet.wire + #packet.prefix + 40
			end
			assert(bytes <= 800 * 45 + 1600, "native byte budget must include every runtime producer")
			assert(#peer.sent <= 4 * 45 + 4, "native packet budget must include every runtime producer")
		end
	end
end, { offline = true })

QT:RegisterTest("network v3 retires throttled work at world departure and resumes with fresh traffic", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	net:StartPeer(a)
	net:StartPeer(b)
	local blocked, completions = false, {}
	net.sendRule = function(_, _, peer)
		if peer == a and not blocked then
			blocked = true
			return 3
		end
		return 0
	end
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }, {
		onComplete = function(ok, reason)
			completions[#completions + 1] = { ok, reason }
		end,
	}))
	net:Advance(0.3)
	assert(blocked)
	Equal(#a.sent, 0)
	Equal(#completions, 0, "a native throttle is not completion")
	a:EndCommunicationSession()
	Equal(#completions, 1)
	Equal(completions[1][1], false)
	local attempts = #a.attempts
	net:Advance(2)
	Equal(#a.attempts, attempts, "active frame callbacks cannot send a departed generation")
	a:ResumeCommunicationSession()
	assert(a:Emit("QTPR", { active = true }, { { distribution = "WHISPER", target = b.name } }))
	net:Advance(2)
	assert(#a.sent > 0)
	Equal(#completions, 1)
	assert(b:IsKnownQTPlayer(a.name))
end)

QT:RegisterTest("network v3 queued coordinates cannot cross a privacy change", function()
	local net = QT:CreateTestNetwork({ fps = 5 })
	local a, b = net:AddPeer("Alice-Realm"), net:AddPeer("Bob-Realm")
	net:StartPeer(a)
	net:StartPeer(b)
	local completed = {}
	local admitted, _, context = a:Emit("STATE", {
		records = {
			{ topic = "QTPR", data = { active = true }, sampledAt = a.API.GetServerTime() },
			{
				topic = "LOC",
				data = { session = "privacy-test", sequence = 1, mask = 3, mapID = 12, x = 0.9, y = 0.8 },
				sampledAt = a.API.GetServerTime(),
			},
		},
	}, { { distribution = "WHISPER", target = b.name } }, {
		onComplete = function(ok, reason)
			completed[#completed + 1] = { ok, reason }
		end,
	})
	assert(admitted)
	a.db.profile.sharePlayerLocation = false
	net:Advance(20)
	Equal(#completed, 1)
	Equal(completed[1][1], false)
	Equal(#b:GetVisiblePlayerLocations("map"), 0)
	for _, packet in ipairs(a.sent) do
		local frame = assert(a:DecodeCommFrame(packet.wire))
		assert(frame.session ~= context.session or frame.messageId ~= context.messageId,
			"the revoked coordinate publication reached native send")
	end
end)

QT:RegisterTest("network v3 queued party focus cannot follow the sender into another group", function()
	local net = QT:CreateTestNetwork({ fps = 20 })
	local a = net:AddPeer("Alice-Realm", { group = "old" })
	local b = net:AddPeer("Bob-Realm", { group = "old" })
	local c = net:AddPeer("Carol-Realm", { group = "new" })
	for _, peer in ipairs({ a, b, c }) do
		net:StartPeer(peer)
	end
	local completions = {}
	local accepted, _, context = a:Emit("QTN2", { session = "old-focus", sequence = 1, questID = 123 }, {
		{ distribution = "PARTY" },
	}, {
		onComplete = function(ok, reason)
			completions[#completions + 1] = { ok, reason }
		end,
	})
	assert(accepted)
	net:SetGroup(a, "new")
	net:Advance(2)
	Equal(#completions, 1)
	Equal(completions[1][1], false)
	for _, packet in ipairs(a.sent) do
		local frame = assert(a:DecodeCommFrame(packet.wire))
		assert(
			frame.session ~= context.session or frame.messageId ~= context.messageId,
			"old group focus reached native send"
		)
	end
end)

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network v3 completes party logs and a diagnostic report while movement remains active", function()
	for _, fps in ipairs({ 5, 60 }) do
		local net = QT:CreateTestNetwork({ fps = fps, seed = 71 })
		local party = {}
		for index = 1, 5 do
			local peer = net:AddPeer("Player" .. index .. "-Realm", { group = "party" })
			local quests = {}
			for quest = 1, 30 do
				quests[quest] = {
					questID = index * 1000 + quest,
					title = "Quest " .. quest .. ": " .. string.rep("A meaningful quest title ", 4),
					isComplete = quest % 3 == 0,
				}
			end
			net:SetQuestLog(peer, quests)
			peer.db.profile.compareAutoRefresh = false
			party[index] = peer
			net:StartPeer(peer)
		end
		local viewer, responder = party[1], party[2]
		viewer.isLocalDeveloper = true
		-- Cryptographic correctness has its own real-key suite. This private
		-- engine seam still yields so authentication runs through the runtime.
		function viewer:SignDeveloperRequest()
			return string.rep("s", 64)
		end
		responder.developerPublicKeyHex = string.rep("0", 64)
		responder.Ed25519 = setmetatable({
			NewVerification = function()
				return coroutine.create(function()
					for _ = 1, 17 do
						coroutine.yield()
					end
					return true
				end)
			end,
		}, { __index = QT.Ed25519 }) -- Mesh hashing remains real in this mixed-load test.
		local reports, snapshots, pongs = {}, 0, 0
		local report = string.rep("Diagnostic fixture state.\n", 1200)
		function responder:BuildDeveloperDiagnosticSnapshot()
			snapshots = snapshots + 1
			return report
		end
		function viewer:GetDebugController()
			return {
				ShowReport = function(_, text, sender)
					reports[#reports + 1] = { text = text, sender = sender, at = net.now }
				end,
			}
		end
		function viewer:PrintPingResponse()
			pongs = pongs + 1
		end
		assert(viewer:RefreshPartyQuestCompare())
		assert(viewer:SendPingRequest(responder.name, true))
		local started, logsAt = net.now, nil
		for tick = 1, 240 do
			responder.position.x = 0.2 + tick % 30 / 100
			net:Advance(1)
			local complete = true
			for _, member in ipairs(viewer.partyQuestCompareSession.members) do
				if member.state ~= "ready" then
					complete = false
				end
			end
			if complete and not logsAt then
				logsAt = net.now
			end
			if complete and #reports == 1 then
				break
			end
		end
		local statuses = {}
		for _, member in ipairs(viewer.partyQuestCompareSession.members) do
			statuses[#statuses + 1] = member.name .. ":" .. member.state
		end
		assert(
			logsAt and logsAt - started < 90,
			"five-player PQL must make progress beside diagnostics: "
				.. table.concat(statuses, ",")
				.. " completion="
				.. tostring(logsAt and logsAt - started)
		)
		Equal(#reports, 1, "diagnostic report must finish at " .. fps .. " FPS; snapshots=" .. snapshots
			.. " pongs=" .. pongs .. " responderOutgoing=" .. responder:GetCommTransferMetrics().outgoing
			.. " viewerIncoming=" .. viewer:GetCommTransferMetrics().incoming)
		Equal(reports[1].text, report)
		Equal(reports[1].sender, responder.name)
		Equal(snapshots, 1, "diagnostic snapshot must be sampled once")
		Equal(pongs, 1, "diagnostic pong must complete")
		for _, member in ipairs(viewer.partyQuestCompareSession.members) do
			local count = 0
			for _ in pairs(member.entries) do
				count = count + 1
			end
			Equal(count, 30)
		end
		local location = viewer:GetPlayerLocationState().peers[responder.name]
		-- Both timestamps use the receiver's monotonic clock. A delayed old
		-- publication must not pass simply because it was received recently.
		local sourceAge = location and viewer.API.GetTime() - location.sampledAt
		local receiptAge = location and viewer.API.GetTime() - location.receivedAt
		assert(
			location and sourceAge >= 0 and sourceAge < 10,
			"bulk traffic must not starve moving peers: fps=" .. fps .. " sourceAge="
				.. tostring(sourceAge) .. " receiptAge=" .. tostring(receiptAge)
				.. " elapsed=" .. tostring(net.now - started)
				.. " responderQueue=" .. responder:GetTransportMetrics().queuedPackets
				.. " responderPartyPending=" .. tostring(responder.geographicCommsState.routes.PARTY and responder.geographicCommsState.routes.PARTY.pending ~= nil)
		)
		for _, peer in ipairs(party) do
			local bytes = 0
			for _, packet in ipairs(peer.sent) do
				bytes = bytes + #packet.wire + #packet.prefix + 40
			end
			assert(bytes <= 800 * (net.now - started) + 1600)
			assert(#peer.sent <= 4 * (net.now - started) + 4)
		end
	end
end, { offline = true })

-- Full multi-peer, multi-frame network simulations run offline.
QT:RegisterTest("network v3 accepts a late correlated pong without reviving its old coordinates", function()
	local net = QT:CreateTestNetwork({ fps = 5 })
	local a, b = net:AddPeer("Developer-Realm"), net:AddPeer("Friend-Realm")
	a.isLocalDeveloper = true
	function a:SignDeveloperRequest()
		return string.rep("s", 64)
	end
	local received = {}
	function a:PrintPingResponse(record)
		received[#received + 1] = record
	end
	b.db.profile.sharePlayerLocation = false
	b.db.profile.shareDeveloperDiagnostics = false
	net:StartPeer(a)
	net:StartPeer(b)
	local accepted, requestId = a:SendPingRequest(b.name, false)
	assert(accepted)
	local sampledAt = b.API.GetServerTime()
	net:Advance(605)
	Equal(#received, 0)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	local record = {
		requestId = requestId,
		senderName = b.name,
		sampledAt = sampledAt,
		mapID = "12",
		coordX = "42",
		coordY = "63",
		locationShared = true,
		addonVersion = "7.0.0",
	}
	assert(b:Respond("PONG", record, { { distribution = "WHISPER", target = a.name } }))
	net:Advance(3)
	Equal(#received, 1)
	Equal(received[1].requestId, requestId)
	Equal(#a:GetVisiblePlayerLocations("map"), 0, "late reply receipt is not a new location sample")
	record.requestId = "unknown-ping"
	record.sampledAt = b.API.GetServerTime()
	assert(b:Respond("PONG", record, { { distribution = "WHISPER", target = a.name } }))
	net:Advance(3)
	Equal(#received, 1, "late acceptance still requires an owned request identity")
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
end, { offline = true })

QT:RegisterTest("native announcement receipt updates subscribed quest progress before chat and bubble presentation", function()
	local net = QT:CreateTestNetwork({fps=20})
	local a=net:AddPeer("Alice-Realm",{group="questers"})
	local b=net:AddPeer("Bob-Realm",{group="questers"})
	for _, peer in ipairs({ a, b }) do net:SetQuestLog(peer, { { questID = 42, title = "Bandanas" } }) end
	local progress = 1
	function b:ReadQuestCompareObjectives(id)
		return { { questId = id, objectiveIndex = 1, text = "Bandanas: " .. progress .. "/8", kind = "item",
			current = progress, required = 8, finished = false } }
	end
	net:StartPeer(a); net:StartPeer(b)
	local updates, presented = 0, 0
	function a:QueuePartyQuestCompareRender() updates=updates+1 end
	assert(a:RefreshPartyQuestCompare(nil, nil, true))
	net:Advance(5)
	a:TogglePartyQuestObjectives(42)
	local member = a.partyQuestCompareSession.byName[b.name]
	local record=member.objectiveDetails[42]
	Equal(record.objectives[1].current, 1)
	function a:HandleAnnouncementEvent(event)
		-- This is where chat option checks, title waits and bubbles start.
		Equal(record.objectives[1].current,7)
		presented=presented+1
	end
	local data={eventType="QUEST_PROGRESS",senderName=b.name,classFile="MAGE",questId="42",
		text="Bandanas: 7/8",occurredAt=100,eventFacts=b:BuildAnnouncementFacts("QUEST_PROGRESS",1,"item",false,7,8)}
	progress = 7
	assert(b:Emit("ANN",data,{{distribution="PARTY",requiresGroup=true}}))
	net:Advance(5)
	Equal(presented,1)
	assert(updates>=1)
	Equal(record.objectives[1].current,7)
	a:EndCommsWorldSession()
	Equal(member.objectiveDetails[42],nil)
	Equal(a.partyQuestProgress,nil)
	a:ResumeCommsWorldSession()
	local current = a.partyQuestCompareSession.byName[b.name]
	assert(current ~= member, "world resume must bind views to the new party lifetime")
	net:Advance(10)
	assert(current.objectiveDetails[42] and current.objectiveDetails[42] ~= record)
	Equal(current.objectiveDetails[42].state, "ready")
	Equal(current.objectiveDetails[42].objectives[1].current, 7)
end)

-- This is an offline load contract, not a promise of a globally complete peer
-- graph. Every client still has independent discovery, consent and budgets.
QT:RegisterTest("mesh two hundred simultaneous clients retain bounded progressive discovery", function()
	local net = QT:CreateTestNetwork({ fps = 5, seed = 1537, latency = 0.08, joinDelay = 0.3, directoryDelay = 0.5 })
	local peers, firstLocation = {}, {}
	for index = 1, 200 do
		peers[index] = net:AddPeer(string.format("Crowd%03d-Realm", index), {
			backingRealm = "Backing" .. (index % 4), mapID = 12,
			x = 0.05 + (index % 20) / 25, y = 0.05 + math.floor((index - 1) / 20) / 15,
		})
	end
	for index, peer in ipairs(peers) do
		local names = { peer.name }
		-- Overlapping directory fragments connect hidden backing populations;
		-- nobody is handed the complete directory or trusted peer records.
		for _, offset in ipairs({ -3, -2, -1, 1, 2, 3, 17, 53 }) do
			names[#names + 1] = peers[(index + offset - 1) % #peers + 1].name
		end
		net:SetChannelDirectory(peer, peer.announcementChannelName, names)
		net:SetChannelDirectory(peer, "QuestTogether3Z12", names)
		net:StartPeer(peer)
	end
	local maxQueue, maxRetained, connected = 0, 0, 0
	for second = 1, 60 do
		if second % 5 == 0 then
			for index = 1, 5 do peers[index].position.x = 0.2 + second / 1000 + index / 100 end
		end
		net:Advance(1)
		for _, peer in ipairs(peers) do
			local transport, mesh, publications = peer:GetTransportMetrics(), peer:GetMeshNetworkMetrics(), peer:GetMeshPublicationMetrics()
			assert(transport.queuedPackets <= 96 and (transport.highWater or 0) <= 96)
			assert((transport.meshBytes or 0) <= second * 400 + 400)
			assert((transport.meshPackets or 0) <= second * 2 + 2)
			assert(mesh.neighbors <= 8 and mesh.candidates <= 512 and mesh.handshakes <= 3 and mesh.interests <= 32)
			assert(publications.retainedBytes <= 131072, "publication memory must remain bounded under simultaneous discovery")
			maxQueue = math.max(maxQueue, transport.highWater or 0)
			maxRetained = math.max(maxRetained, publications.retainedBytes)
			if not firstLocation[peer.name] and #peer:GetVisiblePlayerLocations("map") > 0 then firstLocation[peer.name] = second end
		end
	end
	local latencies = {}
	for _, peer in ipairs(peers) do
		if peer:GetMeshNetworkMetrics().neighbors > 0 then connected = connected + 1 end
		if firstLocation[peer.name] then latencies[#latencies + 1] = firstLocation[peer.name] end
		for _, packet in ipairs(peer.sent) do assert(packet.route == "WHISPER", "public discovery cannot send channel data") end
	end
	table.sort(latencies)
	Equal(connected, #peers, "every reachable client must make bootstrap progress in this lossless fixture")
	assert(#latencies > 0, "public state must progress beside connection and interest traffic")

end, { offline = true })
