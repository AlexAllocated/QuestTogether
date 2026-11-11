-- Live-safe private producers, native adapters and clocks. No client globals.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function Fixture()
	local a = setmetatable(
		{ now = 100, isEnabled = true, commPrefix = "QT3", sent = {}, errors = {} },
		{ __index = QT }
	)
	a.API = {
		GetTime = function()
			return a.now
		end,
		Random = function(low)
			return low
		end,
		SetOrdinaryWhisperObserver = function() return true end,
		GetPlayerNotFoundMessageFormat = function() return "No player named '%s' is currently playing." end,
		AddMessageEventFilter = function(_, callback)
			a.systemFilter = callback
			return true
		end,
		SendAddonMessage = function(prefix, wire, distribution, target)
			a.sent[#a.sent + 1] =
				{ prefix = prefix, wire = wire, distribution = distribution, target = target, at = a.now }
			if a.native then
				return a.native(prefix, wire, distribution, target)
			end
			return 0
		end,
	}
	function a:RecordCommsTraffic() end
	function a:RecordCommsDiagnostic() end
	function a:IsRuntimeRestrictionTypeActive(kind)
		return kind == "chat" and self.chatRestricted == true
	end
	function a:RecordDiagnosticError(_, detail)
		self.errors[#self.errors + 1] = detail
	end
	function a:Advance(seconds)
		self.now = self.now + seconds
		self:DrainTransport()
	end
	function a:Queue(wire, options)
		return self:QueueTransportWire(wire, "test", { distribution = "WHISPER", target = "Peer-Realm" }, options)
	end
	a:InitializeTransport()
	return a
end

local function WhisperReceiptFixture()
	local a = Fixture()
	a.retired = 0
	a.API.GetPlayerNotFoundMessageFormat = function()
		return "No player named '%s' is currently playing."
	end
	a.API.SetOrdinaryWhisperObserver = function()
		return true
	end
	a.API.AddMessageEventFilter = function(_, callback)
		a.systemFilter = callback
		return true
	end
	function a:RetireMeshPeer()
		self.retired = self.retired + 1
	end
	a:InitializeTransport()
	a:Advance(1)
	return a
end

QT:RegisterTest(
	"transport unsent throttling preserves reply evidence while possible sends retain fresh correlation",
	function()
		local route = { distribution = "WHISPER", target = "Peer-Realm" }
		for _, outcome in ipairs({ 3, 0, 8, 9, "no-result", "exception" }) do
			local a = WhisperReceiptFixture()
			assert(a:SendTransportNow("earlier", "MHEL", route))
			a:ClearAddonWhisperFailure(route.target)
			a.now = a.now + 10
			a.native = function()
				if outcome == "exception" then
					error("unknown native outcome")
				end
				if outcome ~= "no-result" then
					return outcome
				end
			end
			a:SendTransportNow("later", "MHEL", route)
			assert(a.systemFilter({}, "CHAT_MSG_SYSTEM", "No player named 'Peer-Realm' is currently playing."))
			a:HandleAddonWhisperSystemMessage("No player named 'Peer-Realm' is currently playing.")
			if outcome == 3 then
				assert(
					not a:IsAddonWhisperTargetUnavailable(route.target) and a.retired == 0,
					"an unsent throttle attempt must not erase the newer reply to a previous send"
				)
			else
				assert(
					a:IsAddonWhisperTargetUnavailable(route.target) and a.retired == 1,
					"accepted, ambiguous, and unknown outcomes may produce their own later failure"
				)
			end
		end
		local a = WhisperReceiptFixture()
		a.native = function()
			return 3
		end
		assert(not a:SendTransportNow("never-sent", "MHEL", route))
		assert(
			not a.systemFilter({}, "CHAT_MSG_SYSTEM", "No player named 'Peer-Realm' is currently playing."),
			"a throttle-only attempt must not claim another sender's later error"
		)
	end
)

QT:RegisterTest(
	"transport unsent rollback preserves synchronous notices replies and newer reentrant attempts",
	function()
		local route = { distribution = "WHISPER", target = "Peer-Realm" }
		local notice = "No player named 'Peer-Realm' is currently playing."
		for _, reentry in ipairs({ "notice", "reply", "newer-attempt" }) do
			local a = WhisperReceiptFixture()
			assert(a:SendTransportNow("earlier", "MHEL", route))
			a:ClearAddonWhisperFailure(route.target)
			a.now = a.now + 110
			a.native = function()
				if reentry == "notice" then
					assert(a.systemFilter({}, "CHAT_MSG_SYSTEM", notice))
					a:HandleAddonWhisperSystemMessage(notice)
				elseif reentry == "reply" then
					a:ClearAddonWhisperFailure(route.target)
				else
					a.native = nil
					assert(a:SendTransportNow("inner-accepted", "MHEL", route))
				end
				return 3
			end
			a:SendTransportNow("outer-throttled", "MHEL", route)
			-- The original receipt has now expired. Rolling it over the synchronous
			-- observation or the newer send would leak this later native notice.
			a.now = a.now + 20
			assert(a.systemFilter({}, "CHAT_MSG_SYSTEM", notice), "rollback must preserve newer native evidence")
			a:HandleAddonWhisperSystemMessage(notice)
			if reentry == "reply" then
				assert(a.retired == 0 and not a:IsAddonWhisperTargetUnavailable(route.target))
			else
				assert(a.retired == 1 and a:IsAddonWhisperTargetUnavailable(route.target))
			end
		end
	end
)

QT:RegisterTest("transport offline native outcomes stop subsequent sends without needing a system notice", function()
	local a, completed = WhisperReceiptFixture(), 0
	local route = { distribution = "WHISPER", target = "Peer-Realm" }
	a.native = function()
		return 12
	end
	assert(a:QueueTransportWire("first", "MHEL", route))
	assert(a:QueueTransportWire("next", "MPUB", route, {
		onComplete = function(sent, reason)
			assert(not sent and reason == "unavailable")
			completed = completed + 1
		end,
	}))
	a:DrainTransport()
	assert(
		#a.sent == 1 and a.retired == 1 and completed == 1,
		"TargetOffline must install its send hold before the next queued packet"
	)
	assert(a:IsAddonWhisperTargetUnavailable(route.target))
	local sent, reason = a:SendTransportNow("producer-retry", "MHEL", route)
	assert(not sent and reason == "unavailable" and #a.sent == 1)
	assert(a.systemFilter({}, "CHAT_MSG_SYSTEM", "No player named 'Peer-Realm' is currently playing."))
	assert(a.retired == 1, "a later server notice cannot repeat native-outcome retirement")
end)

QT:RegisterTest("transport refuses untrackable whisper addresses before spending native budget", function()
	local a = WhisperReceiptFixture()
	local s = a:GetTransportState()
	local tokens, bytes = s.tokens, s.byteTokens
	for _, target in ipairs({ false, "", "|Hplayer:Peer-Realm|hPeer|h", string.rep("x", 121) }) do
		local route = { distribution = "WHISPER", target = target }
		local queued, queueReason = a:QueueTransportWire("bad-target", "MHEL", route)
		local sent, reason = a:SendTransportNow("bad-target", "MHEL", route)
		assert(not queued and queueReason == "invalid" and not sent and reason == "invalid")
	end
	assert(#a.sent == 0 and s.tokens == tokens and s.byteTokens == bytes)
end)

QT:RegisterTest("transport pauses unsafe background whispers without blocking party or targeted work", function()
	for _, blockedBy in ipairs({ "registration", "unknown-human-target" }) do
		local a = WhisperReceiptFixture()
		if blockedBy == "registration" then
			a.addonWhisperChatFilterRegistered = nil
			a.API.SetOrdinaryWhisperObserver = function() return false end
		else
			a:RegisterAddonWhisperChatFilter()
			a:RecordOrdinaryWhisperAttempt(nil, nil)
		end
		local s, completions = a:GetTransportState(), 0
		local packets, bytes = s.tokens, s.byteTokens
		local mesh = { distribution = "WHISPER", target = "Peer-Realm", meshTraffic = true }
		local sent, reason = a:SendTransportNow("mesh-immediate", "MHEL", mesh)
		assert(not sent and reason == "filter-unavailable" and #a.sent == 0)
		assert(s.tokens == packets and s.byteTokens == bytes, "a local filter hold must not spend native tokens")
		assert(a:QueueTransportWire("mesh-queued", "MHEL", mesh, {
			expires = a.now + 180,
			onComplete = function(ok)
				assert(ok)
				completions = completions + 1
			end,
		}))
		assert(a:QueueTransportWire("party", "QTN3", { distribution = "PARTY" }))
		assert(a:QueueTransportWire("targeted", "PING", { distribution = "WHISPER", target = "Direct-Realm" }))
		for _ = 1, 3 do a:Advance(1) end
		assert(#a.sent == 2 and completions == 0 and #s.queue == 1,
			"a held public packet must not block private messages or escape through the native adapter")
		assert(a:GetTransportMetrics().whisperFilterBlocked == 2,
			"count immediate and newly held work, not every frame spent waiting")
		a.API.SetOrdinaryWhisperObserver = function() return true end
		-- Resume after the same bounded protection period used for ordinary
		-- whispers, without re-creating the queued packet or its callbacks.
		a:Advance(121)
		assert(#a.sent == 3 and a.sent[3].wire == "mesh-queued" and completions == 1 and #s.queue == 0)
		a:Advance(1)
		assert(completions == 1)
	end
	local a = WhisperReceiptFixture()
	a.API.AddMessageEventFilter = function() return false end
	a.addonWhisperChatFilterRegistered = nil
	local completed = 0
	assert(a:Queue("expires-quietly", {
		meshTraffic = true, expires = a.now + 2,
		onComplete = function(ok, reason)
			assert(not ok and reason == "expired")
			completed = completed + 1
		end,
	}))
	a:Advance(1)
	a:Advance(2)
	a:Advance(2)
	assert(#a.sent == 0 and completed == 1 and #a:GetTransportState().queue == 0)

	local b, validations = WhisperReceiptFixture(), 0
	assert(b:Queue("callback-hold", {
		meshTraffic = true, expires = b.now + 180,
		isCurrent = function()
			validations = validations + 1
			if validations == 2 then b:RecordOrdinaryWhisperAttempt(nil, nil) end
			return true
		end,
	}))
	local bs = b:GetTransportState()
	local packets, bytes, meshPackets, meshBytes = bs.tokens, bs.byteTokens, bs.meshTokens, bs.meshByteTokens
	b:DrainTransport()
	assert(#b.sent == 0 and #bs.queue == 1)
	assert(bs.tokens == packets and bs.byteTokens == bytes and bs.meshTokens == meshPackets
		and bs.meshByteTokens == meshBytes, "post-selection safety changes must not spend shared or mesh tokens")
	b:Advance(121)
	assert(#b.sent == 1 and #bs.queue == 0)
end)

QT:RegisterTest("transport refuses channel delivery without spending budget or invoking native APIs", function()
	local a = Fixture()
	a.now = a.now + 1
	local route = { distribution = "CHANNEL", target = 7 }
	Equal(a:QueueTransportWire("forbidden", "STATE", route), false)
	Equal(a:SendTransportNow("forbidden", "STATE", route), false)
	Equal(#a.sent, 0)
	Equal(a:GetTransportMetrics().attempts or 0, 0)
end)

QT:RegisterTest("transport chat restriction holds all native routes while expiring stale work and preserving budgets", function()
	local a, completed = Fixture(), {}
	local routes = {
		{ distribution = "WHISPER", target = "Peer-Realm", meshTraffic = true },
		{ distribution = "PARTY" },
		{ distribution = "RAID" },
		{ distribution = "INSTANCE_CHAT" },
	}
	a:Advance(1)
	local s = a:GetTransportState()
	local credits = { s.tokens, s.byteTokens, s.meshTokens, s.meshByteTokens }
	for index, route in ipairs(routes) do
		assert(a:QueueTransportWire("held-" .. index, "test", route, {
			expires = a.now + 30,
			onComplete = function(sent, reason)
				assert(not completed[index], "a held packet must complete once")
				completed[index] = { sent, reason }
			end,
		}))
	end
	local expiryCount, currentCount = 0, 0
	assert(a:QueueTransportWire("expires", "test", routes[1], {
		expires = a.now + 1,
		onComplete = function(sent, reason)
			assert(not sent and reason == "expired")
			expiryCount = expiryCount + 1
		end,
	}))
	local current = true
	assert(a:QueueTransportWire("retired", "test", routes[1], {
		isCurrent = function() return current end,
		onComplete = function(sent, reason)
			assert(not sent and reason == "cancelled")
			currentCount = currentCount + 1
		end,
	}))
	a.chatRestricted, current = true, false
	for _, route in ipairs(routes) do
		local sent, reason = a:SendTransportNow("direct", "test", route)
		assert(not sent and reason == "restricted")
	end
	a:Advance(2)
	a:DrainTransport()
	Equal(#a.sent, 0)
	Equal(a:GetTransportMetrics().attempts or 0, 0)
	Equal(a:GetTransportMetrics().queuedPackets, #routes)
	Equal(expiryCount, 1)
	Equal(currentCount, 1)
	Equal(#a.errors, 0)
	assert(s.tokens >= credits[1] and s.byteTokens >= credits[2]
		and s.meshTokens >= credits[3] and s.meshByteTokens >= credits[4], "paused sends spend no budget")
	a.chatRestricted = false
	-- Ordinary combat alone must not delay otherwise permitted party traffic.
	function a:IsRuntimeRestricted() return true end
	for _ = 1, 4 do a:Advance(1) end
	Equal(#a.sent, #routes)
	Equal(a:GetTransportMetrics().queuedPackets, 0)
	for index = 1, #routes do assert(completed[index][1] and completed[index][2] == "accepted") end
end)

QT:RegisterTest("transport revalidates chat restriction after currentness and between native sends including departure", function()
	local a, checks, completions = Fixture(), 0, 0
	assert(a:Queue("boundary", {
		isCurrent = function()
			checks = checks + 1
			if checks == 2 then a.chatRestricted = true end
			return true
		end,
		onComplete = function(sent) assert(sent); completions = completions + 1 end,
	}))
	a:Advance(1)
	Equal(#a.sent, 0)
	Equal(completions, 0)
	Equal(a:GetTransportMetrics().queuedPackets, 1)
	Equal(a:GetTransportState().tokens, 4)
	Equal(a:GetTransportState().byteTokens, 800)
	a.chatRestricted = false
	assert(a:Queue("next"))
	a.native = function() a.chatRestricted = true; return 0 end
	a:DrainTransport()
	Equal(#a.sent, 1)
	Equal(completions, 1)
	Equal(a:GetTransportMetrics().queuedPackets, 1)
	local bye = assert(a:BuildCommFrames("BYE", { reason = "departure" }, {
		session = "test", messageId = "1", stamp = 0,
	}))[1]
	a:EndTransportSession()
	local s = a:GetTransportState()
	local tokens, bytes = s.tokens, s.byteTokens
	local sent, reason = a:SendTransportNow(bye, "departure", { distribution = "PARTY" }, "departure")
	assert(not sent and reason == "restricted", "best-effort departure cannot bypass chat restriction")
	Equal(s.tokens, tokens)
	Equal(s.byteTokens, bytes)
	Equal(#a.sent, 1)
	Equal(#a.errors, 0)
end)

QT:RegisterTest("transport unavailable whispers conserve budget and record only native attempts", function()
	local a, blocked, attempts, callbacks = Fixture(), true, {}, 0
	local route = { distribution = "WHISPER", target = "Peer-Realm" }
	function a:IsAddonWhisperTargetUnavailable(target)
		return blocked and target == route.target
	end
	function a:RecordAddonWhisperAttempt(target)
		attempts[#attempts + 1] = target
		return true
	end
	a.native = function(_, _, distribution, target)
		if distribution == "WHISPER" then
			Equal(attempts[#attempts], target)
		end
		return 0
	end
	a:Advance(1)
	local s = a:GetTransportState()
	local tokens, bytes = s.tokens, s.byteTokens
	local queued, reason = a:Queue("blocked", {
		onComplete = function()
			callbacks = callbacks + 1
		end,
	})
	Equal(queued, false)
	Equal(reason, "unavailable")
	local sent, directReason = a:SendTransportNow("blocked", "MHEL", route)
	Equal(sent, false)
	Equal(directReason, "unavailable")
	Equal(callbacks, 0) -- Rejected admission creates no completion ticket.
	Equal(#attempts, 0)
	Equal(#a.sent, 0)
	Equal(s.tokens, tokens)
	Equal(s.byteTokens, bytes)
	Equal(a:GetTransportMetrics().whisperUnavailable, 2)
	assert(a:SendTransportNow("party", "QCMP", { distribution = "PARTY" }))
	Equal(#attempts, 0)
	blocked = false
	assert(a:Queue("recovered"))
	Equal(#attempts, 0) -- Queue admission is not a native whisper attempt.
	a:DrainTransport()
	Equal(#attempts, 1)
	Equal(#a.sent, 2)
	Equal(#a.errors, 0)
end)

QT:RegisterTest("transport unavailable notice cancels queued hops and reentrant cleanup once", function()
	local a, blocked, completions, cleanup = Fixture(), false, {}, {}
	function a:IsAddonWhisperTargetUnavailable(target)
		return blocked and target == "Peer-Realm"
	end
	local function Finished(wire)
		return function(sent, reason)
			assert(not completions[wire], "completion repeated for " .. wire)
			completions[wire] = { sent, reason }
			if wire == "next-fragment" then
				cleanup = {
					a:QueueTransportWire(
						"unavailable-control",
						"FXSTAT",
						{ distribution = "WHISPER", target = "Peer-Realm" }
					),
				}
			end
		end
	end
	assert(a:Queue("first-fragment", { onComplete = Finished("first-fragment") }))
	assert(a:Queue("next-fragment", { onComplete = Finished("next-fragment") }))
	assert(a:QueueTransportWire("party", "QCMP", { distribution = "PARTY" }))
	assert(a:QueueTransportWire("other", "MHEL", { distribution = "WHISPER", target = "Other-Realm" }))
	a.native = function(_, wire)
		if wire == "first-fragment" then
			-- Model asynchronous system feedback arriving during a native call.
			-- The owner marks suppression before cancellation triggers callbacks.
			blocked = true
			a:CancelTransportWhere(function(row)
				return row.route.distribution == "WHISPER" and row.route.target == "Peer-Realm"
			end, "unavailable")
		end
		return 0
	end
	a:Advance(1)
	a:DrainTransport()
	Equal(completions["first-fragment"][1], true)
	Equal(completions["next-fragment"][1], false)
	Equal(completions["next-fragment"][2], "unavailable")
	Equal(cleanup[1], false)
	Equal(cleanup[2], "unavailable")
	Equal(#a.sent, 3)
	for _, row in ipairs(a.sent) do
		assert(row.wire ~= "next-fragment" and row.wire ~= "unavailable-control")
	end
	Equal(a:GetTransportMetrics().queuedPackets, 0)
	Equal(a:GetTransportMetrics().attempts, 3)
	Equal(#a.errors, 0)
end)

QT:RegisterTest("transport currentness callbacks cannot send newly unavailable whispers", function()
	local a, blocked, checks, completions, direct = Fixture(), false, 0, 0, {}
	function a:IsAddonWhisperTargetUnavailable()
		return blocked
	end
	assert(a:Queue("stale-hop", {
		isCurrent = function()
			checks = checks + 1
			if checks == 2 then
				blocked = true
			end
			return true
		end,
		onComplete = function(sent, reason)
			completions = completions + 1
			Equal(sent, false)
			Equal(reason, "unavailable")
			direct = { a:SendTransportNow("cleanup", "FXSTAT", { distribution = "WHISPER", target = "Peer-Realm" }) }
		end,
	}))
	a:Advance(1)
	a:DrainTransport()
	Equal(completions, 1)
	Equal(direct[1], false)
	Equal(direct[2], "unavailable")
	Equal(#a.sent, 0)
	Equal(a:GetTransportState().tokens, 4)
	Equal(a:GetTransportState().byteTokens, 800)
	Equal(a:GetTransportMetrics().attempts or 0, 0)
	Equal(a:GetTransportMetrics().queuedPackets, 0)
	Equal(#a.errors, 0)
end)

QT:RegisterTest("mesh budget charges full packets while party traffic retains capacity", function()
	local a, done = Fixture(), 0
	for i = 1, 24 do
		assert(a:Queue(string.rep("m", 200), {
			meshTraffic = true,
			priority = "active",
			flow = "mesh" .. i,
			expires = a.now + 120,
			onComplete = function()
				done = done + 1
			end,
		}))
	end
	Equal(a:Queue("over-capacity", { meshTraffic = true }), false)
	assert(a:QueueTransportWire("party", "QCMP", { distribution = "PARTY" }, { priority = "active" }))
	for i = 1, 100 do
		a:Advance(0.1)
	end
	local party, bytes, packets = false, 0, 0
	for _, sent in ipairs(a.sent) do
		if sent.distribution == "PARTY" then
			party = true
			assert(sent.at <= 101)
		else
			packets = packets + 1
			bytes = bytes + #sent.wire + #a.commPrefix + 40
		end
	end
	assert(party and packets > 0 and packets <= 20 and bytes <= 4000)
	Equal(done, packets)
	Equal(a:GetTransportMetrics().meshBytes, bytes)
end)

QT:RegisterTest("transport v3 shares empty byte and packet budgets across nearby and queued sends", function()
	local a, result = Fixture(), {}
	local ok, status, ticket = a:Queue(string.rep("x", 255), {
		onComplete = function(...)
			result = { ... }
		end,
	})
	Equal(ok, true)
	Equal(status, "queued")
	Equal(ticket.status, "queued")
	a:DrainTransport()
	Equal(#a.sent, 0)
	a:Advance(0.25)
	Equal(#a.sent, 0) -- Packet token alone cannot afford 255+3+40 bytes.
	a:Advance(0.125)
	Equal(#a.sent, 1)
	Equal(a:GetTransportState().byteTokens, 2)
	Equal(result[1], true)
	Equal(result[2], "accepted")
	Equal(result[3], 0)
	Equal(result[4], ticket)
	Equal(ticket.status, "accepted")
	local sent, reason =
		a:SendTransportNow("n", "nearby", { distribution = "WHISPER", target = "Peer-Realm" }, "nearby")
	Equal(sent, false)
	Equal(reason, "paced")
	Equal(#a.sent, 1)
	a.now = a.now + 0.125
	Equal(a:SendTransportNow("n", "nearby", { distribution = "WHISPER", target = "Peer-Realm" }, "nearby"), true)
	Equal(a:GetTransportMetrics().accepted, 2)
end)

QT:RegisterTest("mesh traffic classes progress while private traffic continuously spends the shared budget", function()
	local a, delivered = Fixture(), {}
	local classes = { "control", "event", "active", "bulk", "background" }
	for _, class in ipairs(classes) do
		for i = 1, 3 do
			assert(a:Queue(string.rep("m", 200), {
				meshTraffic = true,
				priority = class,
				flow = "mesh-" .. class,
				expires = a.now + 90,
				onComplete = function(ok)
					if ok then
						delivered[class] = (delivered[class] or 0) + 1
					end
				end,
			}))
		end
	end
	local keepSending = true
	local function Private(class)
		assert(a:QueueTransportWire("party", "STATE", { distribution = "PARTY" }, {
			priority = class,
			flow = "party-" .. class,
			expires = a.now + 90,
			onComplete = function()
				if keepSending then
					Private(class)
				end
			end,
		}))
	end
	for _, class in ipairs(classes) do
		Private(class)
	end
	for _ = 1, 1200 do
		a:Advance(0.05)
	end
	keepSending = false
	for _, class in ipairs(classes) do
		assert(delivered[class] == 3, "starved mesh class: " .. class)
	end
	assert(a:GetTransportMetrics().meshBytes <= 60 * 400)
end)

QT:RegisterTest("mesh large proofs earn byte credit despite continuous cheap traffic", function()
	for _, cheapClass in ipairs({ "control", "background" }) do
		local a, proofs, cheap, party, running = Fixture(), 0, 0, 0, true
		local function Small()
			assert(a:Queue(string.rep("s", 157), {
				meshTraffic = true,
				priority = cheapClass,
				flow = "small",
				expires = a.now + 30,
				onComplete = function(ok)
					if ok then
						cheap = cheap + 1
					end
					if running then
						Small()
					end
				end,
			}))
		end
		local function Private()
			assert(a:QueueTransportWire("party", "STATE", { distribution = "PARTY" }, {
				priority = "active",
				expires = a.now + 30,
				onComplete = function(ok)
					if ok then
						party = party + 1
					end
					if running then
						Private()
					end
				end,
			}))
		end
		Small()
		Private()
		for _ = 1, 3 do
			assert(a:Queue(string.rep("p", 255), {
				meshTraffic = true,
				priority = "background",
				flow = "proof",
				expires = a.now + 30,
				onComplete = function(ok)
					if ok then
						proofs = proofs + 1
					end
				end,
			}))
		end
		for _ = 1, 300 do
			a:Advance(0.05)
		end
		running = false
		Equal(proofs, 3)
		assert(cheap > 0 and party >= 15, "reserving mesh bytes must allow other traffic to progress")
		assert(a:GetTransportMetrics().meshBytes <= 15 * 400)
		assert(a:GetTransportMetrics().meshPackets <= 30)
	end
end)

QT:RegisterTest("transport v3 caps burst credit and makes at most two attempts per drain", function()
	local a = Fixture()
	for i = 1, 5 do
		assert(a:Queue("packet" .. i, { expires = a.now + 500 }))
	end
	a:Advance(100)
	Equal(#a.sent, 2)
	a:DrainTransport()
	Equal(#a.sent, 4)
	a:DrainTransport()
	Equal(#a.sent, 4)
	Equal(a:GetTransportState().tokens, 0)
	Equal(a:GetTransportState().byteTokens, 1600 - 4 * (7 + 3 + 40))
	a:Advance(0.25)
	Equal(#a.sent, 5)
end)

QT:RegisterTest("transport v3 native throttle retains the ticket and ambiguous results never retry", function()
	local a, completions = Fixture(), {}
	a.native = function()
		return #a.sent == 1 and 3 or (#a.sent == 2 and 8 or 0)
	end
	local _, _, ticket = a:Queue("one", {
		onComplete = function(...)
			completions[#completions + 1] = { ... }
		end,
	})
	a:Advance(1)
	Equal(#a.sent, 1)
	Equal(#completions, 0)
	Equal(a:GetTransportState().queue[1].ticket, ticket)
	Equal(a:GetTransportState().packetRate, 1)
	a:Advance(0.999)
	Equal(#a.sent, 1)
	a:Advance(0.0011)
	Equal(#a.sent, 2)
	Equal(#completions, 1)
	Equal(completions[1][1], false)
	Equal(completions[1][2], "ambiguous")
	Equal(completions[1][3], 8)
	Equal(ticket.status, "ambiguous")
	Equal(#a:GetTransportState().queue, 0)
	assert(a:Queue("two"))
	a:Advance(1)
	Equal(#a.sent, 3)
	a:Advance(20)
	Equal(#a.sent, 3)
	Equal(#completions, 1)
	Equal(a:GetTransportMetrics().throttled, 1)
	Equal(a:GetTransportMetrics().ambiguous, 1)
end)

QT:RegisterTest("transport v3 native outcome diagnostics retain rejection codes with bounded buckets", function()
	local a, failure = Fixture(), nil
	function a:RecordCommsDiagnostic(kind, detail)
		if kind == "failedRoutes" then
			failure = detail
		end
	end
	local function Send(value, throws)
		a.native = function()
			if throws then
				error("private exception detail")
			end
			return value
		end
		a.now = a.now + 2
		-- These are independent native-outcome samples; model a new reply so
		-- TargetOffline's send hold does not suppress later samples.
		a:ClearAddonWhisperFailure("Peer-Realm")
		a:SendTransportNow("private payload", "PING", { distribution = "WHISPER", target = "Peer-Realm" })
	end
	for code = 0, 12 do
		Send(code)
		Equal(a:GetTransportMetrics()["nativeResult" .. code], 1)
		if code ~= 0 then
			Equal(failure, "route=WHISPER result=" .. code .. " PING")
		end
	end
	Send(nil)
	Equal(failure, "route=WHISPER result=no-result PING")
	Send(nil, true)
	Equal(failure, "route=WHISPER result=exception PING")
	Send(true)
	for _, value in ipairs({ -1, 13, 999, 3.5, false, "unexpected", {} }) do
		Send(value)
	end
	local metrics, buckets = a:GetTransportMetrics(), 0
	Equal(metrics.nativeNoResult, 1)
	Equal(metrics.nativeException, 1)
	Equal(metrics.nativeBooleanSuccess, 1)
	Equal(metrics.nativeUnknown, 7)
	Equal(failure, "route=WHISPER result=unknown PING")
	for key in pairs(metrics) do
		if key:match("^native") then
			buckets = buckets + 1
		end
	end
	Equal(buckets, 17)
	Equal(metrics.attempts, 23)
end)

QT:RegisterTest(
	"transport v3 hard failures stay in QT diagnostics without global errors or broken completion",
	function()
		local a, reported, completed = Fixture(), {}, {}
		a.API.ReportLuaError = function(detail)
			reported[#reported + 1] = detail
			error("communication failures must not invoke the global error collector")
		end
		local function Send(operation, distribution, result)
			a.native = function()
				return result
			end
			local ok, _, ticket = a:QueueTransportWire(
				"private quest data",
				operation,
				{ distribution = distribution, target = distribution == "WHISPER" and "Private-Realm" or nil },
				{
					onComplete = function(sent, reason)
						completed[#completed + 1] = { sent = sent, reason = reason }
					end,
				}
			)
			assert(ok)
			a:Advance(2)
			return ticket
		end
		Equal(Send("QCMP", "PARTY", 7).status, "rejected")
		Equal(#reported, 0)
		Equal(#a.errors, 1)
		assert(a.errors[1]:find("operation=QCMP, route=PARTY, result=7", 1, true))
		assert(not a.errors[1]:find("private quest data", 1, true))
		assert(not a.errors[1]:find("Private-Realm", 1, true))
		Send("QCMP", "PARTY", 7)
		Send("QCRS", "PARTY", 7)
		Equal(#a.errors, 1, "the same route failure is logged once per minute")
		Send("QCMP", "WHISPER", 7)
		Equal(#a.errors, 2, "a distinct route failure is not hidden")
		Equal(Send("QCRS", "PARTY", 0).status, "accepted")
		Equal(#completed, 5)
		Equal(completed[1].sent, false)
		Equal(completed[5].sent, true)
		Equal(a:GetTransportMetrics().queuedPackets, 0)
		a:Advance(60)
		Send("QCMP", "PARTY", 7)
		Equal(#reported, 0)
		Equal(#a.errors, 3)
		local metrics = a:GetTransportMetrics()
		Equal(metrics["questWire.QCMP.PARTY.nativeResult7"], 3)
		Equal(metrics["questWire.QCMP.WHISPER.nativeResult7"], 1)
		Equal(metrics["questWire.QCRS.PARTY.nativeResult7"], 1)
		Equal(metrics["questWire.QCRS.PARTY.nativeResult0"], 1)
	end
)

QT:RegisterTest("transport v3 throttles and ambiguous sends are not reported as hard failures", function()
	local a, reported = Fixture(), {}
	a.API.ReportLuaError = function(detail)
		reported[#reported + 1] = detail
	end
	a.native = function()
		return #a.sent == 1 and 3 or 8
	end
	local ok, _, ticket = a:QueueTransportWire("data", "QCMP", { distribution = "PARTY" })
	assert(ok)
	a:Advance(1)
	Equal(ticket.status, "queued")
	a:Advance(1)
	Equal(ticket.status, "ambiguous")
	Equal(#reported, 0)
	Equal(#a.errors, 0)
	Equal(a:GetTransportMetrics()["questWire.QCMP.PARTY.nativeResult3"], 1)
	Equal(a:GetTransportMetrics()["questWire.QCMP.PARTY.nativeResult8"], 1)
end)

QT:RegisterTest("transport v3 ambiguous native results do not imply delivery or trigger retransmission", function()
	for _, delivered in ipairs({ false, true }) do
		local net = QT:CreateTestNetwork({ fps = 20 })
		local a, b = net:AddPeer("Sender-Realm"), net:AddPeer("Receiver-Realm")
		a:InitializeTransport()
		local received, completions = {}, {}
		function b:OnCommReceived(_, wire)
			received[#received + 1] = wire
		end
		net.sendRule = function()
			return 8, delivered
		end
		local frame = net:CreateFrame(a)
		frame:SetScript("OnUpdate", function()
			a:DrainTransport()
		end)
		local admitted, _, ticket = a:QueueTransportWire(
			"ambiguous",
			"fixture",
			{ distribution = "WHISPER", target = b.name },
			{
				onComplete = function(ok, reason, code)
					completions[#completions + 1] = { ok, reason, code }
				end,
			}
		)
		assert(admitted)
		net:Advance(10)
		Equal(#a.attempts, 1)
		Equal(#completions, 1)
		Equal(completions[1][1], false)
		Equal(completions[1][2], "ambiguous")
		Equal(completions[1][3], 8)
		Equal(ticket.status, "ambiguous")
		Equal(#received, delivered and 1 or 0)
		Equal(net.metrics.accepted, 0)
		Equal(a:GetTransportMetrics().queuedPackets, 0)
	end
end)

QT:RegisterTest("transport v3 weighted classes rotate peers while preserving flow order", function()
	local a = Fixture()
	for _, class in ipairs({ "control", "event", "active", "bulk", "background" }) do
		for _, flow in ipairs({ "A", "B" }) do
			for i = 1, 4 do
				assert(a:Queue(class .. flow .. i, { priority = class, flow = flow, expires = a.now + 300 }))
			end
		end
	end
	for _ = 1, 4 do
		a:Advance(1)
	end
	local firstRotation, firstFlows = {}, {}
	for _, packet in ipairs(a.sent) do
		local class, flow = packet.wire:match("^(%l+)(%u)")
		assert(class and flow)
		firstRotation[class] = (firstRotation[class] or 0) + 1
		firstFlows[class .. flow] = true
	end
	for class, weight in pairs({ control = 1, event = 1, active = 3, bulk = 2, background = 1 }) do
		Equal(firstRotation[class], weight)
	end
	for _, class in ipairs({ "active", "bulk" }) do
		assert(firstFlows[class .. "A"] and firstFlows[class .. "B"], "weighted service must rotate both queued flows")
	end
	for _ = 1, 20 do
		a:Advance(1)
	end
	local positions = {}
	for _, row in ipairs(a.sent) do
		local flow, sequence = row.wire:match("^(%a+)(%d+)$")
		Equal(tonumber(sequence), (positions[flow] or 0) + 1)
		positions[flow] = tonumber(sequence)
	end
	Equal(#a.sent, 40)
end)

QT:RegisterTest(
	"transport v3 control reserve bounds queue admission without discarding rejected replacements",
	function()
		local a = Fixture()
		for i = 1, 80 do
			assert(a:Queue("bulk" .. i, { priority = "bulk", key = "key" .. i }))
		end
		local ok, reason = a:Queue("full", { priority = "active" })
		Equal(ok, false)
		Equal(reason, "capacity")
		for i = 1, 16 do
			assert(a:Queue("control" .. i, { key = "control" .. i }))
		end
		Equal(a:Queue("overflow"), false)
		Equal(#a:GetTransportState().queue, 96)
		Equal(a:Queue(string.rep("x", 256), { key = "key1" }), false)
		Equal(a:GetTransportState().queue[1].wire, "bulk1")
		-- Non-control cannot convert an existing control reservation into background.
		Equal(a:Queue("replacement", { key = "control1", priority = "background" }), false)
		Equal(a:GetTransportState().queue[1].wire, "bulk1")
		-- Replacing existing background data does not consume another reserved slot.
		Equal(a:Queue("latest", { key = "key1", priority = "background" }), true)
		Equal(a:GetTransportMetrics().queuedPackets, 96)
	end
)

QT:RegisterTest("transport v3 supersession callbacks can replace newly admitted work exactly once", function()
	local a, calls, tickets = Fixture(), {}, {}
	-- Recursive local reference must be explicit in Lua 5.1.
	local callback
	callback = function(name)
		return function(_, reason, _, ticket)
			calls[#calls + 1] = name .. ":" .. reason
			Equal(ticket.status, reason)
			if name == "old" then
				local _, _, newest = a:Queue("newest", { key = "position", onComplete = callback("newest") })
				tickets.newest = newest
			end
		end
	end
	local _, _, old = a:Queue("old", { key = "position", onComplete = callback("old") })
	local _, _, new = a:Queue("new", { key = "position", onComplete = callback("new") })
	Equal(old.status, "superseded")
	Equal(new.status, "superseded")
	Equal(#a:GetTransportState().queue, 1)
	Equal(a:GetTransportState().queue[1].wire, "newest")
	a:Advance(1)
	Equal(table.concat(calls, ","), "old:superseded,new:superseded,newest:accepted")
	Equal(tickets.newest.status, "accepted")
	Equal(#a.sent, 1)
end)

QT:RegisterTest("transport v3 expiration and failing currentness settle before any native send", function()
	local a, calls = Fixture(), {}
	local function Done(_, reason)
		calls[#calls + 1] = reason
	end
	assert(a:Queue("expired", { expires = a.now + 0.5, onComplete = Done }))
	assert(a:Queue("revoked", {
		isCurrent = function()
			return false
		end,
		onComplete = Done,
	}))
	assert(a:Queue("throws", {
		isCurrent = function()
			error("unreadable eligibility")
		end,
		onComplete = Done,
	}))
	a:Advance(1)
	Equal(#a.sent, 0)
	Equal(table.concat(calls, ","), "expired,cancelled,cancelled")
	Equal(a:GetTransportMetrics().expired, 1)
	Equal(a:GetTransportMetrics().cancelled, 2)
end)

QT:RegisterTest("transport v3 native reentrancy rechecks consent before sending the next packet", function()
	local a, allowed = Fixture(), true
	assert(a:Queue("control"))
	local _, _, ticket = a:Queue("location", {
		priority = "active",
		isCurrent = function()
			return allowed
		end,
	})
	a.native = function()
		allowed = false
		a:DrainTransport()
		return 0
	end
	a:Advance(1)
	Equal(#a.sent, 1)
	Equal(ticket.status, "cancelled")
	Equal(#a:GetTransportState().queue, 0)
end)

QT:RegisterTest("transport v3 cancellation from native callbacks never removes another queued packet", function()
	local a, owner, calls = Fixture(), {}, {}
	local _, _, first = a:Queue("first", {
		owner = owner,
		onComplete = function(_, reason)
			calls[#calls + 1] = reason
		end,
	})
	local _, _, second = a:Queue("second", {
		owner = owner,
		onComplete = function(_, reason)
			calls[#calls + 1] = reason
		end,
	})
	a.native = function()
		a:CancelTransportOwner(owner)
		assert(a:Queue("replacement"))
		return 3
	end
	a:Advance(1)
	Equal(first.status, "cancelled")
	Equal(second.status, "cancelled")
	Equal(#calls, 2)
	Equal(#a:GetTransportState().queue, 1)
	Equal(a:GetTransportState().queue[1].wire, "replacement")
	a.native = nil
	a:Advance(1)
	Equal(#a.sent, 2)
	Equal(a.sent[2].wire, "replacement")
end)

QT:RegisterTest("transport v3 native acceptance remains truthful when world teardown occurs inline", function()
	local a, callbacks = Fixture(), 0
	local _, _, first = a:Queue("first", {
		onComplete = function(sent, reason)
			Equal(sent, true)
			Equal(reason, "accepted")
			callbacks = callbacks + 1
		end,
	})
	local _, _, second = a:Queue("second")
	a.native = function()
		a:EndTransportSession()
		return 0
	end
	a:Advance(1)
	Equal(first.status, "accepted")
	Equal(second.status, "cancelled")
	Equal(callbacks, 1)
	Equal(#a.sent, 1)
	a.native = nil
	a:ResumeTransportSession()
	assert(a:Queue("nextworld"))
	a:DrainTransport()
	Equal(#a.sent, 1)
	a:Advance(0.25)
	Equal(#a.sent, 2)
end)

QT:RegisterTest("transport v3 callbacks run after traversal and survive exceptions and state replacement", function()
	local a, seen = Fixture(), {}
	assert(a:Queue("first", {
		onComplete = function()
			seen[#seen + 1] = #a.sent
			a:ResetTransport()
			a:InitializeTransport()
			assert(a:Queue("replacement"))
			error("completion failed")
		end,
	}))
	assert(a:Queue("second", {
		onComplete = function()
			seen[#seen + 1] = #a.sent
		end,
	}))
	a:Advance(1)
	Equal(seen[1], 2)
	Equal(seen[2], 2)
	Equal(#a.errors, 1)
	Equal(#a:GetTransportState().queue, 1)
	a:Advance(0.25)
	Equal(a.sent[3].wire, "replacement")
end)

QT:RegisterTest("transport v3 ownership cancellation and world transitions cannot release old work", function()
	local a, owner = Fixture(), {}
	local _, _, one = a:Queue("owned", { owner = owner })
	local _, _, two = a:Queue("other")
	a:CancelTransportOwner(owner)
	Equal(one.status, "cancelled")
	Equal(two.status, "queued")
	a:EndTransportSession()
	Equal(two.status, "cancelled")
	Equal(a:Queue("departed"), false)
	a:Advance(60)
	Equal(#a.sent, 0)
	a:ResumeTransportSession()
	local _, _, three = a:Queue("new")
	Equal(three.status, "queued")
	a:DrainTransport()
	Equal(#a.sent, 0)
	a:Advance(0.25)
	Equal(#a.sent, 1)
	a.now = a.now - 5
	Equal(a:SendTransportNow("clock", "test", { distribution = "WHISPER", target = "Peer-Realm" }), false)
	Equal(a:GetTransportState().tokens, 0)
	Equal(a:GetTransportState().byteTokens, 0)
end)

QT:RegisterTest("transport v3 departure is best effort within the same budget and never retries", function()
	local a = Fixture()
	a.isLoggingOut = true
	local route = { distribution = "WHISPER", target = "Peer-Realm" }
	local bye =
		assert(a:BuildCommFrames("BYE", { reason = "departure" }, { session = "test", messageId = "1", stamp = 0 }))[1]
	Equal(a:Queue("logout"), false)
	Equal(a:SendTransportNow(bye, "departure", route, "departure"), false)
	a.now = a.now + 1
	Equal(a:SendTransportNow("ordinary", "test", route), false)
	a.native = function()
		return 8
	end
	local sent, reason = a:SendTransportNow(bye, "departure", route, "departure")
	Equal(sent, false)
	Equal(reason, "ambiguous")
	Equal(#a.sent, 1)
	a:EndTransportSession()
	a:Advance(100)
	Equal(#a.sent, 1)
	-- Departure freezes both budgets. A public neighbor cannot spend the
	-- capacity reserved for actual party traffic after the mesh budget runs out.
	local s = a:GetTransportState()
	s.tokens, s.byteTokens, s.meshTokens, s.meshByteTokens = 2, 1600, 0, 400
	local publicRoute = { distribution = "WHISPER", target = "Peer-Realm", meshTraffic = true }
	Equal(a:SendTransportNow(bye, "departure", publicRoute, "departure"), false)
	Equal(s.tokens, 2)
	s.meshTokens = 1
	a:SendTransportNow(bye, "departure", publicRoute, "departure")
	Equal(s.meshTokens, 0)
	Equal(s.tokens, 1)
	Equal(s.metrics.meshPackets, 1)
end)

QT:RegisterTest("transport v3 admission validates packets and retains only bounded primitive metrics", function()
	local a = Fixture()
	for _, wire in ipairs({ "", "a\0b", string.rep("x", 256) }) do
		Equal(a:Queue(wire), false)
	end
	Equal(a:Queue("bad", { priority = "unknown" }), false)
	Equal(a:Queue("bad", { expires = math.huge }), false)
	Equal(a:QueueTransportWire("bad", "test", nil), false)
	local route = { distribution = "WHISPER", target = "Original-Realm" }
	assert(a:QueueTransportWire("valid", "test", route, { priority = "active", flow = "original" }))
	route.target = "Replacement-Realm"
	a:Advance(1)
	Equal(a.sent[1].target, "Original-Realm")
	local metrics = a:GetTransportMetrics()
	Equal(metrics.accepted, 1)
	Equal(metrics.queuedPackets, 0)
	for _, value in pairs(metrics) do
		assert(type(value) == "number" or type(value) == "table")
	end
	local classes = 0
	for _, value in pairs(metrics.classes) do
		Equal(value, 0)
		classes = classes + 1
	end
	Equal(classes, 5)
	metrics.classes.active = 99
	metrics.accepted = 99
	Equal(a:GetTransportMetrics().accepted, 1)
	Equal(a:GetTransportMetrics().classes.active, 0)
end)

QT:RegisterTest("transport v3 eligibility callbacks cannot resurrect their own cancelled packet", function()
	local a, checks, owner = Fixture(), 0, {}
	local _, _, ticket = a:Queue("cancel-self", {
		owner = owner,
		isCurrent = function()
			checks = checks + 1
			if checks == 2 then
				a:CancelTransportOwner(owner)
			end
			return true
		end,
	})
	a:Advance(1)
	Equal(ticket.status, "cancelled")
	Equal(#a.sent, 0)
end)

QT:RegisterTest(
	"transport v3 rejected native and channel errors settle once without blocking unrelated work",
	function()
		local a, results = Fixture(), {}
		a.native = function()
			error("native refused")
		end
		assert(a:Queue("throws", {
			onComplete = function(_, reason)
				results[#results + 1] = reason
			end,
		}))
		a:Advance(1)
		Equal(results[1], "rejected")
		Equal(#a.sent, 1)
		a:Advance(5)
		Equal(#a.sent, 1)
		a.native = nil
		function a:EnsureAnnouncementChannelJoined()
			error("channel unavailable")
		end
		local admitted, reason = a:QueueTransportWire(
			"channel",
			"test",
			{ distribution = "CHANNEL", channelName = "QTTest", requiresChannelJoin = true }
		)
		assert(a:Queue("unrelated"))
		a:Advance(1)
		Equal(admitted, false)
		Equal(reason, "invalid")
		Equal(#a.sent, 2)
		Equal(a.sent[2].wire, "unrelated")
		Equal(a:GetTransportMetrics().rejected, 1)
	end
)

QT:RegisterTest("transport rotating mesh destinations cannot starve replaced native party movement", function()
	local a = Fixture()
	assert(a:Queue("first-public-sample", {
		meshTraffic = true,
		priority = "active",
		flow = "mesh-destination-one",
		expires = a.now + 30,
	}))
	a:Advance(1)
	Equal(#a.sent, 1)
	-- The next inner mesh turn selects a different destination. The previously
	-- served real flow no longer exists in the outer scheduler's eligible set.
	assert(a:Queue("next-public-sample", {
		meshTraffic = true,
		priority = "active",
		flow = "mesh-destination-two",
		expires = a.now + 30,
	}))
	for _, sample in ipairs({ "old-party-location", "latest-party-location" }) do
		assert(a:QueueTransportWire(sample, "STATE", { distribution = "PARTY" }, {
			priority = "active",
			flow = "party-location",
			key = "party-location",
			expires = a.now + 2,
		}))
	end
	a:Advance(1)
	Equal(a.sent[2].distribution, "PARTY")
	Equal(a.sent[2].wire, "latest-party-location")
	Equal(a.sent[3].wire, "next-public-sample")
end)

QT:RegisterTest("transport large private packets earn byte credit under continuous cheap traffic", function()
	for _, fps in ipairs({ 1, 5, 60 }) do
		local a, large, cheap, running = Fixture(), 0, 0, true
		local function Small()
			assert(a:Queue(string.rep("s", 157), {
				priority = "control",
				flow = "small",
				expires = a.now + 60,
				onComplete = function(ok)
					if ok then
						cheap = cheap + 1
					end
					if running then
						Small()
					end
				end,
			}))
		end
		Small()
		for _ = 1, 3 do
			assert(a:Queue(string.rep("p", 255), {
				priority = "bulk",
				flow = "large",
				expires = a.now + 60,
				onComplete = function(ok)
					if ok then
						large = large + 1
					end
				end,
			}))
		end
		for _ = 1, fps * 30 do
			a:Advance(1 / fps)
		end
		running = false
		assert(large == 3, "large private flow starved at " .. fps .. " FPS: " .. large)
		assert(cheap > 0)
		local bytes = 0
		for _, p in ipairs(a.sent) do
			bytes = bytes + #p.wire + #a.commPrefix + 40
		end
		assert(bytes <= 30 * 800 and #a.sent <= 30 * 4)
	end
end)
