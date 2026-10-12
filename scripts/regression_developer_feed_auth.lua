-- Private fixtures share the production verifier without changing live APIs.
local QT = _G.QuestTogether
local PUBLIC_KEY = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
local function Fixture(name, realCrypto)
	local a = setmetatable({
		name = name or "Friend-Realm",
		isEnabled = true,
		isLocalDeveloper = true,
		consent = true,
		now = 100,
		sequence = 0,
		developerPublicKeyHex = PUBLIC_KEY,
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.now
		end,
		Random = function()
			return 1234
		end,
	}
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetAnnouncementServerTime()
		return 1791300000 + math.floor(self.now)
	end
	function a:NextCommunicationSequence()
		self.sequence = self.sequence + 1
		return self.sequence
	end
	function a:GetOption(key)
		return key == "shareDeveloperDiagnostics" and self.consent
	end
	function a:IsIgnoredPlayerName(nameToCheck)
		return self.ignored == nameToCheck
	end
	local seed = ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"):gsub("..", function(x)
		return string.char(tonumber(x, 16))
	end)
	function a:SignDeveloperRequest(message)
		self.signedText = message
		return realCrypto and QT.Ed25519.Sign(seed, message) or string.rep("x", 64)
	end
	a.Ed25519 = realCrypto and QT.Ed25519
		or {
			NewVerification = function(_, message)
				a.verificationText = message
				return coroutine.create(function()
					coroutine.yield()
					return true
				end)
			end,
		}
	return a
end
local function Finish(a)
	local steps = 0
	while a.developerRequestState and #a.developerRequestState.jobs > 0 do
		steps = steps + 1
		assert(steps < 10000, "developer authentication failed to finish")
		a:DrainDeveloperPingVerifications()
		a.now = a.now + 0.01
	end
end
local function Subscription(dev, target)
	return assert(
		dev:PrepareDeveloperAnnouncementSubscription(
			{ active = true, subscriptionSession = "1791300000000-1234" },
			target
		)
	)
end

