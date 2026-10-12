-- Optional developer feed. Normal announcements retain their routes and
-- identity; this feature only supplies additional, consent-bound audiences.
local QT = _G.QuestTogether
local LEASE_SECONDS, RENEW_SECONDS, REOFFER_SECONDS = 240, 90, 10
local MAX_SUBSCRIBERS, MAX_COPIES = 4, 4
local PACKETS_PER_SECOND, PACKET_BURST, PACKETS_PER_FRAME = 32, 16, 8

local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end
local function Jitter(a, low, high)
	return a:SafeToNumber(a.API.Random and a.API.Random(low, high)) or low
end
local function Count(s, key)
	s.metrics[key] = (s.metrics[key] or 0) + 1
end
local function Current(a, s)
	return rawget(a, "developerAnnouncementState") == s
		and a.isEnabled
		and not a.isLoggingOut
		and rawget(a, "communicationState") == s.communication
		and not s.communication.departing
end
local function Sharing(a)
	return a:GetOption("shareDeveloperDiagnostics") == true
end
local function GlobalRoute(a)
	return { { distribution = "CHANNEL", channelName = a.announcementChannelName } }
end

function QT:IsDeveloperAnnouncementReceiver()
	return self.isEnabled
		and not self.isLoggingOut
		and rawget(self, "isLocalDeveloper") == true
		and type(rawget(self, "SignDeveloperRequest")) == "function"
end

function QT:InitializeDeveloperAnnouncements()
	local s = rawget(self, "developerAnnouncementState")
	if s then
		return s
	end
	local now = Now(self)
	s = {
		communication = self:InitializeCommunications(),
		startedAt = now,
		nextTick = now,
		helloAt = now + Jitter(self, 2, 8),
		subscribers = {},
		generation = 0,
		pendingCopies = 0,
		metrics = {},
		sharing = Sharing(self),
		packetAt = now,
		packetTokens = PACKET_BURST,
		framePackets = 0,
		-- A fresh signed offer must sort after a same-second previous login.
		nextOfferAttempt = now + 2,
	}
	self.developerAnnouncementState = s
	return s
end

function QT:GetDeveloperAnnouncementMetrics()
	local s = rawget(self, "developerAnnouncementState")
	local result = { subscribers = 0, pendingCopies = 0 }
	if not s then
		return result
	end
	for key, value in pairs(s.metrics) do
		result[key] = value
	end
	result.pendingCopies = s.pendingCopies
	for _, lease in pairs(s.subscribers) do
		if self:IsDeveloperAnnouncementRouteCurrent({ target = lease.sender, developerAnnouncement = lease }) then
			result.subscribers = result.subscribers + 1
		end
	end
	return result
end

function QT:RemoveDeveloperAnnouncementSubscriber(sender, departure)
	local s = rawget(self, "developerAnnouncementState")
	local lease = s and s.subscribers[sender]
	if not lease then
		return
	end
	if departure and (departure.session ~= lease.session or departure.sequence <= lease.envelopeSequence) then
		return
	end
	-- Keep the signed ordering watermark until replay validity has elapsed.
	lease.active = false
	self:CancelTransportOwner(lease, "cancelled")
	self:CancelCommTransferOwner(lease, "cancelled")
end

function QT:ResetDeveloperAnnouncementSubscriptions()
	local s = rawget(self, "developerAnnouncementState")
	if not s then
		return
	end
	s.generation = s.generation + 1
	for sender in pairs(s.subscribers) do
		self:RemoveDeveloperAnnouncementSubscriber(sender)
	end
	s.subscribers = {}
	s.helloSent = false
	s.helloAt = math.max(s.helloAt, Now(self) + Jitter(self, 2, 8))
end

function QT:CancelIgnoredDeveloperAnnouncements()
	local s = rawget(self, "developerAnnouncementState")
	for sender in pairs(s and s.subscribers or {}) do
		if self:IsIgnoredPlayerName(sender) then
			self:RemoveDeveloperAnnouncementSubscriber(sender)
		end
	end
end

function QT:ResetDeveloperAnnouncements()
	local s = rawget(self, "developerAnnouncementState")
	if not s then
		return
	end
	self:ResetDeveloperAnnouncementSubscriptions()
	self.developerAnnouncementState = nil
	self:CancelTransportOwner(s, "cancelled")
	self:CancelCommTransferOwner(s, "cancelled")
end

function QT:IsDeveloperAnnouncementRouteCurrent(route)
	local s = rawget(self, "developerAnnouncementState")
	local lease = route.developerAnnouncement
	return s ~= nil
		and Current(self, s)
		and Sharing(self)
		and type(lease) == "table"
		and s.subscribers[route.target] == lease
		and lease.active
		and Now(self) < lease.expires
		and not self:IsIgnoredPlayerName(route.target)
