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

QT:RegisterTest("transport v2 restores throttle rate only after sustained successful sending", function()
	local a = Fixture()
	a.native = function()
		return #a.sent == 1 and 3 or 0
	end
	assert(a:Queue("throttle", { expires = a.now + 500 }))
	a:Advance(1)
	a:Advance(1)
	Equal(a:GetTransportState().packetRate, 1)
	a:Advance(100)
	Equal(a:GetTransportState().packetRate, 1)
	for i = 1, 30 do
		assert(a:Queue("recover" .. i))
		a:Advance(1)
	end
	Equal(a:GetTransportState().packetRate, 1)
	assert(a:Queue("recover31"))
	a:Advance(1)
	Equal(a:GetTransportState().packetRate, 1.5)
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
	local expected = { "controlA1", "eventA1", "activeA1", "activeB1", "activeA2", "bulkA1", "bulkB1", "backgroundA1" }
	for index, wire in ipairs(expected) do
		Equal(a.sent[index].wire, wire)
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
	Equal(three.generation, 1)
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
	local count = 0
	for _, value in pairs(metrics) do
		assert(type(value) == "number" or type(value) == "table")
		count = count + 1
	end
	assert(count <= 24)
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
