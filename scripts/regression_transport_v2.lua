-- Live-safe private producers, native adapters and clocks. No client globals.
local QT = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function Fixture()
	local a = setmetatable(
		{ now = 100, isEnabled = true, commPrefix = "QT2", sent = {}, errors = {} },
		{ __index = QT }
	)
	a.API = {
		GetTime = function()
			return a.now
		end,
		Random = function(low)
			return low
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
	function a:RecordDiagnosticError(_, detail)
		self.errors[#self.errors + 1] = detail
	end
	function a:EnsureAnnouncementChannelJoined()
		return self.joined ~= false
	end
	function a:GetAnnouncementChannelTarget()
		return self.channelID or 7
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

local function ChannelRoute(name, target)
	return {
		distribution = "CHANNEL",
		channelName = name or "QuestTogether",
		target = target or 7,
		requiresChannelJoin = true,
	}
end

QT:RegisterTest("transport channel backoff grows by name and recovers only after a quiet successful probe", function()
	local a, route = Fixture(), ChannelRoute()
	a.native = function()
		return 7
	end
	a.now = a.now + 1
	for index, delay in ipairs({ 5, 10, 20, 40, 80, 120, 120 }) do
		local sent, reason, code = a:SendTransportNow("fresh state", "STATE", route)
		Equal(sent, false)
		Equal(reason, "rejected")
		Equal(code, 7)
		Equal(a:GetTransportMetrics().channelBackoffMaxRemaining, delay)
		local state, calls = a:GetTransportState(), #a.sent
		local bytes, packets = state.byteTokens, state.tokens
		-- Channel list reordering and capitalization cannot bypass the cooldown.
		a.channelID, route = 19, ChannelRoute("qUeStToGeThEr", 19)
		local joined = 0
		function a:EnsureAnnouncementChannelJoined()
			joined = joined + 1
			return true
		end
		local queued, why, ticket = a:QueueTransportWire("discarded", "STATE", route)
		Equal(queued, false)
		Equal(why, "backoff")
		Equal(ticket, nil)
		a:RecordTransportChannelRefusal("QuestTogether")
		Equal(a:GetTransportMetrics().channelBackoffMaxRemaining, delay)
		a.now = a.now + delay - 0.01
		local immediate, blocked = a:SendTransportNow("discarded", "STATE", route)
		Equal(immediate, false)
		Equal(blocked, "backoff")
		Equal(joined, 0)
		Equal(#a.sent, calls)
		Equal(state.byteTokens, bytes)
		Equal(state.tokens, packets)
		Equal(a:GetTransportMetrics().packetRate, 4)
		a.now = a.now + 0.01
		Equal(a:GetTransportMetrics().channelProbes or 0, index - 1)
	end
	a.native = nil
	Equal(a:SendTransportNow("recovery", "STATE", route), true)
	Equal(a.sent[#a.sent].target, 19)
	local admitted, why = a:QueueTransportWire("too early", "STATE", route)
	Equal(admitted, false)
	Equal(why, "backoff")
	a:Advance(5)
	Equal(a:GetTransportMetrics().channelRecoveries, 1)
	Equal(a:GetTransportMetrics().channelBackoffChannels, 0)
	a.native = function()
		return 7
	end
	Equal(a:SendTransportNow("new failure", "STATE", route), false)
	Equal(a:GetTransportMetrics().channelBackoffMaxRemaining, 5)
end)

QT:RegisterTest("transport channel cooldown settles stale work once without spending healthy route budgets", function()
	local a, route, calls, current = Fixture(), ChannelRoute(), {}, true
	local function Queue(label, options)
		options = options or {}
		options.onComplete = function(sent, reason)
			calls[label] = (calls[label] or 0) + 1
			Equal(sent, false)
			Equal(reason, label)
		end
		local accepted, _, ticket = a:QueueTransportWire(label, "STATE", route, options)
		assert(accepted)
		return ticket
	end
	local owner = {}
	local blocked = Queue("backoff")
	local expired = Queue("expired", { expires = a.now + 0.5 })
	local stale = Queue("cancelled", {
		isCurrent = function()
			return current
		end,
	})
	local cancelled = Queue("owner cancelled", { owner = owner })
	a:RecordTransportChannelRefusal(route.channelName)
	a:CancelTransportOwner(owner, "owner cancelled")
	current = false
	assert(a:QueueTransportWire("party", "QCMP", { distribution = "PARTY" }, { priority = "bulk" }))
	assert(a:Queue("whisper", { priority = "event" }))
	assert(a:QueueTransportWire("other channel", "STATE", ChannelRoute("QTGeoHealthy"), { priority = "active" }))
	a:Advance(1)
	a:DrainTransport()
	Equal(blocked.status, "backoff")
	Equal(expired.status, "expired")
	Equal(stale.status, "cancelled")
	Equal(cancelled.status, "owner cancelled")
	Equal(#a.sent, 3)
	Equal(a:GetTransportMetrics().attempts, 3)
	Equal(a:GetTransportMetrics().packetTokens, 1)
	Equal(a:GetTransportMetrics().queuedPackets, 0)
	a:Advance(10)
	for _, label in ipairs({ "backoff", "expired", "cancelled", "owner cancelled" }) do
		Equal(calls[label], 1)
	end
	Equal(#a.sent, 3)
	Equal(#a.errors, 0)
	local b, settled = Fixture(), {}
	b.native = function()
		return 7
	end
	local tickets = {}
	for _, label in ipairs({ "rejected", "backoff" }) do
		local admitted, _, ticket = b:QueueTransportWire(label, "STATE", route, {
			onComplete = function(sent, reason)
				Equal(sent, false)
				settled[#settled + 1] = reason
			end,
		})
		assert(admitted)
		tickets[#tickets + 1] = ticket
	end
	b:Advance(1)
	b:DrainTransport()
	b:Advance(10)
	Equal(tickets[1].status, "rejected")
	Equal(tickets[2].status, "backoff")
	Equal(settled[1], "rejected")
	Equal(settled[2], "backoff")
	Equal(#settled, 2)
	Equal(#b.sent, 1)
	Equal(#b.errors, 1) -- The native refusal is reported once; no callback assertion failed.
end)

QT:RegisterTest(
	"transport channel jitter stays bounded and cooldown history survives only its intended lifetime",
	function()
		local a, route = Fixture(), ChannelRoute()
		a.API.Random = function(low, high)
			Equal(low, 0)
			Equal(high, 100)
			return high
		end
		a.native = function()
			return 7
		end
		a.now = a.now + 1
		for _, delay in ipairs({ 5.5, 11, 22, 44, 88, 120, 120 }) do
			Equal(a:SendTransportNow("state", "STATE", route), false)
			assert(math.abs(a:GetTransportMetrics().channelBackoffMaxRemaining - delay) < 0.000001)
			a.now = a.now + delay
		end
		local b = Fixture()
		b:RecordTransportChannelRefusal("QuestTogether")
		b:EndTransportSession()
		b:ResumeTransportSession()
		local admitted, reason = b:QueueTransportWire("state", "STATE", route)
		Equal(admitted, false)
		Equal(reason, "backoff")
		b:ResetTransport()
		b:InitializeTransport()
		Equal(b:GetTransportMetrics().channelBackoffChannels, 0)
		for index = 1, 40 do
			b:RecordTransportChannelRefusal("QTGeo" .. index)
			assert(b:GetTransportMetrics().channelBackoffChannels <= 32)
		end
		b:Advance(601)
		Equal(b:GetTransportMetrics().channelBackoffChannels, 0)
		b:RecordTransportChannelRefusal("QuestTogether")
		b.now = 1
		Equal(b:GetTransportMetrics().channelBackoffChannels, 0)
		assert(b:QueueTransportWire("new clock", "STATE", route))
	end
)

QT:RegisterTest("transport channel probes preserve throttle tickets and never replay ambiguous sends", function()
	local a, route, completions = Fixture(), ChannelRoute(), 0
	a:RecordTransportChannelRefusal(route.channelName)
	a.now = a.now + 5
	a.native = function()
		return #a.sent == 1 and 3 or 8
	end
	local admitted, _, ticket = a:QueueTransportWire("one probe", "PING", route, {
		onComplete = function()
			completions = completions + 1
		end,
	})
	assert(admitted)
	a:DrainTransport()
	Equal(ticket.status, "queued")
	Equal(completions, 0)
	Equal(a:GetTransportMetrics().throttled, 1)
	Equal(a:GetTransportMetrics().packetRate, 1)
	a:Advance(1)
	Equal(ticket.status, "ambiguous")
	Equal(completions, 1)
	a:RecordTransportChannelRefusal(route.channelName)
	Equal(a:GetTransportMetrics().channelBackoffMaxRemaining, 10)
	local sent, reason = a:SendTransportNow("not a retry", "PING", route)
	Equal(sent, false)
	Equal(reason, "backoff")
	a:Advance(200)
	Equal(#a.sent, 2)
	Equal(completions, 1)
end)

QT:RegisterTest("transport reentrant refusals and resets cannot turn a probe into a recovered old lifetime", function()
	local a, route = Fixture(), ChannelRoute()
	a:RecordTransportChannelRefusal(route.channelName)
	a.now = a.now + 5
	a.native = function()
		a:RecordTransportChannelRefusal(route.channelName)
		return 0
	end
	Equal(a:SendTransportNow("probe", "STATE", route), true)
	Equal(a:GetTransportMetrics().channelBackoffMaxRemaining, 10)
	a:Advance(5)
	Equal(a:GetTransportMetrics().channelRecoveries or 0, 0)
	local admitted, reason = a:QueueTransportWire("blocked", "STATE", route)
	Equal(admitted, false)
	Equal(reason, "backoff")
	a.now = a.now + 5
	a.native = function()
		a:ResetTransport()
		a:InitializeTransport()
		return 7
	end
	a:SendTransportNow("old generation", "STATE", route)
	Equal(a:GetTransportMetrics().channelBackoffChannels, 0)
	assert(a:QueueTransportWire("new generation", "STATE", route))
	local b = Fixture()
	b:RecordTransportChannelRefusal(route.channelName)
	b.now = b.now + 5
	b.native = function()
		b:EndTransportSession()
		b:ResumeTransportSession()
		return 0
	end
	Equal(b:SendTransportNow("suspended generation", "STATE", route), true)
	b:Advance(5)
	Equal(b:GetTransportMetrics().channelRecoveries or 0, 0)
	Equal(b:GetTransportMetrics().channelBackoffChannels, 1)
end)

QT:RegisterTest("transport v2 shares empty byte and packet budgets across nearby and queued sends", function()
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

QT:RegisterTest("transport v2 caps burst credit and makes at most two attempts per drain", function()
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

QT:RegisterTest("transport v2 native throttle retains the ticket and ambiguous results never retry", function()
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

QT:RegisterTest("transport v2 native outcome diagnostics retain rejection codes with bounded buckets", function()
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
		a:SendTransportNow("private payload", "PING", { distribution = "CHANNEL", target = 7 })
	end
	for code = 0, 12 do
		Send(code)
		Equal(a:GetTransportMetrics()["nativeResult" .. code], 1)
		if code ~= 0 then
			Equal(failure, "route=CHANNEL result=" .. code .. " PING")
		end
	end
	Send(nil)
	Equal(failure, "route=CHANNEL result=no-result PING")
	Send(nil, true)
	Equal(failure, "route=CHANNEL result=exception PING")
	Send(true)
	for _, value in ipairs({ -1, 13, 999, 3.5, false, "unexpected", {} }) do
		Send(value)
	end
	local metrics, buckets = a:GetTransportMetrics(), 0
	Equal(metrics.nativeNoResult, 1)
	Equal(metrics.nativeException, 1)
	Equal(metrics.nativeBooleanSuccess, 1)
	Equal(metrics.nativeUnknown, 7)
	Equal(failure, "route=CHANNEL result=unknown PING")
	for key in pairs(metrics) do
		if key:match("^native") then
			buckets = buckets + 1
		end
	end
	Equal(buckets, 17)
	Equal(metrics.attempts, 23)
end)

QT:RegisterTest("transport v2 hard failures stay in QT diagnostics without global errors or broken completion", function()
	local a, reported, completed = Fixture(), {}, {}
	a.API.ReportLuaError = function(detail)
		reported[#reported + 1] = detail
		error("communication failures must not invoke the global error collector")
	end
	local function Send(operation, distribution, result)
		a.native = function() return result end
		local ok, _, ticket = a:QueueTransportWire("private quest data", operation,
			{ distribution = distribution, target = distribution == "WHISPER" and "Private-Realm" or nil }, {
				onComplete = function(sent, reason)
					completed[#completed + 1] = { sent = sent, reason = reason }
				end,
			})
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
end)

QT:RegisterTest("transport v2 throttles and ambiguous sends are not reported as hard failures", function()
	local a, reported = Fixture(), {}
	a.API.ReportLuaError = function(detail) reported[#reported + 1] = detail end
	a.native = function() return #a.sent == 1 and 3 or 8 end
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

QT:RegisterTest("transport v2 ambiguous native results do not imply delivery or trigger retransmission", function()
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

QT:RegisterTest("transport v2 weighted classes rotate peers while preserving flow order", function()
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
	"transport v2 control reserve bounds queue admission without discarding rejected replacements",
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

QT:RegisterTest("transport v2 supersession callbacks can replace newly admitted work exactly once", function()
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

QT:RegisterTest("transport v2 expiration and failing currentness settle before any native send", function()
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

QT:RegisterTest("transport v2 native reentrancy rechecks consent before sending the next packet", function()
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

QT:RegisterTest("transport v2 cancellation from native callbacks never removes another queued packet", function()
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

QT:RegisterTest("transport v2 native acceptance remains truthful when world teardown occurs inline", function()
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

QT:RegisterTest("transport v2 callbacks run after traversal and survive exceptions and state replacement", function()
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

QT:RegisterTest("transport v2 ownership cancellation and world transitions cannot release old work", function()
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

QT:RegisterTest("transport v2 departure is best effort within the same budget and never retries", function()
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
end)

QT:RegisterTest("transport v2 admission validates packets and retains only bounded primitive metrics", function()
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

QT:RegisterTest("transport v2 eligibility callbacks cannot resurrect their own cancelled packet", function()
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
	"transport v2 rejected native and channel errors settle once without blocking unrelated work",
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
		local _, _, failed = a:QueueTransportWire(
			"channel",
			"test",
			{ distribution = "CHANNEL", channelName = "QTTest", requiresChannelJoin = true }
		)
		assert(a:Queue("unrelated"))
		a:Advance(1)
		Equal(failed.status, "rejected")
		Equal(#a.sent, 2)
		Equal(a.sent[2].wire, "unrelated")
		Equal(a:GetTransportMetrics().rejected, 2)
	end
)
