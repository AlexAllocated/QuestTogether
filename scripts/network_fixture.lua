-- Private peers, frames, clocks and a queued network. Safe in live /qt test:
-- no engine globals are patched and no live addon state is inherited.
local QT = _G.QuestTogether
local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in pairs(value) do
		result[key] = Copy(item)
	end
	return result
end
local function Noop() end

function QT:CreateTestNetwork(options)
	options = options or {}
	local network = {
		now = options.now or 100,
		tick = 0,
		sequence = 0,
		fps = options.fps or 60,
		seed = options.seed or 1,
		latency = options.latency or 0.05,
		joinDelay = options.joinDelay or 0.1,
		peers = {},
		byName = {},
		pending = {},
		trace = {},
		metrics = { attempts = 0, accepted = 0, delivered = 0, dropped = 0, acceptedBytes = 0 },
	}
	function network:Random(low, high)
		-- Park-Miller stays exactly representable under Lua 5.1/5.2 doubles.
		self.seed = (self.seed * 16807) % 2147483647
		if not low then
			return (self.seed - 1) / 2147483646
		end
		if not high then
			low, high = 1, low
		end
		return low + self.seed % (high - low + 1)
	end
	function network:SetFPS(fps)
		assert(type(fps) == "number" and fps > 0)
		self.fps = fps
	end
	function network:Record(kind, packet, peer)
		self.trace[#self.trace + 1] = { kind = kind, at = self.now, packet = packet, peer = peer and peer.name }
		if self.metrics[kind] then
			self.metrics[kind] = self.metrics[kind] + 1
		end
	end
	function network:After(peer, delay, callback)
		assert(type(callback) == "function")
		self.sequence = self.sequence + 1
		local row = {
			due = self.now + math.max(0, delay),
			earliestTick = self.tick + 1,
			sequence = self.sequence,
			callback = callback,
		}
		peer.timers[#peer.timers + 1] = row
		return row
	end
	function network:CreateFrame(peer)
		local frame = { scripts = {}, events = {}, shown = true }
		function frame:IsForbidden()
			return self.forbidden == true
		end
		function frame:IsProtected()
			return self.protected == true
		end
		function frame:SetScript(event, callback)
			self.scripts[event] = callback
		end
		function frame:GetScript(event)
			return self.scripts[event]
		end
		function frame:RegisterEvent(event)
			self.events[event] = true
		end
		function frame:UnregisterEvent(event)
			self.events[event] = nil
		end
		function frame:UnregisterAllEvents()
			self.events = {}
		end
		function frame:Show()
			self.shown = true
		end
		function frame:Hide()
			self.shown = false
		end
		function frame:IsShown()
			return self.shown
		end
		function frame:IsVisible()
			return self.shown
		end
		peer.frames[#peer.frames + 1] = frame
		return frame
	end
	function network:Emit(peer, event, ...)
		for _, frame in ipairs(peer.frames) do
			if frame.events[event] and frame.scripts.OnEvent then
				frame.scripts.OnEvent(frame, event, ...)
			end
		end
	end
	function network:Join(peer, channel, immediate)
		if peer.joined[channel] or peer.joining[channel] then
			return
		end
		local token = {}
		peer.joining[channel] = token
		local function Ready()
			if peer.connected and peer.joining[channel] == token then
				peer.nextChannelID = peer.nextChannelID + 1
				peer.joined[channel], peer.joining[channel] = peer.nextChannelID, nil
			end
		end
		if immediate then
			Ready()
		else
			self:After(peer, peer.joinDelay or self.joinDelay, Ready)
		end
	end
	function network:Leave(peer, channel)
		peer.joined[channel], peer.joining[channel] = nil, nil
	end
	function network:SetGroup(peer, group, distribution)
		peer.group, peer.groupDistribution = group, distribution or "PARTY"
		for _, actor in ipairs(self.peers) do
			actor.partyMembers, actor.partyMemberOrder = {}, {}
			if actor.group then
				for _, member in ipairs(self.peers) do
					if member.group == actor.group and member.connected then
						actor.partyMembers[member.name] = { name = member.name, classFile = "MAGE" }
						actor.partyMemberOrder[#actor.partyMemberOrder + 1] = member.name
					end
				end
			end
			table.sort(actor.partyMemberOrder)
			actor.partyRosterFingerprint = table.concat(actor.partyMemberOrder, "|")
		end
	end
	function network:SetQuestLog(peer, rows)
		peer.questLog = Copy(rows)
		local function Find(id)
			for index, row in ipairs(peer.questLog) do
				if row.questID == id then
					return row, index
				end
			end
		end
		peer.API.GetNumQuestLogEntries = function()
			return #peer.questLog, #peer.questLog
		end
		peer.API.GetQuestLogInfo = function(index)
			local row = Copy(peer.questLog[index])
			if row then
				row.isHeader, row.isHidden = row.isHeader == true, row.isHidden == true
			end
			return row
		end
		peer.API.GetQuestLogIndexForQuestID = function(id)
			local _, index = Find(id)
			return index
		end
		peer.API.IsOnQuest = function(id)
			return Find(id) ~= nil
		end
		peer.API.IsQuestComplete = function(id)
			local row = Find(id)
			return row and row.isComplete == true or false
		end
		peer.API.IsPushableQuest = function(id)
			local row = Find(id)
			return row and row.isPushable ~= false or false
		end
	end
	function network:IsRecipient(packet, receiver)
		if not receiver.connected then
			return false
		end
		if packet.route == "WHISPER" then
			return receiver.name == packet.target
		end
		if packet.route == "CHANNEL" then
			return packet.channel and receiver.joined[packet.channel] ~= nil
		end
		return packet.group ~= nil and receiver.group == packet.group and receiver.groupDistribution == packet.route
	end
	function network:QueueDelivery(packet, receiver, policy)
		policy = policy or {}
		if policy.drop then
			self:Record("dropped", packet, receiver)
			return
		end
		local copies = policy.copies or 1
		assert(copies >= 1 and copies <= 10)
		for index = 1, copies do
			self.sequence = self.sequence + 1
			self.pending[#self.pending + 1] = {
				packet = packet,
				receiver = receiver,
				due = self.now + (policy.delay or self.latency) + (index - 1) * (policy.copyDelay or 0),
				earliestTick = self.tick + 1,
				sequence = self.sequence,
			}
		end
	end
	function network:NativeSend(peer, prefix, wire, route, target)
		assert(type(prefix) == "string" and #prefix <= 16, "native addon prefix limit")
		assert(type(wire) == "string" and #wire <= 255 and not wire:find("\0", 1, true), "native wire limit")
		local packet = {
			sender = peer.name,
			prefix = prefix,
			wire = wire,
			route = route,
			target = target,
			group = peer.group,
			at = self.now,
		}
		if route == "CHANNEL" then
			for channel, id in pairs(peer.joined) do
				if id == target then
					packet.channel = channel
				end
			end
		end
		self:Record("attempts", packet, peer)
		peer.attempts[#peer.attempts + 1] = packet
		local result, ambiguousDelivery = 0, false
		if not peer.connected or (route == "CHANNEL" and not packet.channel) then
			result = false
		end
		if result == 0 and self.sendRule then
			-- A ChannelThrottle result does not say whether the server submitted
			-- the packet. Tests must be able to exercise both outcomes independently
			-- of the native return code, just as acceptance can still suffer loss.
			result, ambiguousDelivery = self.sendRule(packet, #peer.attempts, peer)
		end
		packet.result = result
		local accepted = result == 0 or result == true
		if not accepted and not (result == 8 and ambiguousDelivery == true) then
			return result
		end
		if accepted then
			self:Record("accepted", packet, peer)
			self.metrics.acceptedBytes = self.metrics.acceptedBytes + #wire
		else
			self:Record("ambiguous", packet, peer)
		end
		peer.sent[#peer.sent + 1] = packet
		for _, receiver in ipairs(self.peers) do
			if self:IsRecipient(packet, receiver) then
				local policy = self.deliveryRule and self.deliveryRule(packet, receiver) or nil
				self:QueueDelivery(packet, receiver, policy)
			end
		end
		return result
	end
	function network:Inject(receiver, prefix, wire, route, sender, options)
		options = options or {}
		local packet = {
			prefix = prefix,
			wire = wire,
			route = route,
			sender = sender,
			target = receiver.name,
			channel = options.channel,
			group = options.group,
			injected = true,
		}
		self:QueueDelivery(packet, receiver, options)
	end
	function network:Step(delta)
		delta = delta or 1 / self.fps
		assert(delta > 0)
		self.tick, self.now = self.tick + 1, self.now + delta
		local frameCallbacks = {}
		for _, peer in ipairs(self.peers) do
			peer.now = self.now + peer.clockOffset
			frameCallbacks[peer] = {}
			for _, frame in ipairs(peer.frames) do
				if frame.shown and frame.scripts.OnUpdate then
					frameCallbacks[peer][#frameCallbacks[peer] + 1] = { frame, frame.scripts.OnUpdate }
				end
			end
		end
		-- Delivery never occurs inside SendAddonMessage, even at zero latency.
		local pending = self.pending
		self.pending = {}
		table.sort(pending, function(a, b)
			return a.due < b.due or (a.due == b.due and a.sequence < b.sequence)
		end)
		for _, row in ipairs(pending) do
			if row.due <= self.now + 1e-9 and row.earliestTick <= self.tick then
				local packet, receiver = row.packet, row.receiver
				if receiver.connected and (packet.injected or self:IsRecipient(packet, receiver)) then
					self:Record("delivered", packet, receiver)
					receiver.received[#receiver.received + 1] = packet
					receiver:OnCommReceived(
						packet.prefix,
						packet.wire,
						packet.route,
						packet.sender,
						packet.channel and receiver.joined[packet.channel],
						packet.channel
					)
				else
					self:Record("dropped", packet, receiver)
				end
			else
				self.pending[#self.pending + 1] = row
			end
		end
		for _, peer in ipairs(self.peers) do
			if peer.connected then
				local timers = peer.timers
				peer.timers = {}
				table.sort(timers, function(a, b)
					return a.due < b.due or (a.due == b.due and a.sequence < b.sequence)
				end)
				for _, timer in ipairs(timers) do
					if timer.due <= self.now + 1e-9 and timer.earliestTick <= self.tick then
						timer.callback()
					else
						peer.timers[#peer.timers + 1] = timer
					end
				end
				for _, row in ipairs(frameCallbacks[peer]) do
					if row[1].shown and row[1].scripts.OnUpdate == row[2] then
						row[2](row[1], delta)
					end
				end
			end
		end
	end
	function network:Advance(seconds)
		assert(type(seconds) == "number" and seconds >= 0)
		local finish = self.now + seconds
		while self.now < finish - 1e-9 do
			self:Step(math.min(1 / self.fps, finish - self.now))
		end
	end
	function network:AddPeer(name, settings)
		settings = settings or {}
		assert(type(name) == "string" and not self.byName[name])
		local peer = setmetatable({
			name = name,
			isEnabled = true,
			hasLoggedIn = true,
			isRunningTests = true,
			connected = true,
			now = self.now + (settings.clockOffset or 0),
			clockOffset = settings.clockOffset or 0,
			serverOffset = settings.serverOffset or 0,
			timers = {},
			frames = {},
			sent = {},
			attempts = {},
			received = {},
			joined = {},
			joining = {},
			nextChannelID = #self.peers * 20,
			ignored = {},
			partyMembers = {},
			partyMemberOrder = {},
			partyRosterFingerprint = "",
			recentCommMessageSignatures = {},
			mapID = settings.mapID or 12,
			position = { x = settings.x or 0.4, y = settings.y or 0.6 },
			viewedMap = settings.viewedMap,
			restricted = false,
			regional = settings.regional == true,
			commPrefix = QT.commPrefix,
			announcementChannelName = "QuestTogether",
			LibChev = QT.LibChev,
			DEFAULTS = QT.DEFAULTS,
			runtimeWorkDelayByClass = Copy(QT.runtimeWorkDelayByClass),
			db = { profile = Copy(QT.DEFAULTS.profile), global = { questTrackers = {} } },
			apiCalls = {},
			output = {},
		}, {
			__index = function(_, key)
				local value = QT[key]
				if type(value) == "function" then
					return value
				end
			end,
		})
		peer.API = {}
		for key, value in pairs(QT.API) do
			if type(value) == "function" then
				peer.API[key] = Noop
			end
		end
		local function Read(key, value)
			peer.apiCalls[key] = (peer.apiCalls[key] or 0) + 1
			return value
		end
		peer.API.GetTime = function()
			return peer.now
		end
		peer.API.GetServerTime = function()
			return math.floor(1800000000 + self.now + peer.serverOffset)
		end
		peer.API.GetFramerate = function()
			return self.fps
		end
		peer.API.IsWorldMapVisible = function()
			return peer.mapOpen == true
		end
		peer.API.Random = function(low, high)
			return self:Random(low, high)
		end
		peer.API.Delay = function(delay, callback)
			return self:After(peer, delay, callback)
		end
		peer.API.GetRealmName = function()
			return "Realm"
		end
		peer.API.RegionalUniqueNamesEnabled = function()
			return peer.regional
		end
		peer.API.GetBestMapForUnit = function()
			return Read("map", peer.mapID)
		end
		peer.API.GetPlayerMapPosition = function()
			return Read("position", Copy(peer.position))
		end
		peer.API.GetMapInfo = function(id)
			return { mapID = id, mapType = id == 99 and 2 or 3, parentMapID = 99 }
		end
		peer.API.UnitClass = function()
			return "Mage", "MAGE"
		end
		peer.API.UnitRace = function()
			return "Human", "Human", 1
		end
		peer.API.UnitLevel = function()
			return 60
		end
		peer.API.GetFaction = function()
			return "Alliance"
		end
		peer.API.IsWarModeActive = function()
			return false
		end
		peer.API.IsWarModeFeatureEnabled = function()
			return true
		end
		peer.API.IsInInstance = function()
			return false, "none"
		end
		peer.API.IsInParty = function()
			return peer.group ~= nil
		end
		peer.API.IsInGroup = peer.API.IsInParty
		peer.API.IsInRaid = function()
			return peer.group and peer.groupDistribution == "RAID" or false
		end
		peer.API.GetPartyJoinInfo = function()
			return peer.group ~= nil, true, #peer.partyMemberOrder, false
		end
		peer.API.IsOnIgnoredList = function(target)
			return peer.ignored[target] == true
		end
		peer.API.GetChannelName = function(channel)
			return peer.joined[channel]
		end
		peer.API.JoinPermanentChannel = function(channel)
			self:Join(peer, channel)
		end
		peer.API.LeaveChannelByName = function(channel)
			self:Leave(peer, channel)
		end
		peer.API.SendAddonMessage = function(...)
			return self:NativeSend(peer, ...)
		end
		function peer:GetPlayerFullName()
			return self.name
		end
		function peer:GetPlayerName()
			return self.name
		end
		function peer:GetPlayerClassFile()
			return "MAGE"
		end
		function peer:GetCurrentCharacterKey()
			return self.name
		end
		function peer:GetAddonVersion()
			return settings.version or "7.0.0"
		end
		function peer:IsRuntimeRestricted()
			return self.restricted
		end
		function peer:IsRuntimeRestrictionTypeActive()
			return self.restricted
		end
		function peer:GetViewedQuestTogetherMapID()
			return self.viewedMap
		end
		function peer:CreateRuntimeCoordinatorFrame()
			return network:CreateFrame(self)
		end
		peer.CreateMapWorkWakeFrame = peer.CreateRuntimeCoordinatorFrame
		peer.CreateRuntimeUIWorkFrame = peer.CreateRuntimeCoordinatorFrame
		function peer:Print(text)
			self.output[#self.output + 1] = text
		end
		-- Presentation boundaries only: domain producers, admission and transport remain real.
		for _, method in ipairs({
			"Debug",
			"Debugf",
			"ObserveAddonVersion",
			"RefreshPlayerLocationPins",
			"HidePlayerLocationPins",
			"RefreshQTPlayerPlatePresence",
			"RefreshQTPlayerPartnerIndicators",
			"RefreshPartyWaypointPins",
			"UpdatePlayerTooltipBadge",
			"UpdateChatLogPlayerTooltip",
			"HidePlayerTooltipBadge",
			"HideChatLogPlayerTooltip",
			"RefreshNearbyStreamPins",
			"RegisterAnnouncementChannelChatFilters",
			"HideAnnouncementChannelFromChatWindows",
			"ScheduleAnnouncementChannelOrder",
			"GetPlayerLocationPriorityOrigin",
			"GetLocationPinSurface",
			"RenderPartyChatReminder",
			"QueuePartyJoinPrompt",
			"RenderPartyQuestCompare",
			"GetQuestFocusEditManager",
			"GetHoveredTrackerQuestID",
		}) do
			peer[method] = Noop
		end
		self.peers[#self.peers + 1], self.byName[name] = peer, peer
		self:SetGroup(peer, settings.group, settings.distribution)
		return peer
	end
	function network:StartPeer(peer)
		peer:EnsureRuntimeStateStore()
		if peer.InitializeCommunications then
			peer:InitializeCommunications()
		end
		peer:InitializeGeographicComms()
		peer:InitializePlayerLocations()
		assert(peer:InitializeRuntimeCoordinator())
		return peer
	end
	return network
end
