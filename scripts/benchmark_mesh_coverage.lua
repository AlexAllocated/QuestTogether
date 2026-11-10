-- Offline coverage benchmark using actual coordinators, codecs and source
-- verification. UI/native adapters are isolated by scripts/test.lua. Host CPU
-- timings include the simulated network and are not live-client frame timings.
-- Run from the repository root, for example:
-- lua scripts/benchmark_mesh_coverage.lua --peers=20,50,200 --seeds=1537,42,2026 --seconds=300 --topology=overlap --party
-- JSON Lines go to stdout; bootstrap messages go to stderr. No production
-- constants are modified. --root can select an archived source tree while
-- retaining this runner's bootstrap support.
-- Seeds control the fixture's random choices; Lua table traversal and host
-- allocation can still alter exact scheduling. Compare multiple runs/seeds.
local options = {
	peers = { 20 },
	seeds = { 1537 },
	seconds = 120,
	fps = 5,
	topology = "overlap",
	root = ".",
	party = false,
}
local function Integers(text)
	local result = {}
	for value in text:gmatch("[^,]+") do
		local number = tonumber(value)
		assert(number and number >= 1 and number == math.floor(number), "expected positive integers: " .. text)
		result[#result + 1] = number
	end
	assert(#result > 0, "empty integer list")
	return result
end
for _, argument in ipairs(arg) do
	local key, value = argument:match("^%-%-([%w_-]+)=(.+)$")
	if argument == "--help" then
		print(
			"lua scripts/benchmark_mesh_coverage.lua --peers=20,50,200 --seeds=1537,42,2026 --seconds=300 --topology=full|overlap|sparse --fps=5 [--party] [--root=source-tree]"
		)
		return
	elseif argument == "--party" then
		options.party = true
	elseif key == "peers" or key == "seeds" then
		options[key] = Integers(value)
	elseif key == "seconds" or key == "fps" then
		options[key] = Integers(value)[1]
	elseif key == "topology" or key == "root" then
		options[key] = value
	else
		error("unknown argument: " .. argument)
	end
end
assert(({ full = true, overlap = true, sparse = true })[options.topology], "unknown directory topology")
assert(options.seconds <= 3600 and options.fps <= 60, "limit the benchmark to one hour and 60 FPS")
for _, size in ipairs(options.peers) do
	assert(size >= (options.party and 5 or 2) and size <= 512, "peer count must fit the scenario and candidate limit")
end
for _, seed in ipairs(options.seeds) do
	assert(seed < 2147483647, "seed exceeds the fixture generator range")
end

local originalArg, originalPrint = arg, print
arg = { options.root, "bootstrap" }
print = function(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring(select(index, ...))
	end
	io.stderr:write(table.concat(parts, "\t"), "\n")
end
local ok, QT, CheckIsolation = pcall(function()
	return assert(loadfile("scripts/test.lua"))()
end)
arg, print = originalArg, originalPrint
assert(ok, QT)
assert(type(CheckIsolation) == "function", "offline runner must support bootstrap mode")

local function Count(values)
	local count = 0
	for _ in pairs(values or {}) do
		count = count + 1
	end
	return count
end
local function Stats(values)
	table.sort(values)
	local total = 0
	for _, value in ipairs(values) do
		total = total + value
	end
	return {
		min = values[1] or 0,
		median = values[math.ceil(#values / 2)] or 0,
		mean = #values > 0 and total / #values or 0,
		max = values[#values] or 0,
	}
end
local function JSON(value)
	if type(value) == "number" then
		assert(value == value and value ~= math.huge and value ~= -math.huge)
		return string.format("%.6g", value)
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "string" then
		return '"'
			.. value:gsub('[%z\1-\31\\"]', function(character)
				return string.format("\\u%04x", string.byte(character))
			end)
			.. '"'
	end
	assert(type(value) == "table", "unsupported report value")
	local keys, result = {}, {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		result[#result + 1] = JSON(key) .. ":" .. JSON(value[key])
	end
	return "{" .. table.concat(result, ",") .. "}"
end
local function Write(value)
	io.stdout:write(JSON(value), "\n")
	io.stdout:flush()
end

local function Scenario(size, seed)
	collectgarbage("collect")
	local heapStart, cpuStart = collectgarbage("count"), os.clock()
	local net =
		QT:CreateTestNetwork({ fps = options.fps, seed = seed, latency = 0.08, joinDelay = 0.3, directoryDelay = 0.5 })
	local peers, observations = {}, {}
	local party = { firstReadyAt = nil, sent = {}, seen = {}, latencies = {}, emitted = 0 }
	local nativeBytes, operations, operationBytes, publicationContexts = {}, {}, {}, {}
	local started = net.now
	local maxSimulationFrameCPU = 0
	local step = net.Step
	function net:Step(delta)
		local before = os.clock()
		step(self, delta)
		maxSimulationFrameCPU = math.max(maxSimulationFrameCPU, (os.clock() - before) * 1000)
	end
	-- Count complete encoded native cost using the same prefix/overhead charge
	-- as Transport. This observer changes neither acceptance nor delivery.
	net.sendRule = function(packet)
		assert(packet.route ~= "CHANNEL", "directory channels must never carry addon traffic")
		local cost = #packet.wire + #packet.prefix + 40
		nativeBytes[packet.sender] = (nativeBytes[packet.sender] or 0) + cost
		local operation = packet.wire:match("^3|([^|]+)|") or "unknown"
		operations[operation] = (operations[operation] or 0) + 1
		operationBytes[operation] = (operationBytes[operation] or 0) + cost
		if operation == "MPUB" then
			-- Repeated means a new transfer of an identical digest over the
			-- same directed link. Existing destination/lease metadata may still
			-- require that transfer; this measures aggregation opportunity, not
			-- proof that the current protocol can safely discard every repeat.
			local session, id = packet.wire:match("^3|MPUB|([^|]+)|([^|]+)|")
			local sender = publicationContexts[packet.sender]
			local entry = sender and sender[session .. ":" .. id]
			assert(entry, "native publication must retain its benchmark digest context")
			local observed, target = entry.observed, packet.target
			local link = entry.digest .. ":" .. target
			local transfer = entry.transfers[target]
			if not transfer then
				transfer = { repeated = observed.nativeDigestLinks[link] == true }
				entry.transfers[target] = transfer
				observed.nativeDigestLinks[link] = true
				observed.nativePublicationTransfers = observed.nativePublicationTransfers + 1
				if transfer.repeated then
					observed.nativeRepeatedTransfers = observed.nativeRepeatedTransfers + 1
				end
			end
			if transfer.repeated then
				observed.nativeRepeatedBytes = observed.nativeRepeatedBytes + cost
			end
		end
		return 0
	end
	for index = 1, size do
		local number = options.topology == "sparse" and index * 7 or index
		local peer = net:AddPeer(string.format("Crowd%03d-Realm", number), {
			backingRealm = options.topology == "overlap" and "Backing" .. index % 4 or "Realm",
			group = options.party and index <= 5 and "benchmark-party" or nil,
			mapID = 12,
			x = 0.05 + (index % 20) / 25,
			y = 0.05 + math.floor((index - 1) / 20) / math.max(30, math.ceil(size / 20) + 1),
		})
		peers[index] = peer
		-- Chat/bubble drawing is a presentation boundary. Party progress is
		-- installed by DispatchOperation before this callback, as in the live UI.
		peer.HandleAnnouncementEvent = function() end
		local observed = {
			locations = {},
			relayedLocations = {},
			directLocations = {},
			verifiedOrigins = {},
			relayedOrigins = {},
			firstLocationAt = nil,
			authRequests = 0,
			authRequestedItems = 0,
			authResponses = 0,
			authConfirmedItems = 0,
			authExpiredRequests = 0,
			authTimeoutRequests = 0,
			authCancelledRequests = 0,
			authOtherFailures = 0,
			runtimeCPU = 0,
			runtimeCPUMax = 0,
			runtimeCalls = 0,
			replayFencesMax = 0,
			cachedReplayBlockedMax = 0,
			nativeDigestLinks = {},
			nativePublicationTransfers = 0,
			nativeRepeatedTransfers = 0,
			nativeRepeatedBytes = 0,
			interestCompleted = 0,
			interestExpired = 0,
			interestOtherFailures = 0,
			visiblePrevious = {},
			visibleEver = {},
			visibleDisappearances = 0,
			visibleReappearances = 0,
			steadyVisibleSum = 0,
			steadyVisibleSamples = 0,
			steadyVisibleMin = size,
			steadyVisibleMax = 0,
		}
		observations[index] = observed
		publicationContexts[peer.name] = {}
		local submit = peer.SubmitCommunication
		function peer:SubmitCommunication(operation, data, routes, descriptor)
			if operation == "MINT" then
				local original, copy = descriptor or {}, {}
				for key, value in pairs(original) do
					copy[key] = value
				end
				copy.onComplete = function(sent, reason, ...)
					local field = sent and "interestCompleted"
						or reason == "expired" and "interestExpired"
						or "interestOtherFailures"
					observed[field] = observed[field] + 1
					if original.onComplete then
						return original.onComplete(sent, reason, ...)
					end
				end
				descriptor = copy
			end
			local accepted, reason, context = submit(self, operation, data, routes, descriptor)
			if accepted and operation == "MPUB" then
				local key = context.session .. ":" .. context.messageId
				local contexts = publicationContexts[self.name]
				contexts[key] = contexts[key] or { digest = data.digest, transfers = {}, observed = observed }
			end
			return accepted, reason, context
		end
		-- Time a single peer's actual periodic callback separately from the
		-- complete network step. Do not install a synthetic profiling API: that
		-- would change the hash scheduler's time-based yielding in this fixture.
		local createRuntimeFrame = peer.CreateRuntimeCoordinatorFrame
		function peer:CreateRuntimeCoordinatorFrame()
			local frame = createRuntimeFrame(self)
			local setScript = frame.SetScript
			function frame:SetScript(script, callback)
				if script == "OnUpdate" and callback then
					local run = callback
					callback = function(...)
						local before = os.clock()
						run(...)
						local elapsed = (os.clock() - before) * 1000
						observed.runtimeCPU = observed.runtimeCPU + elapsed
						observed.runtimeCPUMax = math.max(observed.runtimeCPUMax, elapsed)
						observed.runtimeCalls = observed.runtimeCalls + 1
					end
				end
				return setScript(self, script, callback)
			end
			return frame
		end
		local request = peer.Request
		function peer:Request(operation, data, routes, descriptor)
			if operation == "MAUTH" then
				observed.authRequests = observed.authRequests + 1
				observed.authRequestedItems = observed.authRequestedItems + #data.items
				local respond, expire = descriptor.onResponse, descriptor.onExpire
				descriptor.onResponse = function(...)
					local before = self:GetMeshPublicationMetrics().verified or 0
					local accepted = respond(...)
					observed.authResponses = observed.authResponses + 1
					observed.authConfirmedItems = observed.authConfirmedItems
						+ (self:GetMeshPublicationMetrics().verified or 0)
						- before
					return accepted
				end
				descriptor.onExpire = function(reason, ...)
					observed.authExpiredRequests = observed.authExpiredRequests + 1
					local field = reason == "expired" and "authTimeoutRequests"
						or reason == "cancelled" and "authCancelledRequests"
						or "authOtherFailures"
					observed[field] = observed[field] + 1
					return expire(reason, ...)
				end
			end
			return request(self, operation, data, routes, descriptor)
		end
		-- Observe the authenticated dispatch boundary. A non-neighbor location
		-- is not sufficient evidence of relaying: it may be a former neighbor.
		-- Count a relayed location only when another native sender carried it
		-- AND the real domain handler installed a new location record.
		local dispatch = peer.DispatchVerifiedMeshRecord
		function peer:DispatchVerifiedMeshRecord(frame, data, origin, context)
			local before = self:GetPlayerLocationState().peers[origin]
			local accepted = dispatch(self, frame, data, origin, context)
			local after = self:GetPlayerLocationState().peers[origin]
			if accepted then
				observed.verifiedOrigins[origin] = true
				local relayed = context.relaySender and context.relaySender ~= origin
				if relayed then
					observed.relayedOrigins[origin] = true
				end
				if after and after ~= before and after.mask ~= 0 then
					observed.locations[origin] = true
					observed[relayed and "relayedLocations" or "directLocations"][origin] = true
					observed.firstLocationAt = observed.firstLocationAt or net.now - started
				end
			end
			return accepted
		end
		if options.party and index <= 5 then
			local quests = {}
			for id = 1, 30 do
				quests[id] =
					{ questID = id, title = "Quest " .. id .. ": " .. string.rep("A meaningful quest title ", 4) }
			end
			net:SetQuestLog(peer, quests)
			peer.benchmarkProgress = 0
			function peer:ReadQuestCompareObjectives(id)
				return {
					{
						questId = id,
						objectiveIndex = 1,
						text = "Supplies: " .. self.benchmarkProgress .. "/1000",
						kind = "item",
						current = self.benchmarkProgress,
						required = 1000,
						finished = false,
					},
				}
			end
		end
	end
	for index, peer in ipairs(peers) do
		if options.topology ~= "full" then
			local names = {}
			if options.topology == "sparse" then
				for candidate = 1, size * 7 do
					names[#names + 1] = string.format("Crowd%03d-Realm", candidate)
				end
			else
				names[1] = peer.name
				for _, offset in ipairs({ -3, -2, -1, 1, 2, 3, 17, 53 }) do
					names[#names + 1] = peers[(index + offset - 1) % size + 1].name
				end
			end
			net:SetChannelDirectory(peer, peer.announcementChannelName, names)
			net:SetChannelDirectory(peer, "QuestTogether3Z12", names)
		end
		net:StartPeer(peer)
	end
	if options.party then
		assert(peers[1]:RefreshPartyQuestCompare())
		party.detail = peers[1]:AcquirePartyQuestProgress(peers[2].name, 1, {}, function() end, true)
	end
	local function Sample(second)
		local policy = peers[1]:GetTransportMetrics()
		local values = {}
		local function Add(key, value)
			values[key] = values[key] or {}
			values[key][#values[key] + 1] = value
		end
		for index, peer in ipairs(peers) do
			local mesh, publications, transport =
				peer:GetMeshNetworkMetrics(), peer:GetMeshPublicationMetrics(), peer:GetTransportMetrics()
			local observed = observations[index]
			Add("visible_locations", #peer:GetVisiblePlayerLocations("map"))
			Add("accepted_location_origins", Count(observed.locations))
			Add("relayed_location_origins", Count(observed.relayedLocations))
			Add("direct_location_origins", Count(observed.directLocations))
			Add("verified_origins", Count(observed.verifiedOrigins))
			Add("relayed_origins", Count(observed.relayedOrigins))
			Add("auth_request_attempts", observed.authRequests)
			Add("auth_requested_item_attempts", observed.authRequestedItems)
			Add("auth_responses", observed.authResponses)
			Add("auth_confirmed_items", observed.authConfirmedItems)
			Add("auth_expired_or_rejected_requests", observed.authExpiredRequests)
			Add("auth_timed_out_requests", observed.authTimeoutRequests)
			Add("auth_cancelled_requests", observed.authCancelledRequests)
			Add("auth_other_failed_requests", observed.authOtherFailures)
			if observed.firstLocationAt then
				Add("first_location_seconds", observed.firstLocationAt)
			end
			Add("clients_with_location", observed.firstLocationAt and 1 or 0)
			Add("neighbors", mesh.neighbors)
			Add("candidates", mesh.candidates)
			Add("active_interests", mesh.interests)
			Add("interest_audiences", mesh.interestAudiences or 0)
			Add("local_interest_routes", mesh.localRoutes or 0)
			Add("local_interests", mesh.localInterests or 0)
			Add("interest_forwards", mesh.interestForwards or 0)
			Add("interests_aggregated", mesh.interestsAggregated or 0)
			Add("interest_retries", mesh.interestRetries or 0)
			Add("interest_capacity_drops", mesh.interestCapacity or 0)
			Add("interest_sends_completed", observed.interestCompleted)
			Add("interest_sends_expired", observed.interestExpired)
			Add("interest_sends_other_failures", observed.interestOtherFailures)
			Add("handshake_timeouts", mesh.handshakeTimeouts or 0)
			Add("handshake_busy", mesh.handshakeBusy or 0)
			Add("cached_state_replays", publications.cachedStateReplays or 0)
			Add("replay_delivery_reused", publications.replayDeliveryReused or 0)
			Add("replay_retries", publications.replayRetries or 0)
			Add("replay_fences", publications.replayFences or 0)
			Add("replay_fences_high_water", observed.replayFencesMax)
			Add("replay_fence_capacity_fallbacks", publications.replayFenceCapacity or 0)
			Add("cached_replay_blocked_seconds", publications.cachedReplayBlockedFor or 0)
			Add("cached_replay_blocked_max_seconds", observed.cachedReplayBlockedMax)
			Add("runtime_callback_cpu_max_ms", observed.runtimeCPUMax)
			Add(
				"runtime_callback_cpu_mean_ms",
				observed.runtimeCalls > 0 and observed.runtimeCPU / observed.runtimeCalls or 0
			)
			Add("queued_packets", transport.queuedPackets)
			Add("queue_age_seconds", transport.oldestAge)
			Add("mesh_packets", transport.meshPackets or 0)
			Add("mesh_bytes", transport.meshBytes or 0)
			Add("native_packets", #peer.attempts)
			Add("native_bytes", nativeBytes[peer.name] or 0)
			Add("publication_native_transfers", observed.nativePublicationTransfers)
			Add("publication_native_unique_digest_links", Count(observed.nativeDigestLinks))
			Add("publication_native_redundant_transfers", observed.nativeRepeatedTransfers)
			Add("publication_native_redundant_bytes", observed.nativeRepeatedBytes)
			Add("visible_unique_ever", Count(observed.visibleEver))
			Add("visible_disappearances", observed.visibleDisappearances)
			Add("visible_reappearances", observed.visibleReappearances)
			if observed.steadyVisibleSamples > 0 then
				Add("visible_after_warmup_mean", observed.steadyVisibleSum / observed.steadyVisibleSamples)
				Add("visible_after_warmup_min", observed.steadyVisibleMin)
				Add("visible_after_warmup_max", observed.steadyVisibleMax)
			end
			Add("pending_verification", publications.pending)
			Add("authentication_timeouts", publications.authenticationExpired or 0)
			Add("authentication_latency_max_seconds", publications.authenticationLatencyMax or 0)
			Add("retained_mesh_bytes", publications.retainedBytes)
			Add("diagnostic_errors", peer.diagnosticErrorCount or 0)
		end
		local summary = {}
		for key, rows in pairs(values) do
			summary[key] = Stats(rows)
		end
		Write({
			kind = "coverage",
			schema = 1,
			lua = _VERSION,
			peers = size,
			seed = seed,
			topology = options.topology,
			seconds = second,
			fps = options.fps,
			party = options.party,
			mesh_packet_rate = policy.meshPacketRate or 1,
			mesh_byte_rate = policy.meshByteRate or 200,
			cpu_seconds = os.clock() - cpuStart,
			simulation_frame_cpu_max_ms = maxSimulationFrameCPU,
			host_heap_delta_kib = collectgarbage("count") - heapStart,
			metrics = summary,
			native_operations = operations,
			native_operation_bytes = operationBytes,
			party_logs_ready_seconds = party.firstReadyAt or -1,
			party_progress_emitted = party.emitted,
			party_progress_observed = Count(party.seen),
			party_progress_latency_seconds = Stats(party.latencies),
		})
	end
	for second = 1, options.seconds do
		if options.party and second % 30 == 0 then
			local responder = peers[2]
			responder.benchmarkProgress = responder.benchmarkProgress + 1
			local progress = responder.benchmarkProgress
			assert(responder:Emit("ANN", {
				eventType = "QUEST_PROGRESS",
				senderName = responder.name,
				classFile = "MAGE",
				questId = "1",
				text = "Supplies: " .. progress .. "/1000",
				occurredAt = responder.API.GetServerTime(),
				eventFacts = responder:BuildAnnouncementFacts("QUEST_PROGRESS", 1, "item", false, progress, 1000),
			}, { { distribution = "PARTY", requiresGroup = true } }))
			party.sent[progress], party.emitted = net.now, party.emitted + 1
		end
		net:Advance(1)
		for index, peer in ipairs(peers) do
			local transport, mesh, publications =
				peer:GetTransportMetrics(), peer:GetMeshNetworkMetrics(), peer:GetMeshPublicationMetrics()
			local observed = observations[index]
			local visible, visibleSet = peer:GetVisiblePlayerLocations("map"), {}
			for _, location in ipairs(visible) do
				local name = location.name
				visibleSet[name] = true
				if observed.visibleEver[name] and not observed.visiblePrevious[name] then
					observed.visibleReappearances = observed.visibleReappearances + 1
				end
				observed.visibleEver[name] = true
			end
			for name in pairs(observed.visiblePrevious) do
				if not visibleSet[name] then
					observed.visibleDisappearances = observed.visibleDisappearances + 1
				end
			end
			observed.visiblePrevious = visibleSet
			if second > 300 then
				observed.steadyVisibleSamples = observed.steadyVisibleSamples + 1
				observed.steadyVisibleSum = observed.steadyVisibleSum + #visible
				observed.steadyVisibleMin = math.min(observed.steadyVisibleMin, #visible)
				observed.steadyVisibleMax = math.max(observed.steadyVisibleMax, #visible)
			end
			observed.replayFencesMax = math.max(observed.replayFencesMax, publications.replayFences or 0)
			observed.cachedReplayBlockedMax =
				math.max(observed.cachedReplayBlockedMax, publications.cachedReplayBlockedFor or 0)
			assert(
				(transport.meshPackets or 0)
						<= second * (transport.meshPacketRate or 1) + (transport.meshPacketBurst or 2)
					and (transport.meshBytes or 0)
						<= second * (transport.meshByteRate or 200) + (transport.meshByteBurst or 400),
				"mesh budget exceeded"
			)
			assert(
				#peer.attempts <= second * 4 + 4 and (nativeBytes[peer.name] or 0) <= second * 800 + 1600,
				"shared native budget exceeded"
			)
			assert(
				transport.queuedPackets <= 96 and publications.retainedBytes <= 131072,
				"queue or payload bound exceeded"
			)
			assert(mesh.neighbors <= 8 and mesh.candidates <= 512 and mesh.handshakes <= 3, "discovery bound exceeded")
		end
		if options.party then
			local ready = true
			for _, member in ipairs(peers[1].partyQuestCompareSession.members) do
				if member.state ~= "ready" or Count(member.entries) ~= 30 then
					ready = false
				end
			end
			if ready then
				party.firstReadyAt = party.firstReadyAt or second
			end
			local objective = party.detail.objectives and party.detail.objectives[1]
			local progress = objective and objective.current
			if progress and party.sent[progress] and not party.seen[progress] then
				party.seen[progress] = true
				party.latencies[#party.latencies + 1] = net.now - party.sent[progress]
			end
		end
		if second == 60 or second == 120 or second == 300 or second == 600 or second == options.seconds then
			Sample(second)
		end
	end
	CheckIsolation()
end

for _, size in ipairs(options.peers) do
	for _, seed in ipairs(options.seeds) do
		Scenario(size, seed)
	end
end