QT:RegisterTest("developer feed signatures retain ping domain and share unique request identities", function()
	local dev = Fixture("Dev-Realm")
	local ping = assert(dev:PrepareDeveloperPingRequest({}, "Friend-Realm", false))
	assert(dev.signedText:match("^QTDEV2\n"))
	local subscription = Subscription(dev)
	assert(dev.signedText:match("^QTDEVFEED2\n"))
	assert(subscription.requestId ~= ping.requestId and #subscription.requestId <= 64)
	assert(subscription.requesterName == "" and subscription.targetName == nil)
	assert(subscription.signature == string.rep("78", 64))
	dev.isLocalDeveloper = false
	assert(dev:PrepareDeveloperAnnouncementSubscription({ active = true, subscriptionSession = "session-1" }) == nil)
end)

QT:RegisterTest("developer feed auth validates bounded signed fields before admission", function()
	local dev, peer = Fixture("Dev-Realm"), Fixture()
	local original = Subscription(dev)
	for _, change in ipairs({
		{ "active", "yes" },
		{ "subscriptionSession", "" },
		{ "subscriptionSession", "session\nforged" },
		{ "subscriptionSession", string.rep("x", 65) },
		{ "targetName", "Another-Realm" },
		{ "issuedAt", original.issuedAt - 301 },
		{ "issuedAt", original.issuedAt + 31 },
		{ "requestId", "invalid" },
	}) do
		local copy = peer:DeepCopy(original)
		copy[change[1]] = change[2]
		assert(not peer:QueueDeveloperAnnouncementVerification(copy, dev.name, function() end), change[1])
	end
	assert(not peer:QueueDeveloperAnnouncementVerification(nil, dev.name, function() end))
	assert(rawget(peer, "developerRequestState") == nil)
	peer.consent = false
	assert(not peer:QueueDeveloperAnnouncementVerification(original, dev.name, function() end))
end)

QT:RegisterTest("developer feed authentication shares ping queue replay and sender admission bounds", function()
	local dev, peer = Fixture("Dev-Realm"), Fixture()
	local ping = assert(dev:PrepareDeveloperPingRequest({}, nil, false))
	local subscription = Subscription(dev)
	assert(peer:QueueDeveloperPingVerification(ping, dev.name, function() end))
	assert(not peer:QueueDeveloperAnnouncementVerification(subscription, dev.name, function() end))
	Finish(peer)
	local accepted
	assert(peer:QueueDeveloperAnnouncementVerification(subscription, dev.name, function(copy)
		accepted = copy
	end))
	local session = subscription.subscriptionSession
	subscription.active, subscription.subscriptionSession = false, "tampered"
	Finish(peer)
	assert(accepted.active == true and accepted.subscriptionSession == session)
	assert(accepted.developerVerified == true and accepted.developerPurpose == "announcements")
	assert(accepted.requesterName == dev.name)
	assert(not peer:QueueDeveloperAnnouncementVerification(accepted, dev.name, function() end))
	assert(not peer:QueueDeveloperPingVerification(accepted, dev.name, function() end))
	assert(peer:GetDeveloperCommunicationMetrics().verified == 2)
end)

QT:RegisterTest("developer feed pending authentication respects consent ignores and lifetime fences", function()
	for _, boundary in ipairs({ "consent", "ignore", "disable", "logout", "reset", "clock" }) do
		local dev, peer = Fixture("Dev-Realm"), Fixture()
		local called = false
		assert(peer:QueueDeveloperAnnouncementVerification(Subscription(dev), dev.name, function()
			called = true
		end))
		if boundary == "consent" then
			peer.consent = false
		elseif boundary == "ignore" then
			peer.ignored = dev.name
		elseif boundary == "disable" then
			peer.isEnabled = false
		elseif boundary == "logout" then
			peer.isLoggingOut = true
		elseif boundary == "reset" then
			peer:ResetDeveloperDiagnostics()
		else
			peer.now = peer.now - 1
		end
		peer:DrainDeveloperPingVerifications()
		assert(not called, boundary)
	end
end)

QT:RegisterTest("developer authentication cancelled by ignoring cannot resume after immediate unignore", function()
	for _, purpose in ipairs({ "ping", "announcements" }) do
		local dev, peer = Fixture("Dev-Realm"), Fixture()
		local record = purpose == "ping" and assert(dev:PrepareDeveloperPingRequest({}, nil, false))
			or Subscription(dev)
		local verify = purpose == "ping" and peer.QueueDeveloperPingVerification
			or peer.QueueDeveloperAnnouncementVerification
		local called = false
		assert(verify(peer, record, dev.name, function()
			called = true
		end))
		peer.ignored = dev.name
		peer:CancelIgnoredDeveloperRequests()
		peer.ignored = nil
		Finish(peer)
		assert(not called, purpose)
		assert(#peer.developerRequestState.jobs == 0)
		assert(peer.developerRequestState.pendingSenders[dev.name] == nil)
		assert(peer:GetDeveloperCommunicationMetrics().expired == 1)
	end
end)

-- Repeated real Ed25519 verification belongs offline, not in one live frame.
QT:RegisterTest("developer feed real signatures bind action session target sender time identity and purpose", function()
	local dev, peer = Fixture("Dev-Realm", true), Fixture("Friend-Realm", true)
	local original = Subscription(dev, peer.name)
	local called = false
	assert(peer:QueueDeveloperAnnouncementVerification(original, dev.name, function()
		called = true
	end))
	Finish(peer)
	assert(called)
	for _, field in ipairs({
		"active",
		"subscriptionSession",
		"targetName",
		"sender",
		"issuedAt",
		"requestId",
		"signature",
		"purpose",
	}) do
		peer = Fixture("Friend-Realm", true)
		local copy = peer:DeepCopy(original)
		local sender = dev.name
		if field == "active" then
			copy.active = false
		elseif field == "subscriptionSession" then
			copy.subscriptionSession = "different-1234"
		elseif field == "targetName" then
			copy.targetName = nil
		elseif field == "sender" then
			sender = "Forged-Realm"
		elseif field == "issuedAt" then
			copy.issuedAt = copy.issuedAt - 1
		elseif field == "requestId" then
			copy.requestId = copy.requestId .. "1"
		elseif field == "signature" then
			copy.signature = string.rep("0", 128)
		end
		called = false
		local verify = field == "purpose" and peer.QueueDeveloperPingVerification
			or peer.QueueDeveloperAnnouncementVerification
		assert(verify(peer, copy, sender, function()
			called = true
		end))
		Finish(peer)
		assert(not called, field)
	end
	peer = Fixture("Friend-Realm", true)
	local ping = assert(dev:PrepareDeveloperPingRequest({}, nil, false))
	ping.active, ping.subscriptionSession = true, original.subscriptionSession
	called = false
	assert(peer:QueueDeveloperAnnouncementVerification(ping, dev.name, function()
		called = true
	end))
	Finish(peer)
	assert(not called, "a signed diagnostic ping cannot authorize announcement mirroring")
end, { offline = true })