end

function QT:GetDeveloperAnnouncementRoutes()
	local s = rawget(self, "developerAnnouncementState")
	local routes = {}
	if not s or not Current(self, s) or not Sharing(self) then
		return routes
	end
	local candidates = {}
	for sender, lease in pairs(s.subscribers) do
		local route = { distribution = "WHISPER", target = sender, developerAnnouncement = lease }
		if self:IsDeveloperAnnouncementRouteCurrent(route) then
			candidates[#candidates + 1] = route
		end
	end
	table.sort(candidates, function(a, b)
		return a.target < b.target
	end)
	local cursor = s.subscriberCursor or 0
	for index = 1, #candidates do
		if s.pendingCopies + #routes < MAX_COPIES then
			routes[#routes + 1] = candidates[(cursor + index - 1) % #candidates + 1]
		else
			Count(s, "capacitySkipped")
		end
	end
	if #candidates > 0 then
		s.subscriberCursor = (cursor + #routes) % #candidates
	end
	return routes
end

function QT:ConfigureDeveloperAnnouncementDelivery(route, descriptor)
	local s = rawget(self, "developerAnnouncementState")
	local lease = route.developerAnnouncement
	descriptor.priority, descriptor.owner = "background", lease
	descriptor.expires = math.min(descriptor.expires, lease.expires)
	s.pendingCopies = s.pendingCopies + 1
	Count(s, "queued")
	local complete = descriptor.onComplete
	local finished = false
	descriptor.onComplete = function(ok, reason, code, ticket)
		if finished then
			return
		end
		finished = true
		s.pendingCopies = math.max(0, s.pendingCopies - 1)
		local key = ok and "accepted"
			or reason == "expired" and "expired"
			or reason == "cancelled" and "cancelled"
			or reason == "ambiguous" and "ambiguous"
			or "rejected"
		Count(s, key)
		complete(ok, reason, code, ticket)
	end
end

function QT:HandleDeveloperAnnouncementHello(_, _, context)
	if not self:IsDeveloperAnnouncementReceiver() then
		return false
	end
	local s = self:InitializeDeveloperAnnouncements()
	local now, server = Now(self), self:GetAnnouncementServerTime()
	if not server or not context.stamp or math.abs(server - context.stamp) > 30 then
		return false
	end
	-- One coalesced broadcast reuses the cached signed envelope. Existing peers
	-- suppress it by signed request identity before repeating verification.
	if not s.reofferAt then
		s.reofferAt = math.max(now + Jitter(self, 1, 3), (s.lastOfferAt or 0) + REOFFER_SECONDS)
	end
	Count(s, "hellosReceived")
	return true
end

function QT:HandleDeveloperAnnouncementSubscription(record, sender, context)
	if not Sharing(self) or record.subscriptionSession ~= context.session then
		return false
	end
	local s = self:InitializeDeveloperAnnouncements()
	local known = s.subscribers[sender]
	if known and known.requestId == record.requestId then
		Count(s, "duplicateSubscriptions")
		return true
	end
	local generation = s.generation
	return self:QueueDeveloperAnnouncementVerification(record, sender, function(verified)
		if verified.cancelled or not Current(self, s) or generation ~= s.generation or not Sharing(self) then
			return
		end
		local server, now = self:GetAnnouncementServerTime(), Now(self)
		local remaining = server and verified.issuedAt + LEASE_SECONDS - server or 0
		if remaining <= 0 then
			return
		end
		local sampledAt = now - math.max(0, server - verified.issuedAt)
		if
			not self:CanAcceptPeerEpoch(sender, context.session, verified.issuedAt)
			or not self:CanAcceptPeerUpdate(sender, nil, sampledAt, context.session, context.sequence)
		then
			return
		end
		local sequence = tonumber(verified.requestId:match("%-(%d+)$")) or 0
		local old = s.subscribers[sender]
		if
			old
			and (
				verified.issuedAt < old.issuedAt
				or (
					verified.issuedAt == old.issuedAt
					and (old.session ~= verified.subscriptionSession or sequence <= old.sequence)
				)
			)
		then
			return
		end
		if not old then
			local count = 0
			for _ in pairs(s.subscribers) do
				count = count + 1
			end
			if count >= MAX_SUBSCRIBERS then
				Count(s, "subscriptionsRejected")
				return
			end
		else
			self:RemoveDeveloperAnnouncementSubscriber(sender)
		end
		s.subscribers[sender] = {
			sender = sender,
			active = verified.active,
			issuedAt = verified.issuedAt,
			sequence = sequence,
			requestId = verified.requestId,
			session = verified.subscriptionSession,
			envelopeSequence = context.sequence,
			expires = now + math.min(LEASE_SECONDS, remaining),
			retireAt = now + 330,
		}
		self:RecordPeerEpoch(sender, context.session, verified.issuedAt)
		self:RecordPeerUpdate(sender, "DEVANN", sampledAt, context.session, context.sequence, false)
		Count(s, "subscriptionsVerified")
	end)
end

-- This is a QT processing limit, not a claimed server limit. Dropping extra
-- copies before shared ingress leaves ordinary announcements and party replies
-- their normal allowance; incoming partial objects have a separate small cap.
function QT:AdmitDeveloperAnnouncementPacket()
	local s = rawget(self, "developerAnnouncementState")
	if not s then
		return true
	end
	local now = Now(self)
	s.packetTokens = math.min(PACKET_BURST, s.packetTokens + math.max(0, now - s.packetAt) * PACKETS_PER_SECOND)
	s.packetAt = now
	if s.framePackets >= PACKETS_PER_FRAME or s.packetTokens < 1 then
		Count(s, "ingressDropped")
		return false
	end
	s.framePackets, s.packetTokens = s.framePackets + 1, s.packetTokens - 1
	Count(s, "receivedPackets")
	return true
end

function QT:UpdateDeveloperAnnouncements(now)
	local s = rawget(self, "developerAnnouncementState")
	if not s or not Current(self, s) then
		return
	end
	s.framePackets = 0
	if now < s.startedAt then
		self:ResetDeveloperAnnouncements()
		return
	end
	if now < s.nextTick then
		return
	end
	s.nextTick = now + 1
	local sharing = Sharing(self)
	if s.sharing ~= sharing then
		s.sharing = sharing
		if sharing then
			s.helloSent = false
			s.helloAt = math.max(s.helloAt, now + Jitter(self, 2, 8))
		else
			self:ResetDeveloperAnnouncementSubscriptions()
		end
	end
	for sender, lease in pairs(s.subscribers) do
		if lease.active and (now >= lease.expires or not Sharing(self) or self:IsIgnoredPlayerName(sender)) then
			self:RemoveDeveloperAnnouncementSubscriber(sender)
		end
		if now >= lease.retireAt then
			s.subscribers[sender] = nil
		end
	end
	if not self:GetAnnouncementChannelLocalID(self.announcementChannelName) then
		return
	end
	if not s.helloSent and not s.helloPending and now >= s.helloAt then
		s.helloPending, s.helloAt = true, now + 15
		local ok = self:Emit("HELLO", { version = self:GetAddonVersion() }, GlobalRoute(self), {
			owner = s,
			expires = now + 30,
			isCurrent = function()
				return Current(self, s)
			end,
			onComplete = function(accepted, reason)
				if Current(self, s) then
					s.helloPending = false
					s.helloSent = accepted or reason == "ambiguous"
				end
			end,
		})
		if not ok then
			s.helloPending = false
		end
	end
	if not self:IsDeveloperAnnouncementReceiver() then
		s.subscription, s.offerContext, s.reofferAt = nil, nil, nil
		return
	end
	if s.offerPending or now < (s.nextOfferAttempt or 0) then
		return
	end
	local renew = not s.subscription or now >= s.renewAt
	if not renew and (not s.reofferAt or now < s.reofferAt) then
		return
	end
	s.nextOfferAttempt = now + REOFFER_SECONDS
	if renew then
		s.subscription = self:PrepareDeveloperAnnouncementSubscription({
			active = true,
			subscriptionSession = s.communication.session,
		})
		s.offerContext = nil
		if not s.subscription then
			Count(s, "signingFailed")
			return
		end
		s.renewAt = now + RENEW_SECONDS
	end
	s.offerPending, s.reofferAt, s.lastOfferAt = true, nil, now
	local ok, _, envelope = self:Emit("DEVANN", s.subscription, GlobalRoute(self), {
		owner = s,
		expires = now + 30,
		retryContext = s.offerContext,
		isCurrent = function()
			return Current(self, s) and self:IsDeveloperAnnouncementReceiver()
		end,
		onComplete = function(accepted, reason)
			if Current(self, s) then
				s.offerPending = false
				if not accepted and reason ~= "ambiguous" then
					s.reofferAt = Now(self) + REOFFER_SECONDS
				end
			end
		end,
	})
	if ok then
		s.offerContext = envelope
		Count(s, renew and "subscriptionsSent" or "subscriptionsReoffered")
	else
		s.offerPending, s.reofferAt = false, now + REOFFER_SECONDS
	end
end
