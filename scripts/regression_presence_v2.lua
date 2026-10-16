-- Explicit typed observation supplied at the private receive boundary.
-- Short per-field lifetimes exercise expiry boundaries; public v2 snapshots use 600 seconds.
local function ObserveState(addon, method, field, record, sender)
	local lifetimes = { QTLF = 65, QTLQ = 65, QTVR = 180, QTPG = 180, QJST = 125, QTHI = 180 }
	local observation = addon:CreatePeerObservation(sender, field, {
		source = "snapshot",
		lifetime = lifetimes[field] or 600,
		session = type(record) == "table" and record.session or nil,
		sequence = type(record) == "table" and record.sequence or nil,
	})
	return addon[method](addon, record, sender, observation)
end

-- Typed domain regressions use only private addon instances and queued delivery.
local QT = _G.QuestTogether
local function Check(value, message)
	assert(value, message)
end
local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end
local function Fixture()
	local a = setmetatable({
		isEnabled = true,
		now = 100,
		seq = 0,
		queue = {},
		locations = {},
		ignored = {},
		currentMap = 1,
		options = { showPlayerLocations = true, lookingForQuestPartners = false },
		sharing = true,
		announcementChannelName = "QuestTogether",
		channels = { QuestTogether = 1 },
		partyRosterFingerprint = "solo",
		sample = { mapID = 1, x = 0.4, y = 0.5 },
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.now
		end,
		Random = function(low)
			return low
		end,
		GetBestMapForUnit = function()
			return a.currentMap
		end,
		GetMapInfo = function(id)
			return { mapType = 3, parentMapID = 0 }
		end,
		GetPlayerRaceID = function()
			return 2
		end,
		LeaveChannelByName = function(name)
			a.channels[name] = nil
		end,
		UnitClass = function()
			return "Warrior", "WARRIOR"
		end,
		UnitRace = function()
			return "Orc"
		end,
		UnitLevel = function()
			return 20
		end,
		GetFaction = function()
			return "Horde"
		end,
	}
	function a:SafeToNumber(v)
		local n = tonumber(v)
		if n and n == n then
			return n
		end
	end
	function a:SafeToString(v, d)
		return type(v) == "string" and v or d
	end
	function a:SafeTrimString(v, d)
		return self:SafeToString(v, d):match("^%s*(.-)%s*$")
	end
	function a:CanAccessValue()
		return true
	end
	function a:CanAccessTable(v)
		return type(v) == "table"
	end
	function a:IsRuntimeRestricted()
		return self.restricted
	end
	function a:IsRuntimeRestrictionTypeActive()
		return false
	end
	function a:GetOption(k)
		return self.options[k]
	end
	function a:CanPublishPlayerLocation()
		return self.sharing
	end
	function a:NormalizeMemberName(v)
		return v
	end
	function a:IsSelfSender(n)
		return n == "Self"
	end
	function a:IsIgnoredPlayerName(n)
		return self.ignored[n]
	end
	function a:GetAnnouncementServerTime()
		return 1700000000 + self.now
	end
	function a:GetCommunicationSession()
		return "1700000000-123"
	end
	function a:NextCommunicationSequence()
		self.seq = self.seq + 1
		return self.seq
	end
	function a:GetAnnouncementChannelLocalID(n)
		return self.channels[n]
	end
	function a:EnsureAnnouncementChannelJoined(n)
		self.channels[n] = Count(self.channels) + 1
		return true
	end
	function a:ScheduleAnnouncementChannelOrder() end
	function a:GetViewedQuestTogetherMapID()
		return self.viewedMap
	end
	function a:GetGroupAnnouncementDistribution()
		return self.group
	end
	function a:BroadcastPlayerLocation(share)
		local r = { mask = share and 3 or 0 }
		if share then
			for k, v in pairs(self.sample) do
				r[k] = v
			end
		end
		self:StageCommunicationState("LOC", r)
		return true, self.sample
	end
	function a:Complete(row, sent, reason)
		if row.done then
			return
		end
		row.done = true
		if row.options.onComplete then
			row.options.onComplete(sent, reason or (sent and "accepted" or "rejected"))
		end
	end
	function a:Emit(op, record, routes, options)
		options = options or {}
		local row = { operation = op, data = record, routes = routes, options = options }
		if self.reject then
			return false
		end
		for _, old in ipairs(self.queue) do
			if not old.done and options.key and old.options.key == options.key then
				self:Complete(old, false, "superseded")
			end
		end
		self.queue[#self.queue + 1] = row
		return true, "queued", row
	end
	function a:Publish(op, record, routes, options)
		if routes then
			return self:Emit(op, record, routes, options)
		end
		return self:StageCommunicationState(op, record, options)
	end
	function a:CancelCommunicationOwner(owner, reason)
		for _, row in ipairs(self.queue) do
			if not row.done and row.options.owner == owner then
				self:Complete(row, false, reason)
			end
		end
	end
	function a:CancelCommunicationWhere(predicate)
		for _, row in ipairs(self.queue) do
			if not row.done and predicate(row.options) then
				self:Complete(row, false, "cancelled")
			end
		end
	end
	function a:Rows(op, channel)
		local rows = {}
		for _, row in ipairs(self.queue) do
			if
				not row.done
				and (not op or row.operation == op)
				and (not channel or row.routes[1].channelName == channel)
			then
				rows[#rows + 1] = row
			end
		end
		return rows
	end
	function a:GetFreshPlayerLocation(name, surface)
		return self.locations[name]
	end
	function a:ShouldShowPlayerLocation(name)
		return not self.ignored[name]
	end
	function a:GetLocationPinSurface()
		return { width = 100, height = 100 }
	end
	function a:ProjectPlayerLocationPin(_, row)
		return row.x * 100, row.y * 100
	end
	function a:ReadLocalPlayerLocation()
		return self.sample
	end
	function a:CommitPeerObservation(o, record)
		if o.expiresAt <= self.now then
			return false
		end
		record.sampledAt, record.receivedAt, record.expiresAt = o.sampledAt, o.receivedAt, o.expiresAt
		record.lifetime = o.expiresAt - o.receivedAt
		return true
	end
	a:InitializeGeographicComms()
	return a
end
-- Zone interest, real dwell and query coalescing across separate subscriptions.
QT:RegisterTest("typed geographic discovery follows two interests and coalesces each zone independently", function()
	local a = Fixture()
	a.viewedMap = 2
	a:UpdateGeographicSubscriptions()
	Check(Count(a.geographicCommsState.subscriptions) == 1, "initial only current")
	a.now = 102
	a:UpdateGeographicSubscriptions()
	Check(Count(a.geographicCommsState.subscriptions) == 1, "view dwell")
	a:UpdateGeographicDiscovery()
	local query = a:Rows("QTDQ")[1]
	Check(query and query.data.zone == 1, "current query typed")
	Check(a.geographicCommsState.discovery[1].acceptedAt == nil, "query queued not accepted")
	a.now = 104
	a:UpdateGeographicSubscriptions()
	Check(Count(a.geographicCommsState.subscriptions) == 2, "two interests")
	a.now = 106
	a:UpdateGeographicDiscovery()
	Check(#a:Rows("QTDQ") == 2, "view query included")
	Check(
		a:HandleGeographicDiscovery(
			{ zone = 2 },
			"Other",
			{ distribution = "CHANNEL", channelName = "QuestTogetherZ2" }
		),
		"valid viewed query heard"
	)
	Check(#a:Rows("QTDQ") == 1, "coalesce matching zone only")
	Check(a.geographicCommsState.discovery[2].responseAt == nil, "remote view does not answer")
	Check(
		not a:HandleGeographicDiscovery(
			{ zone = 2 },
			"Other",
			{ distribution = "CHANNEL", channelName = "QuestTogetherZ1" }
		),
		"claimed zone route rejected"
	)
	a:Complete(query, true)
	Check(a.geographicCommsState.discovery[1].acceptedAt == 106, "query accepted timestamp")
	a.currentMap = 3
	a.viewedMap = 4
	a.now = 108
	a:UpdateGeographicSubscriptions()
	Check(Count(a.geographicCommsState.subscriptions) <= 2, "zone changes bounded")
	a.now = 112
	a:UpdateGeographicSubscriptions()
	Check(Count(a.geographicCommsState.subscriptions) == 2, "new viewed interest")
	Check(
		a.geographicCommsState.subscriptions.QuestTogetherZ3 and a.geographicCommsState.subscriptions.QuestTogetherZ4,
		"old interest retired"
	)
end)
-- Publication progress is native-accepted, per route, with finite failure retry.
QT:RegisterTest("typed geographic publication advances only after per-route native acceptance", function()
	local a = Fixture()
	a:StageCommunicationState("QTPR", { active = true })
	a:UpdateGeographicComms()
	a.now = 102
	a:UpdateGeographicComms()
	local global = a:Rows("STATE", "QuestTogether")[1]
	Check(global ~= nil, "global snapshot queued")
	Check(not a.geographicCommsState.lastGlobal, "queued does not mark publication")
	Check(global.data.records[1].sampledAt == 1700000100, "sample time preserved")
	a:Complete(global, false)
	Check(not a.geographicCommsState.lastGlobal, "failure no cadence advancement")
	a.now = 102.5
	a:UpdateGeographicComms()
	Check(#a:Rows("STATE", "QuestTogether") == 0, "failure backoff")
	a.now = 103
	a:UpdateGeographicComms()
	global = a:Rows("STATE", "QuestTogether")[1]
	Check(global ~= nil, "retry due")
	a.now = 104
	a:Complete(global, true)
	Check(a.geographicCommsState.lastGlobal == 104, "accepted marks progress")
	Check(a.geographicCommsState.nextGlobal == 254, "global cadence 150 seconds from acceptance")
	local localRow = a:Rows("STATE", "QuestTogetherZ1")[1]
	Check(localRow ~= nil, "regional independent pending")
	a.sharing = false
	a:StageCommunicationState("LOC", { mask = 0 })
	Check(localRow.done, "withdrawal cancels queued coordinates")
	a:RecordGeographicPeerLocation("Other", { mask = 3, mapID = 1 }, { expiresAt = a.now + 10 })
	Check(a:GetGeographicZonePopulation(1) == 1, "density accepted index")
	a.now = a.now + 10
	Check(a:GetGeographicZonePopulation(1) == 0, "density respects source expiry")
end)
-- Nearest peer lease and latest-only samples through ordinary coordinator.
QT:RegisterTest("typed nearby leases and latest-only samples preserve accepted progress and privacy", function()
	local a = Fixture()
	a.locations.Other = { name = "Other", mapID = 1, x = 0.4, y = 0.4, mask = 3 }
	Check(
		ObserveState(a, "HandlePlayerCapabilityMetadata", "QTCI", { streams = true, raceID = 2 }, "Other"),
		"capabilities typed"
	)
	a:UpdateNearbyStreams()
	local request = a:Rows("QTSR")[1]
	local s = a.nearbyStreamState
	Check(request and request.options.expires == 102, "lease queued TTL2")
	Check(s.wanted.Other.requestedAt == nil, "lease no premature acceptance")
	a.now = 101
	a:Complete(request, true)
	Check(s.wanted.Other.requestedAt == 101, "lease accepted time")
	Check(a:HandleNearbyStreamMessage("QTSR", { token = "other-1" }, "Other"), "reciprocal lease")
	a.now = 101.3
	a:UpdateNearbyStreams()
	local sample = a:Rows("QTSP")[1]
	Check(sample and sample.options.publishesLocation and sample.options.priority == "active", "nearby policy explicit")
	Check(s.subscribers.Other.lastSent == 0, "sample enqueue no sent timestamp")
	a.sample.x = 0.45
	a.now = 101.6
	a:UpdateNearbyStreams()
	local replacement = a:Rows("QTSP")[1]
	Check(sample.done and replacement ~= sample, "moving sample replaces queued sample")
	Check(s.subscribers.Other.lastSent == 0, "replacement cancellation no success")
	a.now = 101.7
	a:Complete(replacement, true)
	Check(s.subscribers.Other.lastSent == 101.7, "sample accepted timestamp")
	Check(s.subscribers.Other.sequence == replacement.data.sequence, "accepted sequence")
	local token = s.wanted.Other.token
	Check(
		a:HandleNearbyStreamMessage(
			"QTSP",
			{ token = token, sequence = 1, stamp = 1700000100, mapID = 1, x = 0.45, y = 0.45 },
			"Other"
		),
		"sample with preserved source age"
	)
	Check(math.abs(s.wanted.Other.sample.at - 100) < 0.00001, "sample not rejuvenated by receipt")
	a.now = 104
	Check(a:GetNearbyStreamPosition(a.locations.Other, true) == a.locations.Other, "expired sample no overlay")
	a.sample.x = 0.47
	a:UpdateNearbyStreams()
	local pending = a:Rows("QTSP")[1]
	a.sharing = false
	a:UpdateNearbyStreams()
	Check(pending and pending.done, "privacy cancels pending stream")
	Check(next(s.wanted) == nil and next(s.subscribers) == nil, "privacy clears leases")
	Check(not a:HandleNearbyStreamMessage("QTSR", { token = "other-2" }, "Other"), "hidden ignores requests")
end)
QT:RegisterTest("staged producer completion reports one accepted route and ignores failed routes", function()
	local a = Fixture()
	local completions = {}
	local function Complete(sent, reason)
		completions[#completions + 1] = { sent = sent, reason = reason }
	end
	a:StageCommunicationState("QTPG", { size = 2, leader = "Self", revision = "1" }, { onComplete = Complete })
	a:UpdateGeographicComms()
	a.now = 102
	a:UpdateGeographicComms()
	local global = a:Rows("STATE", "QuestTogether")[1]
	local regional = a:Rows("STATE", "QuestTogetherZ1")[1]
	Check(global and regional, "independent recipients")
	a:Complete(global, false, "rejected")
	Check(#completions == 0, "queue failure leaves state eligible for retry")
	a:StageCommunicationState("QTPG", { size = 2, leader = "Self", revision = "1" }, { onComplete = Complete })
	a:Complete(regional, true)
	Check(#completions == 1 and completions[1].sent, "same semantic refresh accepts captured publication")
	a.now = 103
	a:UpdateGeographicComms()
	global = a:Rows("STATE", "QuestTogether")[1]
	a:Complete(global, true)
	Check(#completions == 1, "second route cannot double complete")
	a:StageCommunicationState("QTPG", { size = 2, leader = "Self", revision = "2" }, { onComplete = Complete })
	a:StageCommunicationState("QTPG", { size = 0 }, { onComplete = Complete })
	Check(
		#completions == 2 and not completions[2].sent and completions[2].reason == "superseded",
		"replaced intent cancelled"
	)
	a:ResetGeographicComms()
	Check(#completions == 3 and not completions[3].sent, "reset retires unsent receipt")
end)

-- Full same-frame crowd-capacity stress runs offline.
QT:RegisterTest("geographic density stays bounded within a same-tick discovery burst", function()
	local a = Fixture()
	for i = 1, 2500 do
		a:RecordGeographicPeerLocation("Peer" .. i, { mask = 3, mapID = 1 }, { expiresAt = a.now + 600 })
	end
	Check(Count(a.geographicCommsState.peers) == 2048, "bounded before next pruning tick")
	Check(a:GetGeographicZonePopulation(1) == 2048, "density reports bounded active index")
	a.now = a.now + 600
	Check(a:GetGeographicZonePopulation(1) == 0, "cached density expires on original deadline")
end, { offline = true })
