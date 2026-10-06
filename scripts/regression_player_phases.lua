-- Private peers/observations only: safe in live /qt test, no native API patches.
local QT = _G.QuestTogether
local function Eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function Peer(name, guid, key)
	local a = setmetatable({ name = name, now = 100, isEnabled = true, sent = {}, nearby = {},
		options = { experimentalLayerDetection = true }, map = 1, guid = guid, key = key, players = {},
		geographicCommsState = { session = "100-123" } }, { __index = QT })
	a.API = { GetTime = function() return a.now end, IsInInstance = function() return a.instance == true end }
	function a:GetOption(k) return self.options[k] end
	function a:CanPublishPlayerLocation() return not self.private end
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:IsRuntimeRestrictionTypeActive() return self.chatBlocked == true end
	function a:UsesRegionalPlayerNames() return not self.retail end
	function a:NormalizeMemberName(n) return n end
	function a:IsSelfSender(n) return n == self.name end
	function a:IsIgnoredPlayerName(n) return n == self.ignored end
	function a:GetPlayerPhaseCandidates() return self.nearby end
	function a:GetPlayerPhaseObservation()
		if self.noObservation then return end
		local npcs = {}
		if self.key then
			local prefix = "Creature-0-" .. self.key:gsub(":", "-")
			npcs[prefix .. "-123-ABC"] = true
			if not self.oneNPC then npcs[prefix .. "-124-DEF"] = true end
			if self.mixed then npcs["Creature-0-1-0-999-125-AAA"] = true end
		end
		return { map = self.map, guid = self.guid, npcs = npcs, players = self:DeepCopy(self.players) }
	end
	function a:QueueGeographicWire(wire, _, route)
		assert(#wire <= 255 and route.distribution == "WHISPER")
		self.sent[#self.sent + 1] = { wire = wire, target = route.target }
		return true
	end
	return a
end
local function Pair()
	local a, b = Peer("A", "Player-1-ABC", "1:0:100"), Peer("B", "Player-1-DEF", "1:0:200")
	-- Warm observations before discovering each other, as a normal nearby arrival.
	for now = 100, 102 do
		a.now, b.now = now, now
		a:UpdatePlayerPhaseObservations(); b:UpdatePlayerPhaseObservations()
	end
	a.nearby, b.nearby = { { name = "B" } }, { { name = "A" } }
	a.now, b.now = 103, 103
	a:UpdatePlayerPhaseObservations(); b:UpdatePlayerPhaseObservations()
	return a, b
end
local function Deliver(from, to)
	local sent = from.sent; from.sent = {}
	for _, row in ipairs(sent) do
		if from:IsPlayerPhaseQueuedWireCurrent(row.wire, row.target) then
			to:HandlePlayerPhaseMessage(row.wire:sub(6), from.name)
		end
	end
end
local function Exchange(a, b) Deliver(a, b); Deliver(b, a); Deliver(a, b) end
QT:RegisterTest("experimental phases require stable multiple NPCs and timely paired whisper replies", function()
	local a, b = Pair()
	Eq(a:GetPlayerPhaseStatus("B"), nil)
	Exchange(a, b)
	Eq(a:GetPlayerPhaseStatus("B"), "different")
	Eq(b:GetPlayerPhaseStatus("A"), "different")
	Eq(a:RequestPlayerPhaseComparison("B"), false)
	a.now = 134; a:UpdatePlayerPhaseObservations()
	Eq(a:GetPlayerPhaseStatus("B"), nil)
end)
QT:RegisterTest("experimental phases never infer layers from absent players or matching NPC keys", function()
	local a, b = Pair(); b.key = a.key
	b.playerPhaseState.observation.key = a.key
	b.sent = {}; b.playerPhaseState.attempts = {}; b.playerPhaseState.lastRequest = nil
	b:RequestPlayerPhaseComparison("A")
	Exchange(a, b)
	Eq(a:GetPlayerPhaseStatus("B"), nil)
	for _, case in ipairs({ "oneNPC", "mixed", "retail" }) do
		a, b = Pair(); a[case] = true
		a.now = 104; a:UpdatePlayerPhaseObservations()
		Eq(a.playerPhaseState.observation.key, nil)
		Exchange(a, b); Eq(a:GetPlayerPhaseStatus("B"), nil)
	end
end)
QT:RegisterTest("experimental phases prefer direct visibility and shared players over NPC mismatch", function()
	local a, b = Pair(); Exchange(a, b)
	a.players[b.guid] = true; a.now = 104; a:UpdatePlayerPhaseObservations()
	Eq(a:GetPlayerPhaseStatus("B"), "visible")
	a.players = { ["Player-1-FFF"] = true }
	a.now = 105; a:UpdatePlayerPhaseObservations()
	a.playerPhaseState.peers.B.players["Player-1-FFF"] = true
	Eq(a:GetPlayerPhaseStatus("B"), "shared")
	a.players = {}; a.key = nil; a.now = 106; a:UpdatePlayerPhaseObservations()
	Eq(a:GetPlayerPhaseStatus("B"), nil)
end)
QT:RegisterTest("experimental phases clear state and queued packets on opt out privacy restrictions and instances", function()
	for _, case in ipairs({ "off", "private", "blocked", "chatBlocked", "instance" }) do
		local a, b = Pair(); local wire = a.sent[1].wire
		Exchange(a, b); Eq(a:GetPlayerPhaseStatus("B"), "different")
		if case == "off" then a.options.experimentalLayerDetection = false else a[case] = true end
		Eq(a:GetPlayerPhaseStatus("B"), nil)
		Eq(a:IsPlayerPhaseQueuedWireCurrent(wire, "B"), false)
		a:UpdatePlayerPhaseObservations(); Eq(rawget(a, "playerPhaseState"), nil)
	end
end)
QT:RegisterTest("experimental phases reject unsolicited duplicate reordered expired and cross-map replies", function()
	local a, b = Pair(); Deliver(a, b)
	local reply = b.sent[#b.sent].wire:sub(6)
	Eq(a:HandlePlayerPhaseMessage(reply, "Stranger"), false)
	Eq(a:HandlePlayerPhaseMessage(reply, "B"), true)
	Eq(a:HandlePlayerPhaseMessage(reply, "B"), false)
	a, b = Pair(); Deliver(a, b); reply = b.sent[#b.sent].wire:sub(6)
	a.now = 109; a:UpdatePlayerPhaseObservations()
	Eq(a:HandlePlayerPhaseMessage(reply, "B"), false)
	a, b = Pair(); Deliver(a, b); reply = b.sent[#b.sent].wire:sub(6)
	a.map = 2; a.now = 104; a:UpdatePlayerPhaseObservations()
	Eq(a:HandlePlayerPhaseMessage(reply, "B"), false)
	a.map = 1; a.now = 105; a:UpdatePlayerPhaseObservations()
	Eq(a:HandlePlayerPhaseMessage(reply, "B"), false)
end)
QT:RegisterTest("experimental phases reject malformed payloads and bound visibility samples", function()
	local a, b = Pair()
	for i = 1, 128 do b.players["Player-123456-" .. string.format("%032X", i)] = true end
	b.now = 104; b:UpdatePlayerPhaseObservations()
	Deliver(a, b)
	local wire = b.sent[#b.sent].wire
	assert(#wire <= 255)
	Eq(a:HandlePlayerPhaseMessage(wire:sub(6), "B"), true)
	for _, payload in ipairs({ "", "2,Q,1,1,-,Player-1-ABC,", "1,Q,1,0,-,Player-1-ABC,",
		"1,Q,1,1,invalid,Player-1-ABC,", "1,Q,1,1,-,Player-1-ABC,/", string.rep("x", 251) }) do
		Eq(a:HandlePlayerPhaseMessage(payload, "B"), false)
	end
end)
QT:RegisterTest("experimental phases expire departed ignored peers and throttle old clients", function()
	local a, b = Pair(); Exchange(a, b)
	a.ignored = "B"; Eq(a:GetPlayerPhaseStatus("B"), nil)
	a.ignored = nil; a.nearby = {}; a.now = 104; a:UpdatePlayerPhaseObservations()
	Eq(a:GetPlayerPhaseStatus("B"), nil)
	a, b = Pair(); local before = #a.sent
	for now = 104, 132 do a.now = now; a:UpdatePlayerPhaseObservations() end
	Eq(#a.sent, before)
	-- Reload/reset never reuses the request nonce within the same sender session.
	local id = a.playerPhaseState.attempts.B.id
	a.playerPhaseState = nil; a.now = 133; a:UpdatePlayerPhaseObservations()
	assert(a.playerPhaseState.attempts.B.id ~= id)
end)
QT:RegisterTest("experimental phases discard old evidence when local NPC routing changes", function()
	local a, b = Pair(); Exchange(a, b)
	a.key = "1:0:300"
	for now = 104, 106 do a.now = now; a:UpdatePlayerPhaseObservations() end
	Eq(a:GetPlayerPhaseStatus("B"), nil)
end)
QT:RegisterTest("experimental observation scans readable visible units without targeting or retaining frames", function()
	local a = Peer("A", "Player-1-ABC", "1:0:100")
	a.GetPlayerPhaseObservation = QT.GetPlayerPhaseObservation
	a.API.GetPlayerMapID = function() return 1 end
	a.API.UnitGUID = function() return a.guid end
	local frames = { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" } }
	a.API.GetNamePlates = function() return frames end
	local reads = {}
	a.API.GetLayerObservationUnit = function(token)
		reads[token] = true
		if token == "target" then return { guid = "Creature-0-1-0-100-123-AAA", controlled = true } end
		if token == "nameplate1" then return { guid = "Creature-0-1-0-100-124-BBB", controlled = false } end
		if token == "nameplate2" then return { guid = "Player-1-FFF", controlled = true } end
	end
	local o = a:GetPlayerPhaseObservation()
	Eq(o.players["Player-1-FFF"], true)
	Eq(o.npcs["Creature-0-1-0-100-123-AAA"], nil)
	Eq(o.npcs["Creature-0-1-0-100-124-BBB"], true)
	Eq(reads.mouseover, true); Eq(reads.focus, true)
	Eq(QT.DEFAULTS.profile.experimentalLayerDetection, true)
end)

QT:RegisterTest("experimental phase observations reset on shard transfer events", function()
	local a, b = Pair(); Exchange(a, b)
	a:SHARD_TRANSFER_IMMINENT(); Eq(rawget(a, "playerPhaseState"), nil)
	b:SHARD_TRANSFER(); Eq(rawget(b, "playerPhaseState"), nil)
end)

QT:RegisterTest("experimental comparison excludes stale cached positions even inside minimap bounds", function()
	local a = Peer("A", "Player-1-ABC", "1:0:100")
	a.GetPlayerPhaseCandidates = QT.GetPlayerPhaseCandidates
	function a:GetLocationPinSurface() return { width = 100, height = 100 } end
	function a:GetVisiblePlayerLocations() return {
		{ name = "Fresh", receivedAt = 99 }, { name = "Cached", receivedAt = 60 },
		{ name = "Transit", receivedAt = 99, sampledAt = 60 },
	} end
	function a:ProjectPlayerLocationPin() return 50, 50 end
	local candidates = a:GetPlayerPhaseCandidates()
	Eq(#candidates, 1); Eq(candidates[1].name, "Fresh")
end)
