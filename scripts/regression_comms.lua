-- Live-safe fixtures: these tests only replace fields on private addon objects.
local QuestTogether = _G.QuestTogether

local function ObserveLocation(a, data, name, age, session, sequence)
	local observation = a:CreatePeerObservation(
		name,
		"LOC",
		{ source = "snapshot", age = age or 0, lifetime = 600, session = session, sequence = sequence }
	)
	return a:HandlePlayerLocationMessage(data, name, observation)
end

local function Equal(actual, expected)
	if actual ~= expected then
		error("expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function WireEvent(addon, operation, record)
	addon.fixtureSequence = (addon.fixtureSequence or 0) + 1
	return assert(addon:BuildCommFrames(operation, record, {
		session = "1791300000-1234",
		messageId = tostring(addon.fixtureSequence),
		stamp = addon:GetAnnouncementServerTime() or 1791300000,
	}))
end
local function ReadRecord(addon, frames)
	if type(frames) == "string" then
		frames = { frames }
	end
	local parts, operation = {}
	for _, wire in ipairs(frames) do
		local frame, body = addon:DecodeCommFrame(wire)
		assert(frame)
		parts[frame.part] = body
		operation = frame.operation
	end
	return addon:DecodeCommRecord(operation, table.concat(parts)), operation
end

local function QuietNetwork()
	local net = QuestTogether:CreateTestNetwork({ fps = 30 })
	local peer = net:AddPeer("Friend-Realm")
	net:Join(peer, peer.announcementChannelName, true)
	peer:InitializeCommunications()
	peer:InitializeRuntimeCoordinator()
	function peer:UpdatePlayerCommunications() end
	return net, peer
end

local function NewCommsFixture()
	local addon = setmetatable({
		isEnabled = true,
		isLocalDeveloper = true,
		partyMembers = {},
		pendingPingRequests = {},
		pendingQuestCompareRequests = {},
		recentCommMessageSignatures = {},
		delayed = {},
		printed = {},
		wire = {},
		runtime = {},
		now = 100,
		channelID = 7,
	}, { __index = QuestTogether })
	addon.API = {
		GetTime = function()
			return addon.now
		end,
		Random = function()
			return 1234
		end,
		IsWarModeFeatureEnabled = function()
			return true
		end,
		GetRealmName = function()
			return "Realm"
		end,
		UnitFullName = function()
			return "MyPlayer", "Realm"
		end,
		UnitName = function()
			return "MyPlayer"
		end,
		UnitClass = function()
			return "Mage", "MAGE"
		end,
		GetChannelName = function()
			return addon.channelID
		end,
		IsInParty = function()
			return false
		end,
		IsInRaid = function()
			return false
		end,
		IsInInstanceGroup = function()
			return false
		end,
		Delay = function(_, callback)
			addon.delayed[#addon.delayed + 1] = callback
		end,
		SendAddonMessage = function(prefix, message, distribution, target)
			addon.wire[#addon.wire + 1] = { prefix, message, distribution, target }
			return 0
		end,
	}
	function addon:PrepareDeveloperPingRequest(request)
		return request
	end
	function addon:GetRuntimeWorkStateStore()
		return self.runtime
	end
	function addon:Debugf() end
	function addon:Debug() end
	function addon:IsIgnoredPlayerName()
		return false
	end
	function addon:GetPlayerClassFile()
		return "MAGE"
	end
	function addon:GetPlayerAnnouncementLocationInfo()
		return {}
	end
	function addon:GetAddonVersion()
		return "test"
	end
	function addon:PrintQuestCompareStart() end
	function addon:PrintQuestCompareMessage(_, entry)
		self.printed[#self.printed + 1] = entry.questId
	end
	function addon:PrintQuestCompareDone(_, count)
		self.printed[#self.printed + 1] = "done:" .. count
	end
	function addon:PrintPingResponse(response)
		self.printed[#self.printed + 1] = response.senderName
	end
	function addon:PrintConsoleAnnouncement(message)
		self.printed[#self.printed + 1] = message
	end
	function addon:Emit(op, record, routes, options)
		local frames = WireEvent(self, op, record)
		for _, route in ipairs(self:GetCommunicationRoutes(op, routes)) do
			self.wire[#self.wire + 1] = { self.commPrefix, frames, route.distribution, route.target }
		end
		if options and options.onComplete then
			options.onComplete(true, "accepted")
		end
		return true
	end
	function addon:OnCommReceived(prefix, wire, route, sender, ...)
		if type(wire) == "table" then
			local accepted = false
			for _, frame in ipairs(wire) do
				accepted = QuestTogether.OnCommReceived(self, prefix, frame, route, sender, ...) or accepted
			end
			return accepted
		end
		return QuestTogether.OnCommReceived(self, prefix, wire, route, sender, ...)
	end
	function addon:RefreshQTPlayerPlatePresence() end
	return addon
end

local function Event(text)
	return {
		eventType = "QUEST_PROGRESS",
		senderName = "Friend-Realm",
		senderGUID = "Player-1-ABC",
		classFile = "MAGE",
		text = text or "1/5 Things",
		questId = "12345",
	}
end

local function DeveloperFixture(name)
	local a = NewCommsFixture()
	a.db = { profile = QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile), global = {} }
	a.name = name or "Dev-Realm"
	a.PrepareDeveloperPingRequest = QuestTogether.PrepareDeveloperPingRequest
	a.API.GetServerTime = function()
		return 1791300000 + math.floor(a.now)
	end
	function a:GetPlayerFullName()
		return self.name
	end
	function a:IsSelfSender(n)
		return self:NormalizeMemberName(n) == self.name
	end
	function a:IsRuntimeRestricted()
		return false
	end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshPlayerLocationPins() end
	function a:HideAnnouncementChannelFromChatWindows() end
	function a:BuildPartyVisualMetadata()
		return { size = 0 }
	end
	function a:ReadLocalPlayerLocation()
		self.reads = (self.reads or 0) + 1
		return { mapID = 12, x = 0.42, y = 0.63, faction = "Alliance", warMode = false }
	end
	function a:BuildDiagnosticReport(_, extraFields)
		local lines = { "QT diagnostic snapshot\n" .. string.rep("Long diagnostic state\n", 70) }
		for _, field in ipairs(extraFields or {}) do
			lines[#lines + 1] = field[1] .. "=" .. tostring(field[2])
		end
		return table.concat(lines, "\n")
	end
	local seed = ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"):gsub("..", function(x)
		return string.char(tonumber(x, 16))
	end)
	a.developerPublicKeyHex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	function a:SignDeveloperRequest(message)
		return self.Ed25519.Sign(seed, message)
	end
	function a:GetDebugController()
		return {
			ShowReport = function(_, body, title)
				a.report, a.reportTitle = body, title
			end,
		}
	end
	function a:PrintPingResponse(response)
		self.printed[#self.printed + 1] = response
	end
	local clock = a:CreateTestClock(100)
	a.API.GetTime = function()
		return clock:GetTime()
	end
	a.API.Delay = function(seconds, callback)
		clock:After(seconds, callback)
	end
	a.clock = clock
	return a
end

local function FinishDeveloperVerification(peer)
	local steps = 0
	while peer.developerRequestState and #peer.developerRequestState.jobs > 0 do
		steps = steps + 1
		assert(steps < 10000, "incremental verifier did not finish")
		peer:DrainDeveloperPingVerifications()
		peer.clock:Advance(0.1)
	end
end

QuestTogether:RegisterTest(
	"developer verification budgets work and cancels on opt-out without reading diagnostics",
	function()
		local peer = DeveloperFixture("Friend-Realm")
		local work, callback = 0, false
		peer.Ed25519 = {
			NewVerification = function()
				return coroutine.create(function()
					for _ = 1, 100 do
						work = work + 1
						coroutine.yield()
					end
					return true
				end)
			end,
		}
		local request = {
			requestId = "dev-1791300100-1234-1",
			issuedAt = peer:GetAnnouncementServerTime(),
			developerRequest = true,
			supportsPagedPong = true,
			supportsDirectComms = true,
			signature = string.rep("0", 128),
		}
		Equal(
			peer:QueueDeveloperPingVerification(request, "Dev-Realm", function()
				callback = true
			end),
			true
		)
		Equal(work, 0)
		peer:DrainDeveloperPingVerifications()
		peer.clock:Advance(0.1)
		Equal(work, 8, "missing profiler still has a hard step limit")
		Equal(callback, false)
		Equal(peer.reads, nil)
		local milliseconds = 0
		peer.API.ProfileMilliseconds = function()
			milliseconds = milliseconds + 0.6
			return milliseconds
		end
		peer:DrainDeveloperPingVerifications()
		peer.clock:Advance(0.1)
		Equal(work, 10, "frame budget yields before the step limit")
		peer:SetOption("shareDeveloperDiagnostics", false)
		peer:SetOption("shareDeveloperDiagnostics", true)
		peer.clock:Drain()
		Equal(work, 10)
		Equal(callback, false)
		Equal(peer.reads, nil)
	end
)

QuestTogether:RegisterTest(
	"developer requests stay unique in one tick and expose bounded authentication timing",
	function()
		local peer = DeveloperFixture("Dev-Realm")
		peer.SignDeveloperRequest = function()
			return string.rep("x", 64)
		end
		local first = assert(peer:PrepareDeveloperPingRequest({}, "Friend-Realm", false))
		local second = assert(peer:PrepareDeveloperPingRequest({}, "Friend-Realm", false))
		assert(first.requestId ~= second.requestId)
		local recipient = DeveloperFixture("Friend-Realm")
		recipient.Ed25519 = {
			NewVerification = function()
				return coroutine.create(function()
					coroutine.yield()
					return true
				end)
			end,
		}
		Equal(recipient:GetDeveloperCommunicationMetrics().queued, 0)
		Equal(rawget(recipient, "developerRequestState"), nil)
		assert(recipient:QueueDeveloperPingVerification(first, "Dev-Realm", function() end))
		recipient.clock:Advance(2)
		recipient:DrainDeveloperPingVerifications()
		local metrics = recipient:GetDeveloperCommunicationMetrics()
		Equal(metrics.admitted, 1)
		Equal(metrics.verified, 1)
		Equal(metrics.steps, 2)
		Equal(metrics.queueSecondsLast, 2)
		Equal(metrics.queued, 0)
		assert(metrics.verificationSecondsLast >= 0)
	end
)

QuestTogether:RegisterTest(
	"developer verification copies requests bounds admission and backs off invalid senders",
	function()
		local peer, verified = DeveloperFixture("Friend-Realm"), {}
		peer.Ed25519 = {
			NewVerification = function(_, message)
				return coroutine.create(function()
					coroutine.yield()
					return not message:find("Bad-Realm", 1, true)
				end)
			end,
		}
		local function request(id)
			return {
				requestId = "dev-1791300100-1234-" .. id,
				issuedAt = peer:GetAnnouncementServerTime(),
				developerRequest = true,
				supportsPagedPong = true,
				signature = string.rep("0", 128),
			}
		end
		local original = request(1)
		Equal(
			peer:QueueDeveloperPingVerification(original, "Good-Realm", function(copy)
				verified[#verified + 1] = copy
			end),
			true
		)
		original.requestId, original.targetName = "tampered", "Other-Realm"
		Equal(
			peer:QueueDeveloperPingVerification(request(2), "Good-Realm", function() end),
			false,
			"one pending job per sender"
		)
		for index = 2, 4 do
			Equal(
				peer:QueueDeveloperPingVerification(request(index), "Peer" .. index .. "-Realm", function() end),
				true
			)
		end
		Equal(peer:QueueDeveloperPingVerification(request(5), "Overflow-Realm", function() end), false)
		FinishDeveloperVerification(peer)
		Equal(verified[1].requestId, "dev-1791300100-1234-1")
		Equal(verified[1].targetName, nil)
		Equal(verified[1].developerVerified, true)
		Equal(
			peer:QueueDeveloperPingVerification(request(6), "Bad-Realm", function()
				error("invalid request accepted")
			end),
			true
		)
		FinishDeveloperVerification(peer)
		Equal(peer:QueueDeveloperPingVerification(request(7), "Bad-Realm", function() end), false)
		peer.clock:Advance(5)
		Equal(peer:QueueDeveloperPingVerification(request(7), "Bad-Realm", function() end), true)
		peer.developerRequestState = nil -- Same cancellation fence used by departure/reset.
		peer.clock:Drain()
	end
)

QuestTogether:RegisterTest(
	"profile switches copies and resets retire developer verification and queued replies",
	function()
		for _, change in ipairs({ "switch", "copy", "reset" }) do
			local peer = DeveloperFixture("Friend-Realm")
			local work, callbacks = 0, 0
			peer.Ed25519 = {
				NewVerification = function()
					return coroutine.create(function()
						for _ = 1, 40 do
							work = work + 1
							coroutine.yield()
						end
						return true
					end)
				end,
			}
			-- Exercise the real profile methods; UI refreshes belong to separate
			-- private fixtures and must not touch the player's live windows here.
			for _, method in ipairs({
				"EnsureQuestLogChatFrame",
				"CloseQuestLogChatFrame",
				"RefreshPartyRoster",
				"RefreshNameplateAugmentation",
				"RefreshActiveAnnouncementBubbles",
				"RefreshPersonalBubbleAnchorVisualState",
				"RefreshPersonalBubbleEditModeDialog",
				"RefreshMinimapButton",
				"RefreshManagedWindowLayouts",
				"OnPlayerLocationOptionsChanged",
				"BroadcastQuestPartnerStatus",
				"RefreshOptionsWindow",
				"RefreshProfilesWindow",
				"QueuePartyNavigationUpdate",
				"RefreshWindowThemes",
			}) do
				peer[method] = function() end
			end
			peer.hasLoggedIn = true
			peer.activeCharacterKey, peer.activeProfileKey = peer.name, "Initial"
			peer.db.profile.chatLogDestination = "main"
			peer.db.profiles = { Initial = peer.db.profile, Private = peer:DeepCopy(peer.db.profile) }
			peer.db.profiles.Private.shareDeveloperDiagnostics = false
			peer.db.profileKeys = { [peer.name] = "Initial" }
			local request = {
				requestId = "dev-1791300100-1234-1",
				issuedAt = peer:GetAnnouncementServerTime(),
				developerRequest = true,
				supportsPagedPong = true,
				signature = string.rep("0", 128),
			}
			assert(peer:QueueDeveloperPingVerification(request, "Dev-Realm", function()
				callbacks = callbacks + 1
				peer:ReadLocalPlayerLocation()
			end))
			peer:DrainDeveloperPingVerifications()
			peer.clock:Advance(0.1)
			Equal(work, 8)
			peer:InitializeCommunications()
			local generation = rawget(peer, "diagnosticReplyGeneration") or 0
			assert(
				peer:Respond(
					"DREPORT",
					{ requestId = "old-profile", diagnosticText = string.rep("x", 800) },
					{ { distribution = "WHISPER", target = "Dev-Realm" } },
					{
						owner = peer,
						isCurrent = function()
							return generation == (rawget(peer, "diagnosticReplyGeneration") or 0)
								and peer:GetOption("shareDeveloperDiagnostics")
						end,
					}
				)
			)
			local sent = #peer.wire
			if change == "switch" then
				assert(peer:SetActiveProfile("Private"))
				assert(peer:SetActiveProfile("Initial"))
			elseif change == "copy" then
				assert(peer:CopyProfileIntoActiveProfile("Private"))
				peer:SetOption("shareDeveloperDiagnostics", true)
			else
				-- Reset also replaces an opted-in profile with another opted-in one.
				assert(peer:ResetActiveProfile())
			end
			peer.clock:Drain()
			Equal(work, 8)
			Equal(callbacks, 0)
			Equal(peer.reads, nil)
			Equal(#peer.wire, sent)
			Equal(peer.developerRequestState, nil)
		end
	end
)

QuestTogether:RegisterTest(
	"developer verification bounds failed senders and discards work when the clock rewinds",
	function()
		local peer = DeveloperFixture("Friend-Realm")
		peer.API.GetServerTime = function()
			return 1791300000 + math.floor(peer.clock:GetTime())
		end
		peer.Ed25519 = {
			NewVerification = function()
				return coroutine.create(function()
					return false
				end)
			end,
		}
		local function Reject(id, sender)
			local request = {
				requestId = "dev-1791300100-1234-" .. id,
				issuedAt = peer:GetAnnouncementServerTime(),
				developerRequest = true,
				supportsPagedPong = true,
				signature = string.rep("0", 128),
			}
			assert(peer:QueueDeveloperPingVerification(request, sender, function()
				error("invalid signature accepted")
			end))
			FinishDeveloperVerification(peer)
			local count = 0
			for _ in pairs(peer.developerRequestState.failures) do
				count = count + 1
			end
			assert(count <= 64, "invalid identities must not grow an unbounded failure cache")
			peer.clock:Advance(5)
		end
		-- Build long backoffs through actual failures, then churn fresh identities.
		-- Their longer retention overlaps enough newcomers to exercise eviction.
		for round = 1, 5 do
			for index = 1, 8 do
				Reject(round * 10 + index, "Repeat" .. index .. "-Realm")
			end
		end
		for index = 1, 150 do
			Reject(1000 + index, "Peer" .. index .. "-Realm")
		end
		peer.Ed25519 = {
			NewVerification = function()
				return coroutine.create(function()
					for _ = 1, 40 do
						coroutine.yield()
					end
					return true
				end)
			end,
		}
		local request = {
			requestId = "dev-1791300100-1234-999",
			issuedAt = peer:GetAnnouncementServerTime(),
			developerRequest = true,
			supportsPagedPong = true,
			signature = string.rep("0", 128),
		}
		assert(peer:QueueDeveloperPingVerification(request, "Dev-Realm", function()
			error("retired clock lifetime accepted")
		end))
		peer:DrainDeveloperPingVerifications()
		peer.clock:Advance(0.1)
		peer.clock.now = peer.clock.now - 1
		-- Model the timer firing after a reset of the monotonic clock.
		peer:DrainDeveloperPingVerifications()
		Equal(peer.developerRequestState, nil)
		peer.clock:Drain()
	end
)

-- Full RFC vectors include repeated scalar arithmetic; bounded verifier contracts remain live.
QuestTogether:RegisterTest("developer Ed25519 signatures match RFC8032 and reject altered content", function()
	local E = QuestTogether.Ed25519
	local function unhex(s)
		return (s:gsub("..", function(x)
			return string.char(tonumber(x, 16))
		end))
	end
	local seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
	local key = unhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
	local sig = unhex(
		"e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
	)
	Equal(E.PublicKey(seed), key)
	Equal(E.Sign(seed, ""), sig)
	Equal(E.Verify(key, "", sig), true)
	Equal(E.Verify(key, "changed", sig), false)
	Equal(E.Verify(key, "", sig:sub(1, 63)), false)
	Equal(E.Verify(key, "", sig:sub(1, 32) .. string.rep(string.char(255), 32)), false)
	for _, message in ipairs({ "", "changed" }) do
		local verifier, slices = E.NewVerification(key, message, sig), 0
		while coroutine.status(verifier) ~= "dead" do
			local ok, valid = coroutine.resume(verifier)
			assert(ok)
			slices = slices + 1
			if coroutine.status(verifier) == "dead" then
				Equal(valid, message == "")
			end
		end
		assert(slices > 100, "verification must expose bounded arithmetic steps")
	end
end, { offline = true })

local function Pong(a, shared, sampleTime)
	return {
		senderName = "Friend-Realm",
		developer = true,
		locationShared = shared,
		mapID = "12",
		coordX = "42",
		coordY = "63",
		classFile = "MAGE",
		className = "Mage",
		raceName = "Human",
		faction = "Alliance",
		level = "60",
		warMode = "0",
		sampledAt = sampleTime or a:GetAnnouncementServerTime(),
	}
end

-- The exact 14-field PONG layout emitted by 6.5.7: public coordinates, no
-- diagnostic consent/sample extension. Exercise current correlation/dispatch.
local function LegacyPongWire(id, changes)
	local fields =
		{ "2", id, "Friend-Realm", "Realm", "Human", "MAGE", "Mage", "10", "Elwynn", "42", "63", "", "12", "6.5.7" }
	for index, value in pairs(changes or {}) do
		fields[index] = value
	end
	return "PONG|" .. table.concat(fields, ",")
end
local function StartLegacyPong(a, target)
	local ok, id = a:SendPingRequest(target)
	assert(ok)
	return id
end
local function ReceiveLegacyPong(a, id, changes)
	a:OnCommReceived(a.commPrefix, LegacyPongWire(id, changes), "WHISPER", "Friend-Realm")
end

QuestTogether:RegisterTest("shared developer pong refreshes the normal cache and obeys normal map filters", function()
	local a = DeveloperFixture()
	a:AcceptDeveloperPingResponse(Pong(a, true), { developerRequest = true })
	local row = a:GetVisiblePlayerLocations("map")[1]
	assert(row)
	Equal(row, a.playerLocationState.peers["Friend-Realm"])
	Equal(row.x, 0.42)
	Equal(row.level, 60)
	Equal(row.classFile, "MAGE")
	Equal(row.developerOnly, nil)
	Equal(a.developerPlayerData["Friend-Realm"], nil)
	Equal(a:GetRecentPlayerLocationMapID("Friend-Realm"), 12)
	Equal(#a:GetVisiblePlayerLocations("minimap"), 1)
	a.db.profile.mapPartyOnly = true
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	a.db.profile.mapPartyOnly = false
	a.db.profile.onlyShowQuestPartners = true
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	a.db.profile.onlyShowQuestPartners = false
	a.clock:Advance(211) -- Longer than the old dev TTL and a global update interval.
	Equal(#a:GetVisiblePlayerLocations("map"), 1)
	a.clock:Advance(389)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
end)

QuestTogether:RegisterTest("manual location refresh preserves sample age and real LOC sequence", function()
	local a = DeveloperFixture()
	local payload = {
		mask = 3,
		mapID = 12,
		x = 0.1,
		y = 0.2,
		classFile = "MAGE",
		className = "Mage",
		race = "Human",
		faction = "Alliance",
		level = 60,
		warMode = false,
	}
	assert(ObserveLocation(a, payload, "Friend-Realm", 30, "1000-1", 8))
	a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime() - 20), { developerRequest = true })
	local row = a.playerLocationState.peers["Friend-Realm"]
	Equal(row.sampledAt, 80)
	Equal(row.lifetime, 580)
	Equal(row.session, "1000-1")
	Equal(row.sequence, 8)
	Equal(row.x, 0.42)
	-- A higher sequence may still contain a sample older than the manual refresh.
	Equal(ObserveLocation(a, payload, "Friend-Realm", 25, "1000-1", 9), false)
	Equal(ObserveLocation(a, payload, "Friend-Realm", 5, "1000-1", 10), true)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.1)
	-- Delayed pongs cannot move the location back again.
	a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime() - 20), { developerRequest = true })
	Equal(a.playerLocationState.peers["Friend-Realm"].sequence, 10)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.1)
	a.clock:Advance(595)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
end)

QuestTogether:RegisterTest("hidden pongs withdraw public positions without persisting private coordinates", function()
	local a = DeveloperFixture()
	a.activeCharacterKey = a.name
	a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime() - 10), { developerRequest = true })
	a:AcceptDeveloperPingResponse(Pong(a, false), { developerRequest = true })
	local row = a.playerLocationState.peers["Friend-Realm"]
	Equal(row.mask, 0)
	Equal(row.x, nil)
	Equal(row.mapID, nil)
	Equal(a:GetVisiblePlayerLocations("map")[1].publicLocationHidden, true)
	a:SavePlayerLocationCache()
	Equal(#a.db.global.playerLocationCache.rows, 0)
	-- Neither an older nor a tied shared pong can undo a privacy withdrawal.
	for _, age in ipairs({ 0, 10 }) do
		a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime() - age), { developerRequest = true })
		Equal(a.playerLocationState.peers["Friend-Realm"].mask, 0)
	end
	a.clock:Advance(121)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	Equal(a:GetRecentPlayerLocationMapID("Friend-Realm"), nil)
end)

QuestTogether:RegisterTest(
	"new public broadcasts replace hidden developer snapshots even with filtered maps",
	function()
		local a = DeveloperFixture()
		a:AcceptDeveloperPingResponse(Pong(a, false), { developerRequest = true })
		a.clock:Advance(1)
		assert(ObserveLocation(a, {
			mask = 3,
			mapID = 12,
			x = 0.1,
			y = 0.2,
			classFile = "MAGE",
			className = "Mage",
			race = "Human",
			faction = "Alliance",
			level = 60,
			warMode = false,
		}, "Friend-Realm", 0, "1000-1", 1))
		Equal(a.developerPlayerData["Friend-Realm"], nil)
		a.db.profile.mapPartyOnly = true
		Equal(#a:GetVisiblePlayerLocations("map"), 0)
	end
)

QuestTogether:RegisterTest("shared pong locations survive normal reload caching and later live LOC updates", function()
	local a = DeveloperFixture()
	a.activeCharacterKey = a.name
	a:AcceptDeveloperPingResponse(Pong(a, true), { developerRequest = true })
	a:SavePlayerLocationCache()
	Equal(#a.db.global.playerLocationCache.rows, 1)
	local b = DeveloperFixture()
	b.activeCharacterKey, b.db.global = a.name, a.db.global
	b:RestorePlayerLocationCache()
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.42)
	assert(ObserveLocation(b, {
		mask = 3,
		mapID = 12,
		x = 0.1,
		y = 0.2,
		classFile = "MAGE",
		className = "Mage",
		race = "Human",
		faction = "Alliance",
		level = 60,
		warMode = false,
	}, "Friend-Realm", 0, "1000-1", 1))
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.1)
end)

QuestTogether:RegisterTest(
	"newer shared pong removes red private dot and stale hidden replies cannot undo it",
	function()
		local a = DeveloperFixture()
		a:AcceptDeveloperPingResponse(Pong(a, false, a:GetAnnouncementServerTime() - 10), { developerRequest = true })
		a:AcceptDeveloperPingResponse(Pong(a, true), { developerRequest = true })
		Equal(a.developerPlayerData["Friend-Realm"], nil)
		Equal(a:GetVisiblePlayerLocations("map")[1].developerOnly, nil)
		a:AcceptDeveloperPingResponse(Pong(a, false, a:GetAnnouncementServerTime() - 5), { developerRequest = true })
		Equal(a.developerPlayerData["Friend-Realm"], nil)
		Equal(a.playerLocationState.peers["Friend-Realm"].mask, 3)
	end
)

QuestTogether:RegisterTest("manual public refreshes use the normal bounded location cache", function()
	local a = DeveloperFixture()
	function a:GetPlayerLocationPriorityOrigin()
		return nil
	end
	for i = 1, 513 do
		local response = Pong(a, true)
		response.senderName = "Peer" .. i .. "-Realm"
		a:AcceptDeveloperPingResponse(response, { developerRequest = true })
	end
	local count = 0
	for _ in pairs(a.playerLocationState.peers) do
		count = count + 1
	end
	Equal(count, 512)
	Equal(next(a.developerPlayerData), nil)
end)

QuestTogether:RegisterTest("malformed expired and unverified pongs cannot refresh public locations", function()
	local a = DeveloperFixture()
	for _, change in ipairs({ "coordinates", "expired", "future", "consent", "unverified", "ignored" }) do
		local pong, pending = Pong(a, true), { developerRequest = true }
		if change == "coordinates" then
			pong.coordX = "nan"
		elseif change == "expired" then
			pong.sampledAt = pong.sampledAt - 600
		elseif change == "future" then
			pong.sampledAt = pong.sampledAt + 31
		elseif change == "consent" then
			pong.locationShared = nil
		elseif change == "unverified" then
			pending.developerRequest = false
		else
			function a:IsIgnoredPlayerName()
				return true
			end
		end
		a:AcceptDeveloperPingResponse(pong, pending)
		Equal(#a:GetVisiblePlayerLocations("map"), 0)
	end
end)

local function BusyDiagnosticFixture()
	local peer = DeveloperFixture("Friend-Realm")
	peer.BuildDiagnosticReport = QuestTogether.BuildDiagnosticReport
	peer.GetRuntimeWorkStateStore = QuestTogether.GetRuntimeWorkStateStore
	function peer:GetDiagnosticEnvironment()
		return {}
	end
	function peer:GetPlayerTracker()
		return {}
	end
	function peer:IsWorkBlocked()
		return true
	end
	peer.API.IsWorldMapVisible = function()
		return false
	end
	for _, command in ipairs({
		"QTNAV",
		"QTN2",
		"ANN",
		"LVL",
		"LOC",
		"QTPR",
		"QTVR",
		"QTLF",
		"QTLQ",
		"QJST",
		"QJON",
		"QTPG",
		"QPGR",
		"QPGM",
		"QCMP",
		"QCQE",
		"QCDN",
		"QCOB",
		"QTB1",
		"QTDQ",
		"QTCI",
		"QTHQ",
		"QTHD",
		"QTPH",
		"QTSR",
		"QTSP",
		"QTSX",
		"QSHR",
		"PING",
		"PONG",
		"PONP",
	}) do
		peer:RecordCommsTraffic("received", command .. "|1")
	end
	for index = 1, 20 do
		peer:ScheduleDeferredWork(
			"nameplate_tint_refresh",
			"nameplate" .. index,
			function() end,
			0,
			"ScheduleNameplateHealthTintRefresh"
		)
	end
	peer:RecordDiagnosticError("outbound completion", string.rep("Lua error in addon callback; ", 43))
	function peer:BuildDeveloperDiagnosticSnapshot()
		self.builtReport = QuestTogether.BuildDeveloperDiagnosticSnapshot(self)
		return self.builtReport
	end
	return peer
end

QuestTogether:RegisterTest("announcement source timestamps measure delay independently of delivery identity", function()
	local a = NewCommsFixture()
	a.API.GetServerTime = function()
		return 1800000100
	end
	local event = Event()
	event.occurredAt = 1800000050
	a:RecordAnnouncementLatency(event)
	Equal(a:GetCommsDiagnostics().announcementAgeLast, 50)
	event.occurredAt = nil
	a:RecordAnnouncementLatency(event)
	Equal(a:GetCommsDiagnostics().announcementAgeUnknown, 1)
	event.occurredAt = 1800000200
	a:RecordAnnouncementLatency(event)
	Equal(a:GetCommsDiagnostics().announcementAgeUnknown, 2)
	a.API.GetServerTime = function()
		error("unreadable clock")
	end
	Equal(a:GetAnnouncementServerTime(), nil)
end)

QuestTogether:RegisterTest("transport counters count each route attempt and bound unknown command buckets", function()
	local a = NewCommsFixture()
	local wire = WireEvent(a, "ANN", Event())[1]
	a:RecordCommsTraffic("queued", wire)
	a:RecordCommsTraffic("sent", wire, 0)
	Equal(a:GetCommsDiagnostics().traffic.ANN.queued, 1)
	Equal(a:GetCommsDiagnostics().traffic.ANN.sentBytes, #wire)
	for i = 1, 100 do
		a:RecordCommsTraffic("received", "2|UNKNOWN" .. i .. "|garbage")
	end
	local count = 0
	for _ in pairs(a:GetCommsDiagnostics().traffic) do
		count = count + 1
	end
	Equal(count, 2)
	Equal(a:GetCommsDiagnostics().traffic.OTHER.received, 100)
end)

QuestTogether:RegisterTest("unknown addon packets do not fall through into human channel chat", function()
	local addon = NewCommsFixture()
	function addon:CHAT_MSG_CHANNEL()
		error("addon traffic cannot become human chat")
	end
	function addon:RecordQTPlayerPresence()
		error("unknown commands cannot identify peers")
	end
	addon:OnCommReceived(
		addon.commPrefix,
		"FUTURE|Quest 844 — Objective 1: 5/7",
		"CHANNEL",
		"Friend-Realm",
		7,
		addon.announcementChannelName
	)
	Equal(#addon.printed, 0)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("plain QT channel chat displays once without relaying or discovering peers", function()
	local addon = NewCommsFixture()
	local options = { showChatLogs = true, showChatBubbles = true }
	local bubbles, plate = {}, {}
	function addon:GetOption(key)
		return options[key]
	end
	function addon:PrintConsoleAnnouncement(text, _, _, eventType, icon, kind)
		Equal(eventType, "QT_CHAT")
		Equal(icon, "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon")
		Equal(kind, "texture")
		self.printed[#self.printed + 1] = text
	end
	function addon:IsRuntimeRestrictionTypeActive()
		return self.restricted == true
	end
	function addon:IsSelfSender(name)
		return name == "MyPlayer-Realm"
	end
	function addon:FindVisiblePlayerNameplateForSender(guid, name)
		Equal(guid, "Player-1-ABC")
		Equal(name, "Friend-Realm")
		return self.visible and plate or nil
	end
	function addon:ShowAnnouncementBubbleOnNameplate(frame, text, eventType, icon, kind, name)
		Equal(eventType, "QT_CHAT")
		Equal(icon, "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon")
		Equal(kind, "texture")
		Equal(frame, plate)
		Equal(name, "Friend-Realm")
		bubbles[#bubbles + 1] = text
	end
	function addon:ShowAnnouncementBubbleOnUnitNameplate(unit, text, eventType, icon, kind)
		Equal(eventType, "QT_CHAT")
		Equal(unit, "player")
		Equal(icon, "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon")
		Equal(kind, "texture")
		bubbles[#bubbles + 1] = text
	end
	function addon:RecordQTPlayerPresence()
		error("plain chat cannot establish addon presence")
	end
	local function Receive(text, sender, channel, base)
		return addon:CHAT_MSG_CHANNEL(
			"CHAT_MSG_CHANNEL",
			text,
			sender or "Friend-Realm",
			"",
			channel or "7. " .. addon.announcementChannelName,
			nil,
			nil,
			nil,
			7,
			base,
			nil,
			1,
			"Player-1-ABC"
		)
	end
	-- Remote chat reaches the log even without proximity or group membership.
	Equal(Receive("Hello!"), true)
	Equal(#addon.printed, 1)
	Equal(#bubbles, 0)
	addon.visible = true
	Equal(Receive("|cffffffffHi|r |Hitem:123|h[item]|h |Tbad:99|t\nthere"), true)
	Equal(addon.printed[2], "Hi [item]  there")
	Equal(bubbles[1], addon.printed[2])
	Equal(Receive("hello", "MyPlayer-Realm"), true)
	Equal(#bubbles, 2)
	options.hideMyOwnChatBubbles = true
	Receive("hello", "MyPlayer-Realm")
	Equal(#bubbles, 2)
	options.showChatLogs, options.showChatBubbles = false, false
	Receive("hidden")
	Equal(#addon.printed, 4)
	Equal(#bubbles, 2)
	Equal(#addon.wire, 0)
	Equal(#addon.delayed, 0)
	options.showQTChat = false
	Equal(Receive("muted"), false)
	options.showQTChat = true
	Equal(Receive("wrong", nil, "General"), false)
	Equal(Receive("wrong", nil, addon.announcementChannelName .. "Other"), false)
	Equal(Receive("base metadata", nil, "", addon.announcementChannelName), true)
	Equal(Receive(" "), false)
	Equal(Receive("hello", ""), false)
	local inaccessible = setmetatable({}, {
		__tostring = function()
			error("inaccessible chat read")
		end,
	})
	function addon:CanAccessValue(value)
		return value ~= inaccessible
	end
	Equal(Receive(inaccessible), false)
	Equal(Receive("hello", inaccessible), false)
	Equal(Receive("hello", nil, inaccessible, inaccessible), false)
	options.showChatLogs = true
	Receive(string.rep("é", 130))
	Equal(#addon.printed[#addon.printed], 254)
	addon.restricted = true
	Equal(Receive("restricted"), false)
	addon.restricted = false
	function addon:IsIgnoredPlayerName()
		return true
	end
	Equal(Receive("ignored"), false)
	addon.isEnabled = false
	Equal(Receive("disabled"), false)
end)

local function NewRegionalNameFixture()
	local addon = NewCommsFixture()
	addon.showSurname = false
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.API.RegionalUniqueNamesEnabled = function()
		return true
	end
	addon.API.ShouldDisplaySurname = function()
		return addon.showSurname
	end
	addon.API.UnitFullName = function(unit)
		return "Anakin", unit == "player" and "Ofthesea" or "Othername"
	end
	addon.API.UnitName = function()
		return "Anakin"
	end
	addon.API.UnitGUID = function()
		return "Player-fixture-self"
	end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "party1"
	end
	addon.API.IsInRaid = function()
		return false
	end
	function addon:GetOption(key)
		return key == "showChatLogs"
	end
	function addon:ShouldDisplayAnnouncementType()
		return true
	end
	function addon:GetAnnouncementIconInfo()
		return "", ""
	end
	function addon:FindVisiblePlayerNameplateForSender()
		return nil
	end
	function addon:FindNearbyPlayerUnitTokenForSender()
		return nil
	end
	function addon:IsAnnouncementSenderNearbyByLocation()
		return true
	end
	function addon:ShouldShowAnnouncementsForRemoteSender()
		return true
	end
	function addon:PrintConsoleAnnouncement(text, sender)
		self.printed[#self.printed + 1] = { text = text, sender = sender, label = self:GetShortDisplayName(sender) }
	end
	return addon
end

QuestTogether:RegisterTest("Forever local announcements reject their own channel and party echoes", function()
	local addon = NewRegionalNameFixture()
	Equal(addon:PublishAnnouncementEvent("QUEST_PROGRESS", "1/5 objectives", 123), true)
	Equal(#addon.printed, 1)
	Equal(addon.printed[1].label, "Anakin")
	local packet = addon.wire[1][2]
	addon:OnCommReceived(addon.commPrefix, packet, "CHANNEL", "Anakin Ofthesea", 7, addon.announcementChannelName)
	addon:OnCommReceived(addon.commPrefix, packet, "PARTY", "Anakin-Ofthesea")
	Equal(#addon.printed, 1)
	Equal(addon:GetCommsDiagnostics().acceptedAnnouncements, 1)
	-- A different character sharing the first name must still be accepted,
	-- even if the payload claims our GUID. Only transport identity is trusted.
	addon:OnCommReceived(addon.commPrefix, packet, "CHANNEL", "Anakin Othername", 7, addon.announcementChannelName)
	Equal(#addon.printed, 1) -- conflicting claimed identity is rejected
end)

QuestTogether:RegisterTest(
	"Forever surname setting changes labels without changing identity or profile keys",
	function()
		local addon = NewRegionalNameFixture()
		for _, show in ipairs({ false, true, false }) do
			addon.showSurname = show
			Equal(addon:GetPlayerFullName(), "Anakin Ofthesea")
			Equal(addon:GetCurrentCharacterKey(), "Anakin-Ofthesea")
			Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin-Ofthesea")
			Equal(addon:GetShortDisplayName("Anakin Ofthesea"), show and "Anakin Ofthesea" or "Anakin")
			Equal(addon:GetShortDisplayName("Anakin-Ofthesea"), show and "Anakin Ofthesea" or "Anakin")
			Equal(addon:GetShortDisplayName("Anakin Othername"), "Anakin Othername")
			Equal(addon:IsSelfSender("Anakin Ofthesea"), true)
			Equal(addon:IsSelfSender("Anakin-Ofthesea"), true)
			Equal(addon:IsSelfSender("Anakin Othername"), false)
			Equal(addon:IsSelfSender("Anakin"), false)
			Equal(addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "progress", 123).senderName, "Anakin Ofthesea")
		end
	end
)

QuestTogether:RegisterTest("Forever roster unit announcements and ping metadata preserve full names", function()
	local addon = NewRegionalNameFixture()
	addon:RefreshPartyRoster()
	Equal(addon.partyMembers["Anakin Ofthesea"].displayName, "Anakin")
	Equal(addon.partyMembers["Anakin Othername"].displayName, "Anakin Othername")
	Equal(addon:IsGroupedSender("Anakin-Othername"), true)
	Equal(addon:BuildAnnouncementEventForUnit("party1", "QUEST_PROGRESS", "progress").senderName, "Anakin Othername")
	Equal(addon:GetPlayerPingMetadata().realmName, "")
	Equal(addon:GetPlayerPingMetadata().senderName, "Anakin Ofthesea")
	addon.API.UnitFullName = function()
		return "Anakin Ofthesea", nil
	end
	Equal(addon:GetPlayerFullName(), "Anakin Ofthesea")
end)

QuestTogether:RegisterTest("Forever unavailable surname profile fallback never invents a realm", function()
	local addon = NewRegionalNameFixture()
	addon.API.UnitFullName = function()
		return nil, nil
	end
	addon.GetPlayerFullName = function()
		return nil
	end
	addon.API.GetRealmName = function()
		error("regional profile fallback must not read a realm")
	end
	Equal(addon:GetCurrentCharacterKey(), "Anakin")
	Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin")
	addon.API.UnitFullName = function()
		return "Anakin", "Ofthesea"
	end
	Equal(addon:GetCurrentCharacterKey(), "Anakin-Ofthesea")
	Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin-Ofthesea")
end)

QuestTogether:RegisterTest("Forever hidden surnames never become social interaction targets", function()
	local addon = NewRegionalNameFixture()
	local queried = {}
	addon.API.IsOnIgnoredList = function(name)
		queried[#queried + 1] = name
		return false
	end
	Equal(QuestTogether.IsIgnoredPlayerName(addon, "Anakin Ofthesea"), false)
	Equal(#queried, 1)
	Equal(queried[1], "Anakin Ofthesea")
	addon.API.InviteUnit = function(name)
		queried[#queried + 1] = name
	end
	addon:InviteChatLogSpeaker("Anakin Ofthesea")
	Equal(queried[2], "Anakin Ofthesea")
end)

local function UseNativeLocationModel(addon)
	function addon:IsRuntimeRestricted()
		return false
	end
	function addon:GetLocationPinMapWorldSize()
		return 4000, 2000
	end
	addon.GetPlayerAnnouncementLocationInfo = QuestTogether.GetPlayerAnnouncementLocationInfo
	addon.CanPublishPlayerLocation = function()
		return true
	end
	addon.API.GetBestMapForUnit = function()
		return 37
	end
	addon.API.GetMapInfo = function()
		return { mapID = 37, name = "Elwynn Forest" }
	end
	addon.API.GetPlayerMapPosition = function()
		return { x = 0.5, y = 0.5 }
	end
end

QuestTogether:RegisterTest("Forever metadata never reads or displays realms and War Mode", function()
	local addon = NewRegionalNameFixture()
	UseNativeLocationModel(addon)
	addon.API.GetRealmName = function()
		error("Forever has no realm identity")
	end
	addon.API.IsWarModeFeatureEnabled = function()
		error("regional clients have no War Mode")
	end
	addon.API.IsWarModeActive = function()
		error("unsupported mode must not be polled")
	end
	Equal(addon:SupportsWarMode(), false)
	local location = addon:GetPlayerAnnouncementLocationInfo()
	Equal(location.warMode, nil)
	Equal(location.mapID, 37)
	local metadata = addon:GetPlayerPingMetadata()
	Equal(metadata.realmName, "")
	Equal(metadata.warMode, "")
	Equal(metadata.senderName, "Anakin Ofthesea")
	metadata.requestId = "regional-ping"
	local decoded = addon:DecodeCommRecord("PONG", addon:EncodeCommRecord("PONG", metadata))
	Equal(decoded.realmName, "")
	Equal(decoded.warMode, "")
	Equal(decoded.senderName, metadata.senderName)
	local event = addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	Equal(event.warMode, "")
	Equal(addon:DecodeCommRecord("ANN", addon:EncodeCommRecord("ANN", event)).warMode, "")
	-- Older clients still send a dummy realm and WM Off; ignore these labels
	-- without discarding their real name, map or coordinates.
	decoded.realmName, decoded.warMode = "LegacyRealm", "0"
	local message = addon:BuildPingResponseMessage(decoded)
	assert(not message:find("LegacyRealm", 1, true))
	assert(not message:find("WM Off", 1, true))
	assert(message:find("Elwynn Forest", 1, true))
	assert(not addon:BuildAnnouncementLocationSuffix(decoded):find("WM Off", 1, true))
end)

QuestTogether:RegisterTest("announcement metadata preserves unknown War Mode instead of inventing Off", function()
	for _, capability in ipairs({ "enabled", "disabled", "unreadable", "missing" }) do
		for _, state in ipairs({ "on", "off", "unknown" }) do
			local addon = NewCommsFixture()
			UseNativeLocationModel(addon)
			local polls = 0
			addon.API.IsWarModeFeatureEnabled = function()
				if capability == "enabled" then
					return true
				end
				if capability == "disabled" then
					return false
				end
				return nil
			end
			if capability == "missing" then
				addon.API.IsWarModeFeatureEnabled = nil
			end
			addon.API.IsWarModeActive = function()
				polls = polls + 1
				if state == "on" then
					return true
				end
				if state == "off" then
					return false
				end
			end
			local expected = ""
			if capability == "enabled" and state ~= "unknown" then
				expected = state == "on" and "1" or "0"
			end
			local metadata = addon:GetPlayerPingMetadata()
			Equal(metadata.warMode, expected)
			Equal(addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123).warMode, expected)
			Equal(polls, capability == "enabled" and 2 or 0)
			local suffix = addon:BuildAnnouncementLocationSuffix(metadata)
			Equal(suffix:find("WM ", 1, true) ~= nil, expected ~= "")
		end
	end
end)

QuestTogether:RegisterTest("unavailable War Mode capability cannot certify nearby announcement state", function()
	local addon = NewCommsFixture()
	UseNativeLocationModel(addon)
	local remote = { mapID = 37, zoneName = "Elwynn Forest", coordX = 50, coordY = 50, warMode = "0" }
	local inaccessible = setmetatable({}, {
		__tostring = function()
			error("inaccessible mode formatted")
		end,
	})
	function addon:CanAccessValue(value)
		return value ~= inaccessible
	end
	addon.API.IsWarModeActive = function()
		return false
	end
	addon.API.IsWarModeFeatureEnabled = function()
		return inaccessible
	end
	Equal(addon:SupportsWarMode(), nil)
	Equal(addon:NormalizeAnnouncementWarModeValue(inaccessible), nil)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.API.IsWarModeFeatureEnabled = function()
		error("capability unavailable")
	end
	Equal(addon:SupportsWarMode(), nil)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.API.IsWarModeFeatureEnabled = function()
		return false
	end
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	addon.API.IsWarModeFeatureEnabled = function()
		return true
	end
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	remote.warMode = "1"
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
end)

QuestTogether:RegisterTest("Forever nearby announcements use map distance without Retail War Mode", function()
	local sender, receiver = NewRegionalNameFixture(), NewRegionalNameFixture()
	UseNativeLocationModel(sender)
	UseNativeLocationModel(receiver)
	receiver.API.UnitFullName = function()
		return "Anakin", "Othername"
	end
	receiver.IsAnnouncementSenderNearbyByLocation = QuestTogether.IsAnnouncementSenderNearbyByLocation
	receiver.ShouldShowAnnouncementsForRemoteSender = QuestTogether.ShouldShowAnnouncementsForRemoteSender
	receiver.GetOption = function(_, key)
		if key == "showProgressFor" then
			return "party_nearby"
		end
		return key == "showChatLogs"
	end
	local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	for _, legacyMode in ipairs({ "", "0", "1" }) do
		event.warMode = legacyMode
		assert(sender:SendAnnouncementWireEvent(event))
		receiver:OnCommReceived(
			receiver.commPrefix,
			sender.wire[#sender.wire][2],
			"CHANNEL",
			"Anakin Ofthesea",
			7,
			receiver.announcementChannelName
		)
		receiver.now = receiver.now + 1
	end
	Equal(#receiver.printed, 3)
	event.mapID = "999"
	assert(sender:SendAnnouncementWireEvent(event))
	receiver:OnCommReceived(
		receiver.commPrefix,
		sender.wire[#sender.wire][2],
		"CHANNEL",
		"Anakin Ofthesea",
		7,
		receiver.announcementChannelName
	)
	Equal(#receiver.printed, 3)
	event.mapID, event.coordX, event.coordY = "37", "90", "90"
	assert(sender:SendAnnouncementWireEvent(event))
	receiver:OnCommReceived(
		receiver.commPrefix,
		sender.wire[#sender.wire][2],
		"CHANNEL",
		"Anakin Ofthesea",
		7,
		receiver.announcementChannelName
	)
	Equal(#receiver.printed, 3)
end)

QuestTogether:RegisterTest("Forever nameplate matching preserves surnames and rejects conflicting GUIDs", function()
	local addon = NewRegionalNameFixture()
	function addon:IsNameplateUnitPlayer()
		return true
	end
	addon.API.UnitGUID = function()
		return nil
	end
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin Othername"), true)
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin-Othername"), true)
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin Ofthesea"), false)
	Equal(addon:DoesUnitTokenMatchSender("party1", nil, "Anakin"), false)
	addon.API.UnitGUID = function()
		return "Player-fixture-other"
	end
	Equal(addon:DoesUnitTokenMatchSender("party1", "Player-fixture-self", "Anakin Othername"), false)
	Equal(addon:DoesUnitTokenMatchSender("party1", "Player-fixture-other", "Anakin Othername"), true)
end)

QuestTogether:RegisterTest("Forever display settings fail closed and inaccessible names stay unread", function()
	local addon = NewRegionalNameFixture()
	local inaccessible = setmetatable({}, {
		__tostring = function()
			error("foreign name traversed")
		end,
	})
	function addon:CanAccessValue(value)
		return value ~= inaccessible
	end
	Equal(addon:GetShortDisplayName(inaccessible), "Unknown")
	addon.API.ShouldDisplaySurname = function()
		return inaccessible
	end
	Equal(addon:GetShortDisplayName("Anakin Ofthesea"), "Anakin")
	addon.API.ShouldDisplaySurname = function()
		error("unknown setting")
	end
	Equal(addon:GetShortDisplayName("Anakin Ofthesea"), "Anakin")
	Equal(addon:GetShortDisplayName("Anakin Othername"), "Anakin Othername")
	addon.API.UnitFullName = function()
		return "Anakin", inaccessible
	end
	Equal(addon:GetPlayerFullName(), nil)
end)

QuestTogether:RegisterTest("retail names keep realm identity and native short display", function()
	local addon = NewCommsFixture()
	addon.API.RegionalUniqueNamesEnabled = function()
		return false
	end
	addon.API.Ambiguate = function(name, context)
		Equal(context, "short")
		return name:match("^[^-]+")
	end
	addon.API.ShouldDisplaySurname = function()
		error("not a regional name")
	end
	Equal(addon:GetPlayerFullName(), "MyPlayer-Realm")
	Equal(addon:GetShortDisplayName("MyPlayer-Realm"), "MyPlayer")
	Equal(addon:NormalizeMemberName("Other-Other Realm"), "Other-OtherRealm")
	Equal(addon:IsSelfSender("MyPlayer-Realm"), true)
	Equal(addon:IsSelfSender("MyPlayer-OtherRealm"), false)
end)

QuestTogether:RegisterTest("comms reports rejected or throwing send results as failure", function()
	for _, result in ipairs({ 1, 8, "throw" }) do
		local n, a = QuietNetwork()
		local completions = {}
		n.sendRule = function()
			if result == "throw" then
				error("failed native")
			end
			return result
		end
		assert(a:Emit("ANN", Event(), { { distribution = "CHANNEL", channelName = a.announcementChannelName } }, {
			onComplete = function(ok, status)
				completions[#completions + 1] = { ok, status }
			end,
		}))
		n:Advance(3)
		Equal(#completions, 1)
		Equal(completions[1][1], false)
		Equal(completions[1][2], result == 8 and "ambiguous" or "rejected")
	end
end)

QuestTogether:RegisterTest("comms resolves channel target after rejoining", function()
	local n, a = QuietNetwork()
	assert(a:Emit("ANN", Event(), { { distribution = "CHANNEL", channelName = a.announcementChannelName } }))
	n:Leave(a, a.announcementChannelName)
	n:Join(a, a.announcementChannelName, true)
	local id = a.joined[a.announcementChannelName]
	n:Advance(3)
	assert(#a.sent > 0)
	Equal(a.sent[1].target, id)
end)

QuestTogether:RegisterTest("announcement fragments preserve complete UTF8 and every declared field", function()
	local a = NewCommsFixture()
	local event = Event(string.rep("任務,|%", 100))
	event.zoneName = string.rep("Долина", 30)
	local frames = WireEvent(a, "ANN", event)
	assert(#frames > 1)
	for _, wire in ipairs(frames) do
		assert(#wire <= 255)
	end
	local decoded = ReadRecord(a, frames)
	Equal(decoded.text, event.text)
	Equal(decoded.zoneName, event.zoneName)
end)

QuestTogether:RegisterTest("announcement local text limit preserves complete UTF8", function()
	local addon = NewCommsFixture()
	local text = addon:SanitizeAnnouncementText(string.rep("写", 100))
	Equal(#text, 219)
	Equal(string.sub(text, -3), "写")
end)

QuestTogether:RegisterTest("quest comparison titles retain full UTF8 text through bounded shared fragments", function()
	local a = NewCommsFixture()
	local title = string.rep("写真", 80)
	local record = {
		requestId = "qcmp",
		snapshotId = "snapshot",
		count = 1,
		entries = {
			{ questId = 12345, questTitle = title },
		},
	}
	local frames = assert(
		a:BuildCommFrames(
			"QCRS",
			record,
			{ session = "100-1234", messageId = "1", requestId = "qcmp", stamp = 1800000000 }
		)
	)
	assert(#frames > 1)
	for _, wire in ipairs(frames) do
		assert(#wire <= 255)
	end
	local decoded = ReadRecord(a, frames)
	Equal(decoded.entries[1].questId, 12345)
	Equal(decoded.entries[1].questTitle, title)
end)

QuestTogether:RegisterTest("oversized transport messages fail before sending", function()
	local _, a = QuietNetwork()
	local event = Event(string.rep("x", 1025))
	local ok = a:Emit("ANN", event)
	Equal(ok, false)
	Equal(#a.attempts, 0)
	Equal(a:DecodeCommFrame(string.rep("x", 256)), nil)
	Equal(a:DecodeCommFrame("2|ANN|x|1||1|1|1|" .. string.char(0)), nil)
end)

QuestTogether:RegisterTest("chat channel filter ignores mentions and similarly named channels", function()
	local addon = NewCommsFixture()
	Equal(
		addon:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL",
			addon.announcementChannelName,
			"Friend",
			"",
			"General"
		),
		false
	)
	Equal(
		addon:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL",
			"hi",
			"Friend",
			"",
			"7. " .. addon.announcementChannelName
		),
		true
	)
	Equal(
		addon:AnnouncementChannelChatFilter(
			nil,
			"CHAT_MSG_CHANNEL",
			"hi",
			"Friend",
			"",
			addon.announcementChannelName .. "Other"
		),
		false
	)
end)

QuestTogether:RegisterTest("explicit channel name overrides a stale local channel ID", function()
	local addon = NewCommsFixture()
	addon.announcementChannelLocalID = 7
	Equal(addon:IsAnnouncementChannelEvent("CHANNEL", 7, "General"), false)
	Equal(addon:IsAnnouncementChannelEvent("CHANNEL", 7, ""), true)
end)

QuestTogether:RegisterTest("party normalization rejects inaccessible names and realms", function()
	local addon = NewCommsFixture()
	function addon:CanAccessValue(value)
		return value ~= "hidden"
	end
	Equal(addon:NormalizeMemberName("hidden"), nil)
	Equal(addon:NormalizeMemberName("  Friend-Other Realm  "), "Friend-OtherRealm")
	Equal(addon:NormalizeMemberName(""), nil)
	Equal(addon:NormalizeMemberName(nil), nil)
	addon.API.UnitFullName = function()
		return "Friend", "hidden"
	end
	Equal(addon:GetPlayerFullName(), nil)
end)

QuestTogether:RegisterTest("ping metadata keeps class and realm secondary return values", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function()
		return "Friend", "Other Realm"
	end
	local response = addon:GetPlayerPingMetadata()
	Equal(response.classFile, "MAGE")
	Equal(response.realmName, "Other Realm")
end)

QuestTogether:RegisterTest("quest comparison deduplicates entries for the entire request", function()
	local a = NewCommsFixture()
	a.pendingQuestCompareRequests.test = { targetName = "Friend-Realm" }
	local row = { questId = 12345, questTitle = "Quest" }
	local response = { requestId = "test", snapshotId = "snapshot", count = 2, entries = { row, row } }
	Equal(a:HandleQuestCompareResponse(response, "Friend-Realm"), false)
	Equal(#a.printed, 0)
	response.entries = { row }
	response.count = 1
	assert(a:HandleQuestCompareResponse(response, "Friend-Realm"))
	Equal(a:HandleQuestCompareResponse(response, "Friend-Realm"), false)
	Equal(#a.printed, 2)
end)

QuestTogether:RegisterTest("quest comparison never exposes rows from an incomplete atomic object", function()
	local a = NewCommsFixture()
	a.pendingQuestCompareRequests.test = { targetName = "Friend-Realm" }
	local response = {
		requestId = "test",
		snapshotId = "snapshot",
		count = 2,
		entries = {
			{ questId = 100, questTitle = "First" },
		},
	}
	Equal(a:HandleQuestCompareResponse(response, "Friend-Realm"), false)
	Equal(#a.printed, 0)
	response.entries[2] = { questId = 200, questTitle = "Second" }
	assert(a:HandleQuestCompareResponse(response, "Friend-Realm"))
	Equal(a.pendingQuestCompareRequests.test, nil)
	Equal(a.printed[3], "done:2")
end)

QuestTogether:RegisterTest("ping responses deduplicate each sender for entire request", function()
	local addon = NewCommsFixture()
	addon.pendingPingRequests.test = { responders = {}, responderCount = 0, remoteReplies = 0, startedAt = addon.now }
	local response = { requestId = "test", senderName = "Friend-Realm" }
	Equal(addon:HandlePingResponse(response), true)
	addon.now = 105
	Equal(addon:HandlePingResponse(response), false)
	Equal(addon:HandlePingResponse({ requestId = "test", senderName = "Friend-OtherRealm" }), true)
	Equal(#addon.printed, 2)
end)

QuestTogether:RegisterTest("stale quest compare timeout cannot clear a replacement request", function()
	local a = NewCommsFixture()
	assert(a:RequestQuestCompare("Friend-Realm"))
	local id = next(a.pendingQuestCompareRequests)
	local replacement = { targetName = "Friend-Realm" }
	a.pendingQuestCompareRequests[id] = replacement
	a.now = a.now + 181
	a:UpdateCommunicationRuntime()
	Equal(a.pendingQuestCompareRequests[id], replacement)
	Equal(#a.printed, 0)
end)

QuestTogether:RegisterTest("incomplete quest comparison reports timeout instead of completion", function()
	local a = NewCommsFixture()
	assert(a:RequestQuestCompare("Friend-Realm"))
	local id = next(a.pendingQuestCompareRequests)
	Equal(
		a:HandleQuestCompareResponse({
			requestId = id,
			snapshotId = "snapshot",
			count = 2,
			entries = { { questId = 100, questTitle = "First" } },
		}, "Friend-Realm"),
		false
	)
	a.now = a.now + 181
	a:UpdateCommunicationRuntime()
	Equal(a.pendingQuestCompareRequests[id], nil)
	Equal(a.printed[1], "Quest comparison timed out (0 quests received).")
end)

QuestTogether:RegisterTest("leaving comm channel clears outstanding response and replay state", function()
	local addon = NewCommsFixture()
	addon.pendingPingRequests.test = true
	addon.pendingQuestCompareRequests.test = {}
	addon.recentCommMessageSignatures.test = 100
	addon:LeaveAnnouncementChannel()
	Equal(next(addon.pendingPingRequests), nil)
	Equal(next(addon.pendingQuestCompareRequests), nil)
	Equal(next(addon.recentCommMessageSignatures), nil)
end)

QuestTogether:RegisterTest("incoming claimed identity cannot impersonate another player", function()
	local a = NewCommsFixture()
	local seen
	function a:HandleAnnouncementEvent(row)
		seen = row.senderName
	end
	local event = Event()
	event.senderName = "Spoofed-Realm"
	a:OnCommReceived(a.commPrefix, WireEvent(a, "ANN", event), "CHANNEL", "Friend-Realm", 7, a.announcementChannelName)
	Equal(seen, nil)
	event.senderName = "Friend-Realm"
	a:OnCommReceived(a.commPrefix, WireEvent(a, "ANN", event), "CHANNEL", "Friend-Realm", 7, a.announcementChannelName)
	Equal(seen, "Friend-Realm")
end)

QuestTogether:RegisterTest("disabled comm receiver does not dispatch announcements", function()
	local addon = NewCommsFixture()
	addon.isEnabled = false
	local count = 0
	function addon:HandleAnnouncementEvent()
		count = count + 1
	end
	addon:OnCommReceived(addon.commPrefix, "ANN|" .. addon:EncodeCommRecord("ANN", Event()), "PARTY", "Friend-Realm")
	Equal(count, 0)
end)

QuestTogether:RegisterTest("quest compare done rejects invalid or fractional counts", function()
	local addon = NewCommsFixture()
	for _, count in ipairs({ "bad", -1, 1.5 }) do
		addon.pendingQuestCompareRequests.test = { targetName = "Friend-Realm" }
		Equal(
			addon:HandleQuestCompareResponse(
				{ requestId = "test", snapshotId = "snapshot", count = count, entries = {} },
				"Friend-Realm"
			),
			false
		)
	end
end)

local function NewLevelUpFixture()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.emotes = {}
	addon.API.Random = function()
		return 1
	end
	addon.API.DoEmote = function(token, target)
		addon.emotes[#addon.emotes + 1] = { token = token, target = target }
	end
	addon.API.CanTargetUnitForEmote = function(unit)
		return unit == "target" or unit == "nameplate1"
	end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "target" or unit == "nameplate1"
	end
	addon.API.UnitIsPlayer = function()
		return true
	end
	addon.API.UnitGUID = function(unit)
		return unit == "player" and "Player-self" or "Player-1-ABC"
	end
	addon.API.UnitFullName = function(unit)
		return unit == "player" and "MyPlayer" or "Friend", "Realm"
	end
	addon.API.UnitName = function(unit)
		return unit == "player" and "MyPlayer" or "Friend"
	end
	function addon:IsRuntimeRestricted()
		return false
	end
	function addon:IsRuntimeRestrictionTypeActive()
		return false
	end
	function addon:FindVisiblePlayerNameplateForSender()
		return nil
	end
	function addon:FindNearbyPlayerUnitTokenForSender()
		return "target"
	end
	function addon:IsAnnouncementSenderNearbyByLocation()
		return false
	end
	function addon:ShowAnnouncementBubbleOnUnitNameplate()
		error("level-up should only play an emote")
	end
	function addon:ShowAnnouncementBubbleOnNameplate()
		error("level-up should only play an emote")
	end
	return addon
end

local function LevelUpEvent()
	local event = Event("Level 20")
	event.eventType = "PLAYER_LEVEL_UP"
	event.questId = ""
	event.emoteToken = "cheer"
	return event
end

local function NewRemoteCelebrationFixture()
	local addon = NewLevelUpFixture()
	addon.db.profile.showChatBubbles = false
	addon.db.profile.showChatLogs = false
	addon.db.profile.showProgressFor = "party_nearby"
	addon.API.UnitFullName = function(unit)
		return unit == "player" and "MyPlayer" or "Friend", "Realm"
	end
	addon.API.UnitName = function(unit)
		return unit == "player" and "MyPlayer" or "Friend"
	end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "target"
	end
	addon.API.UnitIsPlayer = function()
		return true
	end
	addon.API.UnitGUID = function(unit)
		return unit == "player" and "Player-self" or "Player-friend"
	end
	addon.API.IsMounted = function()
		return false
	end
	addon.API.GetFaction = function()
		return "Neutral"
	end
	addon.FindVisiblePlayerNameplateForSender = nil
	addon.FindNearbyPlayerUnitTokenForSender = nil
	addon.ForEachVisibleNamePlate = function() end
	return addon
end

local function ReceiveCelebration(addon, eventType, token, sender)
	local event = Event("Quest Completed: Wolves")
	event.eventType = eventType
	event.senderGUID = "Player-friend"
	event.emoteToken = token
	local command = eventType == "PLAYER_LEVEL_UP" and "LVL" or "ANN"
	local wire = WireEvent(addon, command, event)
	Equal(#wire <= 255, true)
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", sender or "Friend-Realm", 7, addon.announcementChannelName)
end

QuestTogether:RegisterTest("received celebrations reject unsupported and malformed emote tokens", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, token in ipairs({
			"rude",
			"not-an-emote",
			"cheer rude",
			"cheer\nrude",
			"|Hplayer:Friend|hcheer|h",
			"123",
			"true",
			"",
		}) do
			local addon = NewRemoteCelebrationFixture()
			ReceiveCelebration(addon, eventType, token)
			Equal(addon:GetCommsDiagnostics().acceptedAnnouncements, 1)
			Equal(#addon.emotes, 0)
		end
	end
end)

QuestTogether:RegisterTest("received celebrations canonicalize every approved local emote", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, token in ipairs(QuestTogether.completionEmotes) do
			local addon = NewRemoteCelebrationFixture()
			ReceiveCelebration(addon, eventType, " \t" .. string.upper(token) .. " \n")
			Equal(#addon.emotes, 1)
			Equal(addon.emotes[1].token, token)
			Equal(addon.emotes[1].target, "target")
		end
	end
end)

QuestTogether:RegisterTest(
	"received out-of-list special celebrations are rejected regardless of mount or faction",
	function()
		for _, eventType in ipairs({
			"QUEST_COMPLETED",
			"WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_COMPLETED",
			"PLAYER_LEVEL_UP",
		}) do
			for _, token in ipairs({ " MOUNTSPECIAL ", " FORTHEHORDE ", " FORTHEALLIANCE " }) do
				for _, faction in ipairs({ "Alliance", "Horde", "Neutral" }) do
					local addon = NewRemoteCelebrationFixture()
					addon.API.IsMounted = function()
						return true
					end
					addon.API.GetFaction = function()
						return faction
					end
					ReceiveCelebration(addon, eventType, token)
					Equal(addon:GetCommsDiagnostics().acceptedAnnouncements, 1)
					Equal(#addon.emotes, 0)
				end
			end
		end
	end
)

QuestTogether:RegisterTest("received celebration validation retains identity scope and option checks", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, blockedBy in ipairs({ "option", "scope", "ignored", "self", "identity" }) do
			local addon = NewRemoteCelebrationFixture()
			if blockedBy == "option" then
				local option = eventType == "PLAYER_LEVEL_UP" and "emoteOnNearbyPlayerLevelUp"
					or "emoteOnNearbyPlayerQuestCompletion"
				addon.db.profile[option] = false
			elseif blockedBy == "scope" then
				addon.db.profile.showProgressFor = "party_only"
			elseif blockedBy == "ignored" then
				addon.IsIgnoredPlayerName = function()
					return true
				end
			end
			local sender = blockedBy == "self" and "MyPlayer-Realm"
				or (blockedBy == "identity" and "Other-Realm" or "Friend-Realm")
			ReceiveCelebration(addon, eventType, "CHEER", sender)
			Equal(#addon.emotes, 0)
		end
	end
end)

QuestTogether:RegisterTest(
	"remote celebration validation never stringifies inaccessible or non-string tokens",
	function()
		local addon = NewRemoteCelebrationFixture()
		local inaccessible = setmetatable({}, {
			__tostring = function()
				error("inaccessible token stringified")
			end,
		})
		local accessible = setmetatable({}, {
			__tostring = function()
				error("non-string token stringified")
			end,
		})
		addon.CanAccessValue = function(_, value)
			return value ~= inaccessible
		end
		for _, token in ipairs({ inaccessible, accessible, 123, true, false }) do
			Equal(addon:GetSafeRemoteCompletionEmote(token), nil)
		end
		Equal(addon:GetSafeRemoteCompletionEmote(nil), nil)
	end
)

QuestTogether:RegisterTest("remote celebrations cannot expand their shipped list through runtime mutation", function()
	local addon = NewRemoteCelebrationFixture()
	addon.completionEmotes = { "rude", "mountspecial", "forthealliance", "forthehorde" }
	addon.API.Random = function()
		error("unsupported incoming emotes must not pick a substitute")
	end
	for _, token in ipairs(addon.completionEmotes) do
		ReceiveCelebration(addon, "QUEST_COMPLETED", token)
	end
	Equal(#addon.emotes, 0)
	Equal(addon:GetSafeRemoteCompletionEmote("cheer"), "cheer")
end)

QuestTogether:RegisterTest("remote rejected celebrations never query mount or faction or choose a fallback", function()
	local addon = NewRemoteCelebrationFixture()
	addon.API.IsMounted = function()
		error("mount state is irrelevant")
	end
	addon.API.GetFaction = function()
		error("faction is irrelevant")
	end
	addon.API.Random = function()
		error("no replacement emote")
	end
	for _, token in ipairs({ "mountspecial", "forthealliance", "forthehorde", "rude" }) do
		Equal(addon:GetSafeRemoteCompletionEmote(token), nil)
	end
end)

QuestTogether:RegisterTest("level-up sends one shared emote token on party and nearby routes", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.emoteOnQuestCompletion = false
	addon.API.IsInParty = function()
		return true
	end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), true)
	Equal(#addon.wire, 2)
	Equal(addon.wire[1][3], "PARTY")
	Equal(addon.wire[2][3], "CHANNEL")
	Equal(addon.wire[1][2], addon.wire[2][2])
	local event, command = ReadRecord(addon, addon.wire[1][2])
	Equal(command, "LVL")

	Equal(event.eventType, "PLAYER_LEVEL_UP")
	Equal(event.text, "Level 20")
	Equal(event.questId, "")
	Equal(#addon.emotes, 1)
	Equal(addon.emotes[1].token, event.emoteToken)
	Equal(addon.emotes[1].target, "MyPlayer")
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("local level-up toggle and test suppression still publish to peers", function()
	for _, suppressTests in ipairs({ false, true }) do
		local addon = NewLevelUpFixture()
		addon.db.profile.emoteOnLevelUp = suppressTests
		addon.suppressLocalAnnouncementDisplayDuringTests = suppressTests
		Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), true)
		Equal(#addon.wire, 1)
		Equal(#addon.emotes, 0)
	end
end)

QuestTogether:RegisterTest("disabled addon and invalid level-up payloads cannot celebrate or publish", function()
	local addon = NewLevelUpFixture()
	-- Forever traps division by zero, so constructing NaN here aborts the fixture
	-- before the handler runs. NaN coverage belongs to the offline contracts.
	for _, level in ipairs({ 0, -1, 1.5, false, {}, "invalid", math.huge }) do
		Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", level), false)
	end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", nil), false)
	addon.CanAccessValue = function()
		return false
	end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), false)
	addon.CanAccessValue = nil
	addon.isEnabled = false
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), false)
	Equal(#addon.emotes, 0)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("remote level-up obeys its own toggle independently of quest and chat options", function()
	for _, enabled in ipairs({ false, true }) do
		local addon = NewLevelUpFixture()
		addon.db.profile.emoteOnNearbyPlayerLevelUp = enabled
		addon.db.profile.emoteOnNearbyPlayerQuestCompletion = not enabled
		addon.db.profile.emoteOnLevelUp = false
		addon.db.profile.showChatLogs = false
		addon.db.profile.showChatBubbles = false
		Equal(addon:HandleAnnouncementEvent(LevelUpEvent(), false), true)
		Equal(#addon.emotes, enabled and 1 or 0)
		if enabled then
			Equal(addon.emotes[1].token, "cheer")
			Equal(addon.emotes[1].target, "target")
		end
	end
end)

QuestTogether:RegisterTest("level-up reactions require proximity and obey party-only scope", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.showProgressFor = "party_only"
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 0)
	addon.partyMembers["Friend-Realm"] = { fullName = "Friend-Realm", classFile = "MAGE" }
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.FindNearbyPlayerUnitTokenForSender = function()
		return nil
	end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.db.profile.showProgressFor = "party_nearby"
	addon.partyMembers = {}
	addon.db.profile.devLogAllAnnouncements = true
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.IsAnnouncementSenderNearbyByLocation = function()
		return true
	end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1) -- Coordinates cannot establish visibility in this layer.
	addon.FindVisiblePlayerNameplateForSender = function()
		return {
			GetUnit = function()
				return "nameplate1"
			end,
		}
	end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 2)
	Equal(addon.emotes[2].target, "nameplate1")
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest(
	"level-up wire uses transport identity and suppresses duplicates self and ignored senders",
	function()
		local addon = NewLevelUpFixture()
		addon.FindNearbyPlayerUnitTokenForSender = function(_, _, senderName)
			Equal(senderName, "Friend-Realm")
			return "target"
		end
		local event = LevelUpEvent()
		event.senderName = "Friend-Realm"
		addon.partyMembers["Friend-Realm"] = {}
		local wire = WireEvent(addon, "LVL", event)
		addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Friend-Realm")
		addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, addon.announcementChannelName)
		Equal(#addon.emotes, 1)
		Equal(#addon.printed, 0)
		addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "MyPlayer-Realm")
		addon.IsIgnoredPlayerName = function()
			return true
		end
		addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Ignored-Realm")
		Equal(#addon.emotes, 1)
	end
)

QuestTogether:RegisterTest(
	"remote celebrations require a current visible matching unit even with dev logging",
	function()
		for _, eventType in ipairs({
			"QUEST_COMPLETED",
			"WORLD_QUEST_COMPLETED",
			"BONUS_OBJECTIVE_COMPLETED",
			"PLAYER_LEVEL_UP",
		}) do
			for _, failure in ipairs({
				"coordinates",
				"other layer",
				"gone",
				"recycled GUID",
				"wrong name",
				"not player",
				"restricted",
				"chat restricted",
				"unknown",
				"error",
			}) do
				local addon = NewRemoteCelebrationFixture()
				addon.db.profile.showChatLogs = true
				addon.db.profile.devLogAllAnnouncements = true
				addon.IsAnnouncementSenderNearbyByLocation = function()
					return true
				end
				if failure == "coordinates" then
					addon.FindNearbyPlayerUnitTokenForSender = function()
						return nil
					end
				elseif failure == "other layer" then
					addon.API.CanTargetUnitForEmote = function()
						return false
					end
				elseif failure == "gone" then
					addon.FindNearbyPlayerUnitTokenForSender = function()
						return "target"
					end
					addon.API.UnitExists = function()
						return false
					end
				elseif failure == "recycled GUID" then
					addon.FindNearbyPlayerUnitTokenForSender = function()
						return "target"
					end
					addon.API.UnitGUID = function()
						return "Player-other"
					end
				elseif failure == "wrong name" then
					addon.FindNearbyPlayerUnitTokenForSender = function()
						return "target"
					end
					addon.API.UnitFullName = function()
						return "SomeoneElse", "Realm"
					end
				elseif failure == "not player" then
					addon.FindNearbyPlayerUnitTokenForSender = function()
						return "target"
					end
					addon.API.UnitIsPlayer = function()
						return false
					end
				elseif failure == "restricted" then
					addon.IsRuntimeRestricted = function()
						return true
					end
				elseif failure == "chat restricted" then
					addon.IsRuntimeRestrictionTypeActive = function(_, kind)
						return kind == "chat"
					end
				elseif failure == "unknown" then
					local inaccessible = {}
					addon.CanAccessValue = function(_, value)
						return value ~= inaccessible
					end
					addon.API.CanTargetUnitForEmote = function()
						return inaccessible
					end
				elseif failure == "error" then
					addon.API.CanTargetUnitForEmote = function()
						error("unit unavailable")
					end
				end
				ReceiveCelebration(addon, eventType, "cheer")
				Equal(#addon.emotes, 0)
				if eventType ~= "PLAYER_LEVEL_UP" then
					Equal(#addon.printed, 1)
				end
				Equal(#addon.delayed, 0) -- Never defer a reaction until someone becomes visible.
			end
		end
	end
)

QuestTogether:RegisterTest("remote plate celebrations handle recycled forbidden and unreadable plate units", function()
	for _, failure in ipairs({ "valid", "recycled", "forbidden", "getter error", "unreadable" }) do
		local addon = NewRemoteCelebrationFixture()
		local inaccessible = {}
		addon.CanAccessValue = function(_, value)
			return value ~= inaccessible
		end
		addon.API.UnitExists = function(unit)
			return unit == "nameplate1"
		end
		addon.API.UnitGUID = function()
			return failure == "recycled" and "Player-other" or "Player-friend"
		end
		local plate = {
			IsForbidden = function()
				return failure == "forbidden"
			end,
			GetUnit = function()
				if failure == "forbidden" or failure == "getter error" then
					error("do not read plate")
				end
				return failure == "unreadable" and inaccessible or "nameplate1"
			end,
		}
		addon.FindVisiblePlayerNameplateForSender = function()
			return plate
		end
		ReceiveCelebration(addon, "QUEST_COMPLETED", "cheer")
		Equal(#addon.emotes, failure == "valid" and 1 or 0)
	end
end)

QuestTogether:RegisterTest("self celebrations do not require remote target visibility", function()
	local addon = NewLevelUpFixture()
	addon.API.CanTargetUnitForEmote = function()
		error("self emotes must not use remote targeting")
	end
	addon.API.UnitExists = function()
		return false
	end
	Equal(addon:PlayLocalCompletionEmote("cheer"), true)
	Equal(addon:PlayLocalCelebrationEmote("applaud", "emoteOnLevelUp"), true)
	Equal(#addon.emotes, 2)
	Equal(addon.emotes[1].target, "MyPlayer")
	Equal(addon.emotes[2].target, "MyPlayer")
end)

QuestTogether:RegisterTest("level-up wire rejects other event types", function()
	local addon = NewLevelUpFixture()
	local event = LevelUpEvent()
	event.eventType = "QUEST_COMPLETED"
	addon:OnCommReceived(addon.commPrefix, WireEvent(addon, "LVL", event), "PARTY", "Friend-Realm")
	Equal(#addon.emotes, 0)
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("level-up options migrate existing profiles and preserve disabled values", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.emoteOnLevelUp = nil
	addon.db.profile.emoteOnNearbyPlayerLevelUp = nil
	addon:NormalizeSettingsProfile()
	Equal(addon:GetOption("emoteOnLevelUp"), true)
	Equal(addon:GetOption("emoteOnNearbyPlayerLevelUp"), true)
	addon:SetOption("emoteOnLevelUp", false)
	addon:SetOption("emoteOnNearbyPlayerLevelUp", false)
	addon:NormalizeSettingsProfile()
	Equal(addon:GetOption("emoteOnLevelUp"), false)
	Equal(addon:GetOption("emoteOnNearbyPlayerLevelUp"), false)
end)

QuestTogether:RegisterTest("level-up event registration follows addon enable and disable", function()
	local addon = NewLevelUpFixture()
	local registered = {}
	addon.registeredRuntimeEvents = {}
	addon.eventFrame = {
		RegisterEvent = function(_, name)
			registered[name] = true
		end,
		UnregisterEvent = function(_, name)
			registered[name] = nil
		end,
	}
	addon:RegisterRuntimeEvents()
	Equal(registered.PLAYER_LEVEL_UP, true)
	addon:UnregisterRuntimeEvents()
	Equal(registered.PLAYER_LEVEL_UP, nil)
end)

QuestTogether:RegisterTest("localized announcement metadata and default icon fit a real send", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function()
		return "Алесандра", "Гордунни"
	end
	addon.API.UnitGUID = function()
		return "Player-1602-12345678"
	end
	function addon:GetPlayerClassFile()
		return "DEATHKNIGHT"
	end
	function addon:GetPlayerAnnouncementLocationInfo()
		return { mapID = 2248, zoneName = "Остров Дорн", coordX = 50.1, coordY = 40.2, warMode = false }
	end
	local event = addon:BuildLocalAnnouncementEvent("QUEST_ACCEPTED", "Quest accepted: A normal quest", 12345)
	Equal(event.iconAsset, "Interface/GossipFrame/AvailableQuestIcon")
	Equal(addon:SendAnnouncementWireEvent(event), true)
	local event, command = ReadRecord(addon, addon.wire[1][2])
	local decoded = event
	Equal(command, "ANN")
	Equal(#addon.wire[1][2] <= 255, true)
	Equal(decoded.senderName, "Алесандра-Гордунни")
	Equal(decoded.text, event.text)
	Equal(decoded.zoneName, "Остров Дорн")
	-- Optional decoration must yield to identity and useful text for larger
	-- localized metadata, rather than producing an undecodable empty message.
	event.zoneName = string.rep("Долина", 30)
	event.iconAsset = string.rep("Icon", 40)
	Equal(addon:SendAnnouncementWireEvent(event), true)
	decoded = ReadRecord(addon, addon.wire[2][2])
	Equal(#addon.wire[2][2] <= 255, true)
	Equal(decoded.senderName, event.senderName)
	Equal(decoded.text, event.text)
	Equal(decoded.zoneName, event.zoneName)
	Equal(decoded.mapID, "2248")
	Equal(decoded.coordX, "50.1")
	Equal(decoded.coordY, "40.2")
end)

QuestTogether:RegisterTest("length prefixed text preserves delimiters and UTF8 and rejects NUL", function()
	local a = NewCommsFixture()
	local text = "Дорн, 100% | test\n"
	local decoded = assert(a:DecodeCommRecord("ANN", assert(a:EncodeCommRecord("ANN", Event(text)))))
	Equal(decoded.text, text)
	Equal(a:EncodeCommRecord("ANN", Event(text .. string.char(0))), nil)
	Equal(a:DecodeCommRecord("ANN", "1,QUEST_PROGRESS,old"), nil)
end)

local function InstallResponseClock(addon)
	addon.delayed, addon.responses = {}, {}
	function addon:Respond(operation, record, routes, options)
		options = options or {}
		if options.isCurrent and not options.isCurrent() then
			return false, "cancelled"
		end
		if self.sendFails then
			return false, "capacity"
		end
		self.fixtureResponseSequence = (self.fixtureResponseSequence or 0) + 1
		local frames = assert(self:BuildCommFrames(operation, record, {
			session = "100-1234",
			messageId = tostring(self.fixtureResponseSequence),
			requestId = record.requestId,
			stamp = 1800000000,
		}))
		local copied = assert(self:CopyCommRecord(operation, record))
		self.responses[#self.responses + 1] = { operation = operation, record = copied, options = options }
		self.wire[#self.wire + 1] = { self.commPrefix, frames, routes[1].distribution, routes[1].target }
		if options.onComplete and not self.holdAcceptance then
			options.onComplete(true, "accepted")
		end
		return true
	end
end
local function RunResponseTimer(addon)
	addon.now = addon.now + 1
	addon:ProgressQuestCompareResponses(addon.now)
	return next(addon.questCompareResponseCache or {}) ~= nil
end
local function ReceiveComparison(addon, id, extra)
	local data = extra or {}
	data.requestId = id
	data.requesterName = data.requesterName or "Friend-Realm"
	data.targetName = "MyPlayer-Realm"
	return addon:HandleQuestCompareRequest(data)
end
local function ResponseCount(addon)
	local count = 0
	for _ in pairs(addon.questCompareResponseCache or {}) do
		count = count + 1
	end
	return count
end
local function ComparisonNetwork(count)
	local net = QuestTogether:CreateTestNetwork({ fps = 30, latency = 0.03 })
	local receiver = net:AddPeer("Viewer-Realm", { group = "party" })
	local sender = net:AddPeer("Responder-Realm", { group = "party" })
	function sender:BuildQuestCompareEntries()
		local rows = {}
		for index = 1, count do
			rows[index] = { questId = index, questTitle = "Quest " .. index, isComplete = false, isPushable = true }
		end
		return rows
	end
	for _, peer in ipairs({ receiver, sender }) do
		peer:InitializeCommunications()
		peer.OnCommReceived = peer.ReceiveCommunication
		local frame = net:CreateFrame(peer)
		frame:SetScript("OnUpdate", function()
			peer:UpdateCommunicationRuntime()
		end)
	end
	local result = { entries = {}, completed = 0 }
	local function Request()
		result.entries = {}
		local ok, id = receiver:RequestQuestCompare(sender.name, {
			routes = { { distribution = "WHISPER", target = sender.name, requiresGroup = true } },
			onEntry = function(row)
				result.entries[#result.entries + 1] = row
			end,
			onDone = function()
				result.completed = result.completed + 1
				result.at = net.now
			end,
			onTimeout = function()
				result.timeout = true
			end,
		})
		assert(ok)
		result.id = id
		return id
	end
	return net, sender, receiver, result, Request
end

local function SetComparisonEntries(addon, count)
	function addon:BuildQuestCompareEntries()
		local entries = {}
		for index = 1, count do
			entries[index] = { questId = tostring(index), questTitle = "Quest " .. index, isComplete = false }
		end
		return entries
	end
end

QuestTogether:RegisterTest("comparison send pacing does not consume failed-native-send retries", function()
	local net, sender, receiver, result, request = ComparisonNetwork(2)
	sender:GetTransportState().blockedUntil = sender.now + 5
	request()
	net:Advance(4)
	Equal(result.completed, 0)
	local job = next(sender.questCompareResponseCache or {})
	assert(job)
	net:Advance(10)
	Equal(result.completed, 1)
	Equal(#result.entries, 2)
end)

QuestTogether:RegisterTest("existing channels install filters once and avoid per-packet chat cleanup", function()
	local a = NewCommsFixture()
	local filters, cleanups = 0, 0
	a.announcementChannelChatFiltersRegistered = false
	a.API.AddMessageEventFilter = function()
		filters = filters + 1
	end
	function a:HideAnnouncementChannelFromChatWindows()
		cleanups = cleanups + 1
	end
	function a:IsRuntimeRestricted()
		return false
	end
	for _ = 1, 20 do
		assert(a:EnsureAnnouncementChannelJoined())
	end
	Equal(filters, 3)
	Equal(cleanups, 1)
	a.channelID = 9
	assert(a:EnsureAnnouncementChannelJoined())
	Equal(cleanups, 2)
end)

QuestTogether:RegisterTest("local publication samples one event for wire party chat and local presentation", function()
	local a = NewCommsFixture()
	local builds = 0
	function a:BuildLocalAnnouncementEvent()
		builds = builds + 1
		return { eventType = "QUEST_PROGRESS", senderName = "Me-Realm", text = "sample " .. builds }
	end
	function a:SendAnnouncementWireEvent(event)
		self.sentEvent = event
		return true
	end
	function a:AnnounceToNonQTParty(event)
		self.partyEvent = event
	end
	function a:HandleAnnouncementEvent(event)
		self.localEvent = event
	end
	a.suppressLocalAnnouncementDisplayDuringTests = false
	assert(a:PublishAnnouncementEvent("QUEST_PROGRESS", "Progress"))
	Equal(builds, 1)
	Equal(a.sentEvent, a.partyEvent)
	Equal(a.sentEvent, a.localEvent)
end)

QuestTogether:RegisterTest("oversized or nul-containing inbound transport is rejected before decoding", function()
	local a = NewCommsFixture()
	function a:DeserializeWireMessage()
		error("invalid packet reached parser")
	end
	a:OnCommReceived(a.commPrefix, "ANN|" .. string.rep("x", 252), "PARTY", "Peer-Realm")
	a:OnCommReceived(a.commPrefix, "PING|1,a\0b", "PARTY", "Peer-Realm")
end)

QuestTogether:RegisterTest("quest comparison paces and retries delivery before completing the real receiver", function()
	local net, sender, receiver, result, request = ComparisonNetwork(12)
	local attempts, throttled = 0, false
	net.sendRule = function(packet)
		if packet.sender == sender.name then
			attempts = attempts + 1
			if attempts == 2 then
				throttled = true
				return 3
			end
		end
		return 0
	end
	request()
	net:Advance(30)
	assert(throttled)
	Equal(result.completed, 1)
	Equal(#result.entries, 12)
	Equal(next(receiver.pendingQuestCompareRequests), nil)
end)

-- Full cryptographic vectors and long-running retry/capacity simulations run offline.
QuestTogether:RegisterTest("quest comparison retry exhaustion never advertises a partial result as complete", function()
	local net, sender, receiver, result, request = ComparisonNetwork(3)
	net.deliveryRule = function(packet, peer)
		if peer == receiver then
			return { drop = true }
		end
	end
	request()
	net:Advance(610)
	Equal(result.completed, 0)
	Equal(#result.entries, 0)
	assert(result.timeout)
	Equal(next(receiver.pendingQuestCompareRequests), nil)
end, { offline = true })

QuestTogether:RegisterTest("quest comparison queues expire and old callbacks cannot send after reset", function()
	local a = NewCommsFixture()
	InstallResponseClock(a)
	SetComparisonEntries(a, 3)
	a.sendFails = true
	assert(ReceiveComparison(a, "old"))
	local old = a.questCompareResponseCache
	a:ResetCommsState()
	a.sendFails = false
	a:ProgressQuestCompareResponses(a.now + 601)
	Equal(#a.wire, 0)
	assert(a.questCompareResponseCache ~= old)
	a.isEnabled = false
	Equal(ReceiveComparison(a, "disabled"), false)
end)

QuestTogether:RegisterTest("quest comparison response memory has job and packet bounds", function()
	local a = NewCommsFixture()
	InstallResponseClock(a)
	SetComparisonEntries(a, 1)
	a.holdAcceptance = true
	for i = 1, 16 do
		assert(ReceiveComparison(a, "request-" .. i))
	end
	Equal(ReceiveComparison(a, "overflow"), false)
	Equal(ResponseCount(a), 16)
	for _, response in ipairs(a.responses) do
		response.options.onComplete(true, "accepted")
	end
	Equal(ResponseCount(a), 0)
	assert(ReceiveComparison(a, "next"))
end)

QuestTogether:RegisterTest("oversized mandatory wire identity is rejected rather than truncated", function()
	local net, addon = QuietNetwork()
	local identity = string.rep("Длинное", 100) .. "-Realm"
	local event = Event("1/5 objectives")
	event.senderName = identity
	Equal(addon:SendAnnouncementWireEvent(event), false)
	Equal(addon:EncodeCommRecord("PONG", { requestId = "test", senderName = identity }), nil)
	net:Advance(2)
	Equal(#addon.sent, 0)
end)

-- Full cryptographic vectors and long-running retry/capacity simulations run offline.
QuestTogether:RegisterTest("completed comparisons release domain capacity for repeated empty-log refreshes", function()
	local net, sender, receiver, result, request = ComparisonNetwork(0)
	for i = 1, 20 do
		request()
		net:Advance(3)
		Equal(result.completed, i)
	end
	Equal(ResponseCount(sender), 0)
	Equal(#sender.commTransferState.outgoing, 0)
end, { offline = true })

QuestTogether:RegisterTest(
	"ordinary comparison completes within the shared budget without legacy packet pacing",
	function()
		local net, _, _, result, request = ComparisonNetwork(25)
		request()
		net:Advance(20)
		Equal(result.completed, 1)
		Equal(#result.entries, 25)
		assert(result.at < 120)
	end
)

QuestTogether:RegisterTest("failed comparison sends back off longer than successful packet pacing", function()
	local net, sender, _, result, request = ComparisonNetwork(2)
	local failedAt, nextAt
	net.sendRule = function(packet)
		if packet.sender == sender.name then
			if not failedAt then
				failedAt = net.now
				return 3
			end
			nextAt = nextAt or net.now
		end
		return 0
	end
	request()
	net:Advance(20)
	assert(nextAt - failedAt >= 1)
	Equal(result.completed, 1)
end)

QuestTogether:RegisterTest("queued group comparisons stop when requester leaves the roster", function()
	local net, sender, receiver, result, request = ComparisonNetwork(30)
	sender:GetTransportState().blockedUntil = sender.now + 10
	request()
	net:Advance(2)
	net:SetGroup(receiver, nil)
	net:Advance(12)
	Equal(result.completed, 0)
	Equal(#result.entries, 0)
	Equal(ResponseCount(sender), 0)
end)

QuestTogether:RegisterTest("private comparisons are independent from public channel identifiers", function()
	local net, sender, receiver, result, request = ComparisonNetwork(4)
	request()
	receiver.announcementChannelLocalID = 99
	sender.announcementChannelLocalID = 42
	net:Advance(10)
	Equal(result.completed, 1)
	local accepted = 0
	for _, row in ipairs(net.trace) do
		if row.kind == "accepted" then
			accepted = accepted + 1
			Equal(row.packet.route, "WHISPER")
		end
	end
	assert(accepted > 0)
end)

QuestTogether:RegisterTest("group comparisons remain private after party becomes raid", function()
	local net, sender, receiver, result, request = ComparisonNetwork(2)
	request()
	net:Advance(10)
	Equal(result.completed, 1)
	receiver.groupDistribution, sender.groupDistribution = "RAID", "RAID"
	request()
	net:Advance(10)
	Equal(result.completed, 2)
end)

QuestTogether:RegisterTest("comparison snapshots wait for both quest count and every row before sending", function()
	local a = NewCommsFixture()
	InstallResponseClock(a)
	local phase = 0
	a.IsWorkBlocked = function()
		return false
	end
	a.API.GetNumQuestLogEntries = function()
		return phase > 0 and 2 or nil
	end
	a.API.GetQuestLogInfo = function(i)
		if i == 2 and phase < 2 then
			return
		end
		return { questID = i, title = "Quest " .. i }
	end
	a.GetQuestShareableStatusLabel = function()
		return "No"
	end
	assert(ReceiveComparison(a, "loading"))
	Equal(#a.wire, 0)
	phase = 1
	RunResponseTimer(a)
	Equal(#a.wire, 0)
	phase = 2
	RunResponseTimer(a)
	Equal(#a.responses, 1)
	Equal(a.responses[1].record.count, 2)
	Equal(#a.responses[1].record.entries, 2)
	Equal(ResponseCount(a), 0)
end)

QuestTogether:RegisterTest(
	"unavailable comparison count exhausts bounded snapshot retries without completion",
	function()
		local a = NewCommsFixture()
		InstallResponseClock(a)
		local reads = 0
		a.IsWorkBlocked = function()
			return false
		end
		a.API.GetNumQuestLogEntries = function()
			reads = reads + 1
			return nil
		end
		assert(ReceiveComparison(a, "unavailable"))
		for _ = 1, 10 do
			RunResponseTimer(a)
		end
		Equal(reads, 5)
		Equal(#a.responses, 1)
		Equal(a.responses[1].operation, "ERROR")
	end
)

QuestTogether:RegisterTest("missing comparison rows cannot become a certified partial quest log", function()
	local a = NewCommsFixture()
	InstallResponseClock(a)
	local missing = 0
	a.IsWorkBlocked = function()
		return false
	end
	a.API.GetNumQuestLogEntries = function()
		return 2
	end
	a.API.GetQuestLogInfo = function(i)
		if i == 2 then
			missing = missing + 1
			return
		end
		return { questID = 123, title = "Readable quest" }
	end
	a.GetQuestShareableStatusLabel = function()
		return "No"
	end
	assert(ReceiveComparison(a, "partial"))
	for _ = 1, 10 do
		RunResponseTimer(a)
	end
	Equal(missing, 5)
	Equal(#a.responses, 1)
	Equal(a.responses[1].operation, "ERROR")
end)

QuestTogether:RegisterTest("a readable empty quest log still completes a comparison", function()
	local a = NewCommsFixture()
	InstallResponseClock(a)
	a.IsWorkBlocked = function()
		return false
	end
	a.API.GetNumQuestLogEntries = function()
		return 0
	end
	assert(ReceiveComparison(a, "empty"))
	Equal(#a.responses, 1)
	Equal(a.responses[1].operation, "QCRS")
	Equal(a.responses[1].record.count, 0)
end)

QuestTogether:RegisterTest("comparison snapshots defer restricted reads and reject changing counts", function()
	local addon = NewCommsFixture()
	local blocked, reads = true, 0
	addon.IsWorkBlocked = function()
		return blocked
	end
	addon.API.GetNumQuestLogEntries = function()
		reads = reads + 1
		return reads == 1 and 0 or 1
	end
	Equal(addon:BuildQuestCompareEntries(), nil)
	Equal(reads, 0)
	blocked = false
	Equal(addon:BuildQuestCompareEntries(), nil)
	Equal(reads, 2)
end)

QuestTogether:RegisterTest("self comparison reports an unavailable snapshot without claiming completion", function()
	local a = NewCommsFixture()
	a.IsWorkBlocked = function()
		return false
	end
	a.API.GetNumQuestLogEntries = function()
		return nil
	end
	Equal(a:RequestQuestCompare("MyPlayer-Realm"), false)
	Equal(#a.printed, 0)
end)

QuestTogether:RegisterTest(
	"comparison snapshots wait for missing blank and inaccessible visible quest titles",
	function()
		local a = NewCommsFixture()
		InstallResponseClock(a)
		local phase = 0
		a.IsWorkBlocked = function()
			return false
		end
		a.API.GetNumQuestLogEntries = function()
			return 1
		end
		a.API.GetQuestLogInfo = function()
			return { questID = 123, title = ({ [1] = "   ", [2] = "inaccessible", [3] = "Loaded quest" })[phase] }
		end
		a.CanAccessValue = function(_, v)
			return v ~= "inaccessible"
		end
		a.GetQuestShareableStatusLabel = function()
			return "No"
		end
		assert(ReceiveComparison(a, "title"))
		Equal(#a.wire, 0)
		for i = 1, 2 do
			phase = i
			RunResponseTimer(a)
			Equal(#a.wire, 0)
		end
		phase = 3
		RunResponseTimer(a)
		Equal(#a.responses, 1)
		Equal(a.responses[1].record.entries[1].questTitle, "Loaded quest")
	end
)

QuestTogether:RegisterTest("comparison snapshots can omit explicitly known header and hidden rows", function()
	local addon = NewCommsFixture()
	addon.IsWorkBlocked = function()
		return false
	end
	addon.API.GetNumQuestLogEntries = function()
		return 2
	end
	addon.API.GetQuestLogInfo = function(index)
		if index == 1 then
			return { isHeader = true }
		end
		return { questID = 123, isHidden = true }
	end
	local entries = addon:BuildQuestCompareEntries()
	Equal(type(entries), "table")
	Equal(#entries, 0)
end)

local function NewSnapshotComparisonFixture()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local clock = addon:CreateTestClock(100)
	addon.restrictions = {}
	addon.questReads = 0
	addon.API.GetTime = function()
		return clock:GetTime()
	end
	addon.API.Delay = function(seconds, callback)
		clock:After(seconds, callback)
	end
	addon.API.InCombatLockdown = function()
		return addon.restrictions.combat == true
	end
	addon.API.IsWorldMapVisible = function()
		return addon.restrictions.map == true
	end
	addon.IsRuntimeRestrictionTypeActive = function(_, restrictionType)
		return addon.restrictions[restrictionType] == true
	end
	addon.API.GetNumQuestLogEntries = function()
		Equal(addon:IsWorkBlocked("quest_snapshot_refresh"), false)
		addon.questReads = addon.questReads + 1
		if addon.snapshotUnavailable then
			return nil
		end
		return 1
	end
	addon.API.GetQuestLogInfo = function()
		Equal(addon:IsWorkBlocked("quest_snapshot_refresh"), false)
		return { questID = 123, title = "Readable quest", isComplete = false }
	end
	addon.GetTrackedQuestStatusState = function()
		return { isOnQuest = true }
	end
	addon.API.IsPushableQuest = function()
		return nil
	end
	addon.partyMembers["Friend-Realm"] = {}
	local advance = clock.Advance
	function clock:Advance(dt)
		advance(self, dt)
		addon.now = self:GetTime()
		addon:ProgressQuestCompareResponses(addon.now)
	end
	return addon, clock
end

local function ReceiveSnapshotComparisonRequest(addon, id)
	return ReceiveComparison(addon, id, { partyOnly = true })
end

QuestTogether:RegisterTest("queued comparisons recover after long combat map and encounter restrictions", function()
	for _, restriction in ipairs({ "combat", "map", "encounter" }) do
		local a, clock = NewSnapshotComparisonFixture()
		a.restrictions[restriction] = true
		assert(ReceiveSnapshotComparisonRequest(a, restriction))
		for _ = 1, 12 do
			clock:Advance(1)
		end
		Equal(ResponseCount(a), 1)
		Equal(a.questReads, 0)
		Equal(#a.responses, 0)
		a.restrictions[restriction] = nil
		clock:Advance(1)
		Equal(#a.responses, 1)
		Equal(a.responses[1].record.entries[1].questId, 123)
		Equal(ResponseCount(a), 0)
	end
end)

QuestTogether:RegisterTest("restriction deferrals preserve the bounded unavailable snapshot retry budget", function()
	local a, clock = NewSnapshotComparisonFixture()
	a.snapshotUnavailable = true
	ReceiveSnapshotComparisonRequest(a, "unavailable")
	clock:Advance(1)
	clock:Advance(1)
	Equal(a.questReads, 3)
	a.restrictions.combat = true
	for _ = 1, 12 do
		clock:Advance(1)
	end
	Equal(a.questReads, 3)
	a.restrictions.combat = nil
	clock:Advance(1)
	clock:Advance(1)
	Equal(a.questReads, 5)
	Equal(#a.responses, 1)
	Equal(a.responses[1].operation, "ERROR")
end)

QuestTogether:RegisterTest("restricted comparison jobs still expire without reading or sending", function()
	local a, clock = NewSnapshotComparisonFixture()
	a.restrictions.map = true
	ReceiveSnapshotComparisonRequest(a, "expired")
	clock:Advance(179)
	Equal(ResponseCount(a), 1)
	clock:Advance(1)
	Equal(ResponseCount(a), 0)
	a.restrictions.map = nil
	clock:Advance(10)
	Equal(a.questReads, 0)
	Equal(#a.wire, 0)
	Equal(#clock.timers, 0)
end)

QuestTogether:RegisterTest("restricted comparison callbacks cannot revive canceled or disabled work", function()
	local a, clock = NewSnapshotComparisonFixture()
	a.restrictions.combat = true
	ReceiveSnapshotComparisonRequest(a, "old")
	local old = a.questCompareResponseCache
	a:ResetCommsState()
	ReceiveSnapshotComparisonRequest(a, "new")
	assert(a.questCompareResponseCache ~= old)
	a.isEnabled = false
	a.restrictions.combat = nil
	clock:Advance(10)
	Equal(a.questReads, 0)
	Equal(#a.wire, 0)
	Equal(ResponseCount(a), 0)
end)

QuestTogether:RegisterTest("comparison source wire and display preserve all three shareability states", function()
	for _, expected in ipairs({ "Yes", "No", "Unknown" }) do
		local a = NewSnapshotComparisonFixture()
		a.API.IsPushableQuest = function()
			if expected == "Yes" then
				return true
			elseif expected == "No" then
				return false
			end
		end
		a.GetQuestStatusLabel = function()
			return "Not Started"
		end
		a.BuildChatLogQuestLabel = function(_, _, title)
			return title
		end
		local entry = a:BuildQuestCompareEntries()[1]
		local copied = assert(a:CopyCommRecord("QCENTRY", entry))
		copied.classFile = "MAGE"
		Equal(copied.questId, 123)
		Equal(a:GetQuestCompareShareableToYouLabel(copied.isPushable), expected)
		Equal(
			a:BuildQuestCompareMessage("Friend-Realm", copied),
			"Readable quest | Them: In Progress | You: Not Started | Shareable to You: " .. expected
		)
	end
end)

QuestTogether:RegisterTest(
	"comparison codecs reject obsolete wire layouts while preserving typed optional booleans",
	function()
		local a = NewCommsFixture()
		for _, prefix in ipairs({ "QCMP", "QCQE", "QCOB", "QCDN" }) do
			Equal(a:DecodeCommFrame(prefix .. "|1,legacy,Friend-Realm,123,Old quest"), nil)
		end
		for _, value in ipairs({ true, false, "unknown" }) do
			local row = assert(
				a:CopyCommRecord(
					"QCENTRY",
					{ questId = 123, questTitle = "Quest", isPushable = value ~= "unknown" and value or nil }
				)
			)
			Equal(row.isPushable, value ~= "unknown" and value or nil)
		end
	end
)

local function NewLocationReceiver()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function()
		return "Receiver", "Realm"
	end
	addon.API.UnitName = function()
		return "Receiver"
	end
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.db.profile.showProgressFor = "party_nearby"
	addon.db.profile.showChatLogs = true
	addon.db.profile.showChatBubbles = false
	addon.FindVisiblePlayerNameplateForSender = function()
		return nil
	end
	addon.FindNearbyPlayerUnitTokenForSender = function()
		return nil
	end
	function addon:IsRuntimeRestricted()
		return false
	end
	function addon:GetLocationPinMapWorldSize()
		return 4000, 2000
	end
	return addon
end

QuestTogether:RegisterTest("announcement map identity survives local construction and wire round trip", function()
	local addon = NewCommsFixture()
	addon.GetPlayerAnnouncementLocationInfo = function()
		return { mapID = 37, zoneName = "Elwynn Forest", coordX = 50, coordY = 50, warMode = false }
	end
	local event = addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123, { emoteToken = "CHEER" })
	Equal(event.mapID, "37")
	Equal(addon:SendAnnouncementWireEvent(event), true)
	local event, command = ReadRecord(addon, addon.wire[1][2])
	local received = event
	Equal(command, "ANN")
	Equal(received.mapID, "37")
	Equal(received.emoteToken, "CHEER", "appending map identity must not move old fields")
	Equal(#addon.wire[1][2] <= 255, true)
end)

QuestTogether:RegisterTest("received nearby announcements use map identity across localized labels", function()
	local cases = {
		{ remoteID = 37, localID = 37, remoteName = "Elwynn Forest", localName = "Wald von Elwynn", visible = true },
		{ remoteID = 37, localID = 99999, remoteName = "Same label", localName = "Same label", visible = false },
		{ remoteID = 37, localID = 37, remoteName = "", localName = "", visible = true },
		{
			remoteID = 37,
			localID = 37,
			remoteName = "Same label",
			localName = "Same label",
			far = true,
			visible = false,
		},
		{
			remoteID = 37,
			localID = 37,
			remoteName = "Same label",
			localName = "Same label",
			differentWarMode = true,
			visible = false,
		},
		{ localID = 37, remoteName = "Legacy label", localName = "Legacy label", visible = true },
		{ remoteID = 37, remoteName = "Legacy label", localName = "Legacy label", visible = true },
		{ remoteName = "Different label", localName = "Legacy label", visible = false },
	}
	for _, case in ipairs(cases) do
		local sender, receiver = NewCommsFixture(), NewLocationReceiver()
		sender.GetPlayerAnnouncementLocationInfo = function()
			return { mapID = case.remoteID, zoneName = case.remoteName, coordX = 50, coordY = 50, warMode = false }
		end
		receiver.GetPlayerAnnouncementLocationInfo = function()
			return {
				mapID = case.localID,
				zoneName = case.localName,
				coordX = case.far and 90 or 50,
				coordY = 50,
				warMode = case.differentWarMode == true,
			}
		end
		local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
		Equal(sender:SendAnnouncementWireEvent(event), true)
		receiver:OnCommReceived(
			receiver.commPrefix,
			sender.wire[1][2],
			"CHANNEL",
			"MyPlayer-Realm",
			7,
			receiver.announcementChannelName
		)
		Equal(#receiver.printed, case.visible and 1 or 0)
	end
end)

QuestTogether:RegisterTest("announcement map metadata rejects invalid IDs and old layouts", function()
	local a = NewCommsFixture()
	Equal(a:DecodeCommRecord("ANN", "3,QUEST_PROGRESS,Player-1,MAGE,Friend,Old,123"), nil)
	for _, invalid in ipairs({ "0", "-1", "1.5", "nan", "inf", "garbage", "" }) do
		local event = Event()
		event.mapID = invalid
		Equal(a:SanitizeAnnouncementEventData(event).mapID, "")
	end
	local secret = setmetatable({}, {
		__tostring = function()
			error("secret")
		end,
	})
	a.CanAccessValue = function(_, value)
		return value ~= secret
	end
	local event = Event()
	event.mapID = secret
	Equal(a:SanitizeAnnouncementEventData(event).mapID, "")
end)

QuestTogether:RegisterTest(
	"announcement packet fitting retains numeric location when display labels are too large",
	function()
		local sender, receiver = NewCommsFixture(), NewLocationReceiver()
		sender.GetPlayerAnnouncementLocationInfo = function()
			return { mapID = 2248, zoneName = string.rep("Долина", 40), coordX = 50, coordY = 50, warMode = false }
		end
		receiver.GetPlayerAnnouncementLocationInfo = function()
			return { mapID = 2248, zoneName = "Isle of Dorn", coordX = 50, coordY = 50, warMode = false }
		end
		local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
		Equal(sender:SendAnnouncementWireEvent(event), true)
		local wire = sender.wire[1][2]
		Equal(#wire <= 255, true)
		local received = ReadRecord(sender, wire)
		Equal(received.zoneName, event.zoneName)
		Equal(received.mapID, "2248")
		Equal(received.coordX, "50.0")
		Equal(received.coordY, "50.0")
		Equal(received.warMode, "0")
		receiver:OnCommReceived(
			receiver.commPrefix,
			wire,
			"CHANNEL",
			"MyPlayer-Realm",
			7,
			receiver.announcementChannelName
		)
		Equal(#receiver.printed, 1)
	end
)

local function NewBubblePreviewFixture()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.db.profile.showChatBubbles = true
	addon.db.profile.showChatLogs = false
	addon.partyMembers["Target-Realm"] = {}
	addon.API.UnitFullName = function(unit)
		return unit == "player" and "MyPlayer" or "Target", "Realm"
	end
	addon.API.UnitGUID = function(unit)
		return unit == "player" and "Player-self" or "Player-target"
	end
	addon.API.UnitExists = function(unit)
		return unit == "target" or unit == "nameplate1" or unit == "player"
	end
	addon.API.UnitIsPlayer = function()
		return true
	end
	addon.IsWorkBlocked = function()
		return false
	end
	local plate = {
		UnitFrame = { unit = "nameplate1" },
		GetUnit = function()
			return "nameplate1"
		end,
	}
	addon.ForEachVisibleNamePlate = function(_, callback)
		callback(plate)
	end
	addon.bubbles = {}
	addon.ShowAnnouncementBubbleOnNameplate = function(_, frame, text)
		Equal(frame, plate)
		addon.bubbles[#addon.bubbles + 1] = text
		return true
	end
	return addon
end

QuestTogether:RegisterTest("bubbletest previews target locally without broadcasting another identity", function()
	local addon = NewBubblePreviewFixture()
	local ok, name = addon:SendBubbleAnnouncementTest("Local target preview")
	Equal(ok, true)
	Equal(name, "Target-Realm")
	Equal(#addon.wire, 0)
	Equal(#addon.bubbles, 1)
	Equal(addon.bubbles[1], "Local target preview")
	addon.API.UnitExists = function(unit)
		return unit == "nameplate1" or unit == "player"
	end
	ok, name = addon:SendBubbleAnnouncementTest("Explicit player preview", "Target-Realm")
	Equal(ok, true)
	Equal(name, "Target-Realm")
	Equal(#addon.wire, 0)
	Equal(#addon.bubbles, 2)
end)

QuestTogether:RegisterTest("local bubble previews do not depend on transport and report suppression", function()
	local addon = NewBubblePreviewFixture()
	addon.SendAnnouncementWireEvent = function()
		error("a local preview must not use the network")
	end
	Equal(addon:SendBubbleAnnouncementTest("Local preview"), true)
	addon.db.profile.announceProgress = false
	local ok, message = addon:SendBubbleAnnouncementTest("Suppressed preview")
	Equal(ok, false)
	Equal(message, "The local preview was suppressed by your announcement settings.")
	Equal(#addon.bubbles, 1)
end)

local function NewBubbleSlashFixture(regional, hasTarget)
	local addon = NewBubblePreviewFixture()
	addon.messages = {}
	addon.Print = function(_, message)
		addon.messages[#addon.messages + 1] = message
	end
	addon.GetDebugController = function()
		return {
			HandleCommand = function()
				return false
			end,
		}
	end
	addon.API.RegionalUniqueNamesEnabled = function()
		return regional
	end
	addon.API.ShouldDisplaySurname = function()
		return false
	end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "nameplate1" or unit == "nameplate2" or (hasTarget and unit == "target")
	end
	addon.API.UnitFullName = function(unit)
		if not regional then
			return unit == "player" and "MyPlayer" or "Target", "Realm"
		end
		if unit == "player" then
			return "MyPlayer", "Selfname"
		end
		return "Anakin", unit == "nameplate2" and "Elsewhere" or "Othername"
	end
	addon.API.UnitName = function(unit)
		return unit == "player" and "MyPlayer" or (regional and "Anakin" or "Target")
	end
	addon.API.UnitGUID = function(unit)
		return unit == "player" and "Player-self" or (unit == "nameplate2" and "Player-other" or "Player-target")
	end
	if regional then
		-- The other character with the same first name appears first, so a
		-- weakened first-name lookup would render on the wrong private frame.
		local firstPlate = addon.ForEachVisibleNamePlate
		local otherPlate = {
			UnitFrame = { unit = "nameplate2" },
			GetUnit = function()
				return "nameplate2"
			end,
		}
		addon.ForEachVisibleNamePlate = function(self, callback)
			callback(otherPlate)
			firstPlate(self, callback)
		end
	end
	return addon
end

QuestTogether:RegisterTest("bubbletest slash accepts full regional quoted and legacy identities", function()
	for _, command in ipairs({
		"bubbletest Anakin Othername hello there",
		"preview announcement Anakin Othername hello there",
		"bubbletest Anakin   Othername hello there",
		'bubbletest "Anakin Othername" hello there',
		'preview announcement "Anakin Othername" hello there',
		"bubbletest Anakin-Othername hello there",
	}) do
		local addon = NewBubbleSlashFixture(true, false)
		addon:HandleSlashCommand(command)
		Equal(#addon.bubbles, 1)
		Equal(addon.bubbles[1], "hello there")
		Equal(#addon.wire, 0)
		Equal(addon.messages[#addon.messages], "Ran local bubble preview for Anakin Othername")
	end
	local addon = NewBubbleSlashFixture(true, false)
	Equal(addon:SendBubbleAnnouncementTest("Direct preview", "Anakin Othername"), true)
	Equal(#addon.bubbles, 1)
	Equal(addon.bubbles[1], "Direct preview")
end)

QuestTogether:RegisterTest("bubbletest slash retains retail single-token and quoted player names", function()
	for _, command in ipairs({
		"bubbletest Target hello there",
		"bubbletest Target-Realm hello there",
		"preview announcement Target-Realm hello there",
		'bubbletest "Target-Realm" hello there',
		'preview announcement "Target-Realm" hello there',
	}) do
		local addon = NewBubbleSlashFixture(false, false)
		addon:HandleSlashCommand(command)
		Equal(#addon.bubbles, 1)
		Equal(addon.bubbles[1], "hello there")
		Equal(#addon.wire, 0)
	end
end)

QuestTogether:RegisterTest(
	"bubbletest slash keeps complete target text including quotes and player-like words",
	function()
		for _, regional in ipairs({ false, true }) do
			local addon = NewBubbleSlashFixture(regional, true)
			local text = '"Anakin Othername" Hello THERE'
			addon:HandleSlashCommand("preview ANNOUNCEMENT " .. text)
			Equal(#addon.bubbles, 1)
			Equal(addon.bubbles[1], text)
			Equal(#addon.wire, 0)
		end
	end
)

QuestTogether:RegisterTest("bubbletest slash rejects malformed names empty text and ambiguous first names", function()
	for _, regional in ipairs({ false, true }) do
		for _, arguments in ipairs({
			'"" hello',
			'"   " hello',
			'"Anakin Othername hello',
			'"Anakin Othername"hello',
			'"Anakin Othername"',
			'"Anakin Othername"   ',
			"Target-Realm",
		}) do
			local addon = NewBubbleSlashFixture(regional, false)
			addon:HandleSlashCommand("bubbletest " .. arguments)
			Equal(#addon.bubbles, 0)
			Equal(#addon.wire, 0)
			Equal(addon.messages[#addon.messages], 'Usage without a target: /qt preview announcement "<player>" <text>')
		end
	end
	for _, arguments in ipairs({ '"Anakin" hello there', "Anakin hello there" }) do
		local addon = NewBubbleSlashFixture(true, false)
		addon:HandleSlashCommand("bubbletest " .. arguments)
		Equal(#addon.bubbles, 0)
		Equal(#addon.wire, 0)
		Equal(addon.messages[#addon.messages], "No visible nearby player matched that name.")
	end
end)

-- Full cryptographic vectors and long-running retry/capacity simulations run offline.
QuestTogether:RegisterTest(
	"rapid party comparison refreshes supersede obsolete peer responses and complete the newest session",
	function()
		local net, sender, receiver, result, request = ComparisonNetwork(35)
		local ids = {}
		for i = 1, 4 do
			if ids[i - 1] then
				receiver:ClearPendingQuestCompare(ids[i - 1], receiver:GetPendingQuestCompare(ids[i - 1]))
			end
			ids[i] = request()
			net:Advance(0.3)
		end
		net:Advance(40)
		Equal(result.completed, 1)
		Equal(#result.entries, 35)
		for _, id in ipairs(ids) do
			Equal(receiver:GetPendingQuestCompare(id), nil)
		end
	end,
	{ offline = true }
)

QuestTogether:RegisterTest("comparison transactions isolate equal request IDs by authenticated sender", function()
	local a = NewCommsFixture()
	InstallResponseClock(a)
	SetComparisonEntries(a, 1)
	a.holdAcceptance = true
	for _, sender in ipairs({ "Alpha-Realm", "Beta-Realm", "Gamma-Realm", "Delta-Realm" }) do
		assert(ReceiveComparison(a, "same-id", { requesterName = sender }))
	end
	Equal(ResponseCount(a), 4)
	local alpha = a.questCompareResponseCache["Alpha-Realm:same-id"]
	assert(ReceiveComparison(a, "same-id", { requesterName = "Alpha-Realm" }))
	Equal(a.questCompareResponseCache["Alpha-Realm:same-id"], alpha)
	Equal(#a.responses, 4)
	assert(ReceiveComparison(a, "new", { requesterName = "Alpha-Realm" }))
	Equal(ResponseCount(a), 5)
end)

QuestTogether:RegisterTest("restricted comparison requests share the runtime clock and cannot survive reset", function()
	local a, clock = NewSnapshotComparisonFixture()
	a.restrictions.combat = true
	ReceiveSnapshotComparisonRequest(a, "first")
	ReceiveSnapshotComparisonRequest(a, "second")
	Equal(ResponseCount(a), 2)
	Equal(a.questReads, 0)
	Equal(#clock.timers, 0)
	a:ResetCommsState()
	a.restrictions.combat = nil
	clock:Advance(2)
	Equal(#a.wire, 0)
	Equal(ResponseCount(a), 0)
end)

local function PartyChatFixture()
	local addon = NewCommsFixture()
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.qtPlayerPresenceState = { peers = {} }
	function addon:IsRuntimeRestrictionTypeActive()
		return self.chatRestricted == true
	end
	addon.chatMessages, addon.members = {}, { party1 = "Friend-Realm" }
	addon.partyOption, addon.eventOption = true, true
	addon.db = { profile = { hidePartyChatReminder = true } }
	function addon:GetOption(key)
		if key == "hidePartyChatReminder" then
			return self.db.profile.hidePartyChatReminder
		end
		if key == "announceToNonQTParty" then
			return self.partyOption
		end
		if key == "announceProgress" then
			return self.eventOption
		end
		return false
	end
	function addon:GetUnitFullName(unit)
		return self.members[unit]
	end
	addon.API.UnitExists = function(unit)
		return addon.members[unit] ~= nil
	end
	addon.API.IsInParty = function()
		return true
	end
	addon.API.SendPartyChatMessage = function(text, route)
		addon.chatMessages[#addon.chatMessages + 1] = { text, route }
		return true
	end
	return addon
end

QuestTogether:RegisterTest("party announcements require a currently unidentified party member", function()
	local a = PartyChatFixture()
	local event = { eventType = "QUEST_PROGRESS", text = "Wolves: 2/8" }
	Equal(QuestTogether.DEFAULTS.profile.announceToNonQTParty, true)
	Equal(a:AnnounceToNonQTParty(event), true)
	Equal(a.chatMessages[1][1], "[QT] Wolves: 2/8")
	Equal(a.chatMessages[1][2], "PARTY")
	a:RecordQTPlayerPresence("Friend-Realm", true)
	Equal(a:AnnounceToNonQTParty(event), false)
	a.members.party2 = "Other-Realm"
	Equal(a:AnnounceToNonQTParty(event), true)
	a.members.party2 = nil
	Equal(a:AnnounceToNonQTParty(event), false)
	Equal(#a.chatMessages, 2)
end)

local function ReminderFixture()
	local a = PartyChatFixture()
	a.db.profile.hidePartyChatReminder = false
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:RenderPartyChatReminder(request)
		self.rendered = request
	end
	function a:RefreshOptionsWindow() end
	function a:SetOption(key, value)
		if key == "announceToNonQTParty" then
			self.partyOption = value
		else
			self.db.profile[key] = value
		end
		return true
	end
	return a
end

QuestTogether:RegisterTest("party reminder gates forwarding until acknowledged and rearms for new members", function()
	local a, event = ReminderFixture(), { eventType = "QUEST_PROGRESS", text = "Progress" }
	Equal(QuestTogether.DEFAULTS.profile.hidePartyChatReminder, false)
	Equal(a:AnnounceToNonQTParty(event), false)
	Equal(a.rendered, nil)
	a.now = 109
	Equal(a:UpdatePartyChatReminder(), false)
	Equal(a.rendered, nil)
	a.now = 110
	Equal(a:UpdatePartyChatReminder(), false)
	local request = a.rendered
	Equal(request.names[1], "Friend-Realm")
	Equal(a:AcknowledgePartyChatReminder(request, false, false), true)
	Equal(a:AnnounceToNonQTParty(event), true)
	Equal(#a.chatMessages, 1) -- Nothing queued or replayed from before acknowledgement.
	a.blocked = true
	Equal(a:AnnounceToNonQTParty(event), true) -- UI restrictions do not revoke acknowledgement.
	a.blocked = false
	Equal(a:UpdatePartyChatReminder(), true)
	a.members.party2 = "New-Realm"
	Equal(a:AnnounceToNonQTParty(event), false)
	a.now = 120
	a:UpdatePartyChatReminder()
	Equal(a.rendered.names[1], "New-Realm")
	a:RecordQTPlayerPresence("New-Realm", true)
	Equal(a:UpdatePartyChatReminder(), true)
	Equal(a.rendered, nil)
	a.members = {}
	a:UpdatePartyChatReminder()
	a.members.party1 = "Friend-Realm"
	Equal(a:UpdatePartyChatReminder(), false)
end)

QuestTogether:RegisterTest("party reminder choices persist only on valid acknowledgement", function()
	for _, off in ipairs({ false, true }) do
		local a = ReminderFixture()
		a:UpdatePartyChatReminder()
		a.now = 110
		a:UpdatePartyChatReminder()
		Equal(a:AcknowledgePartyChatReminder(a.rendered, true, off), true)
		Equal(a.db.profile.hidePartyChatReminder, true)
		Equal(a.partyOption, not off)
		a:ResetPartyChatReminder()
		Equal(a:UpdatePartyChatReminder(), not off)
	end
	for _, stale in ipairs({ "profile", "leave", "known", "off", "disabled", "restricted", "unreadable" }) do
		local a = ReminderFixture()
		a:UpdatePartyChatReminder()
		a.now = 110
		a:UpdatePartyChatReminder()
		local old = a.rendered
		if stale == "profile" then
			a.db.profile = { hidePartyChatReminder = false }
		elseif stale == "leave" then
			a.members = {}
		elseif stale == "known" then
			a:RecordQTPlayerPresence("Friend-Realm", true)
		elseif stale == "off" then
			a.partyOption = false
		elseif stale == "disabled" then
			a.isEnabled = false
		elseif stale == "restricted" then
			a.blocked = true
		else
			a.API.UnitExists = function()
				return nil
			end
		end
		Equal(a:AcknowledgePartyChatReminder(old, true, false), false)
		Equal(a.db.profile.hidePartyChatReminder, false)
	end
end)

QuestTogether:RegisterTest("party reminder cancels discovery candidates and handles clock resets", function()
	local a = ReminderFixture()
	a:UpdatePartyChatReminder()
	a.now = 105
	a:RecordQTPlayerPresence("Friend-Realm", true)
	Equal(a:UpdatePartyChatReminder(), true)
	Equal(a.rendered, nil)
	a:RecordQTPlayerPresence("Friend-Realm", false)
	a:UpdatePartyChatReminder()
	a.now = 115
	a:UpdatePartyChatReminder()
	local old = a.rendered
	a.now = 10
	Equal(a:AcknowledgePartyChatReminder(old, true, false), false)
	Equal(a.rendered, nil)
	a.now = 20
	a:UpdatePartyChatReminder()
	assert(a.rendered ~= old)
	a:ResetCommsState()
	Equal(a.partyChatReminderState, nil)
end)

QuestTogether:RegisterTest("party announcements honor options group routes and unreadable identities", function()
	local event = { eventType = "QUEST_PROGRESS", text = "Progress" }
	for _, scenario in ipairs({
		"off",
		"eventOff",
		"disabled",
		"restricted",
		"solo",
		"raid",
		"unknownRaid",
		"unknownMember",
		"unknownName",
		"tests",
	}) do
		local a = PartyChatFixture()
		if scenario == "off" then
			a.partyOption = false
		elseif scenario == "eventOff" then
			a.eventOption = false
		elseif scenario == "disabled" then
			a.isEnabled = false
		elseif scenario == "restricted" then
			a.chatRestricted = true
		elseif scenario == "solo" then
			a.API.IsInParty = function()
				return false
			end
		elseif scenario == "raid" then
			a.API.IsInRaid = function()
				return true
			end
		elseif scenario == "unknownRaid" then
			a.API.IsInRaid = function()
				error("unavailable")
			end
		elseif scenario == "unknownMember" then
			a.API.UnitExists = function()
				return nil
			end
		elseif scenario == "unknownName" then
			a.GetUnitFullName = function()
				return nil
			end
		else
			a.suppressLocalAnnouncementDisplayDuringTests = true
		end
		Equal(a:AnnounceToNonQTParty(event), false)
		Equal(#a.chatMessages, 0)
	end
	local a = PartyChatFixture()
	a.API.IsInInstanceGroup = function()
		return true
	end
	Equal(a:AnnounceToNonQTParty(event), true)
	Equal(a.chatMessages[1][2], "INSTANCE_CHAT")
end)

QuestTogether:RegisterTest("party announcements contain bounded plain text and do not retry failures", function()
	local a = PartyChatFixture()
	Equal(
		a:AnnounceToNonQTParty({
			eventType = "QUEST_PROGRESS",
			text = "|cffffffff|Hquest:1|h[Quest]|h|r\nDone |Ticon:16|t",
		}),
		true
	)
	Equal(a.chatMessages[1][1], "[QT] [Quest] Done")
	Equal(a:AnnounceToNonQTParty({ eventType = "QUEST_PROGRESS", text = string.rep("é", 150) }), true)
	assert(#a.chatMessages[2][1] <= 255)
	Equal(a.chatMessages[2][1], "[QT] " .. string.rep("é", 125))
	local attempts = 0
	a.API.SendPartyChatMessage = function()
		attempts = attempts + 1
		error("blocked")
	end
	Equal(a:AnnounceToNonQTParty({ eventType = "QUEST_PROGRESS", text = "Progress" }), false)
	Equal(attempts, 1)
	Equal(#a.delayed, 0)
end)

QuestTogether:RegisterTest("local publication sends one party announcement independent of addon transport", function()
	local a = PartyChatFixture()
	function a:BuildLocalAnnouncementEvent(eventType, text)
		return { eventType = eventType, text = text }
	end
	function a:SendAnnouncementWireEvent()
		return false
	end
	function a:HandleAnnouncementEvent() end
	Equal(a:PublishAnnouncementEvent("QUEST_PROGRESS", "Progress"), true)
	Equal(#a.chatMessages, 1)
	-- Incoming events use HandleAnnouncementEvent, never the local publisher.
	Equal(a:AnnounceToNonQTParty({ eventType = "PLAYER_LEVEL_UP", text = "Level 10" }), true)
end)

QuestTogether:RegisterTest("major channel transition sends only current and rejects retired channel traffic", function()
	local a = NewCommsFixture()
	local wire = WireEvent(a, "ANN", Event())
	local seen = 0
	function a:HandleAnnouncementEvent()
		seen = seen + 1
	end
	a:OnCommReceived(a.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, "QuestTogetherAnnounce1")
	Equal(seen, 0)
	a:OnCommReceived(a.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, a.announcementChannelName)
	Equal(seen, 1)
	Equal(a:IsAnnouncementChannelEvent("CHANNEL", 7, "General"), false)
end)

QuestTogether:RegisterTest("current channel resolves fresh IDs after joins and fails without a route", function()
	local n, a = QuietNetwork()
	n:Leave(a, a.announcementChannelName)
	a.API.JoinPermanentChannel = function() end
	local outcome
	assert(a:Emit("ANN", Event(), { { distribution = "CHANNEL", channelName = a.announcementChannelName } }, {
		expires = a.now + 2,
		onComplete = function(_, status)
			outcome = status
		end,
	}))
	n:Advance(3)
	Equal(#a.sent, 0)
	Equal(outcome, "rejected")
	n:Join(a, a.announcementChannelName, true)
	assert(a:Emit("ANN", Event(), { { distribution = "CHANNEL", channelName = a.announcementChannelName } }))
	n:Advance(3)
	assert(#a.sent > 0)
	Equal(a.sent[1].target, a.joined[a.announcementChannelName])
end)

QuestTogether:RegisterTest(
	"QT channels sort last in human chat then regional order without disturbing other channel order",
	function()
		local addon = NewCommsFixture()
		addon:InitializeGeographicComms()
		addon.geographicCommsState.subscriptions.QuestTogetherZ12 = true
		local names = { "QuestTogetherZ12", "General", addon.announcementChannelName, "Trade", "MyFriends" }
		local swaps = 0
		function addon:IsRuntimeRestricted()
			return self.blocked == true
		end
		function addon:IsRuntimeRestrictionTypeActive()
			return false
		end
		addon.API.GetChatChannelList = function()
			local list = {}
			for i, name in ipairs(names) do
				list[#list + 1], list[#list + 2], list[#list + 3] = i, name, false
			end
			return list
		end
		addon.API.GetChannelName = function(name)
			for i, value in ipairs(names) do
				if name == value then
					return i
				end
			end
		end
		addon.API.SwapChatChannelIndices = function(a, b)
			names[a], names[b] = names[b], names[a]
			swaps = swaps + 1
			addon:CHANNEL_UI_UPDATE()
			return true
		end
		addon:CHANNEL_COUNT_UPDATE()
		addon:CHANNEL_UI_UPDATE()
		Equal(#addon.delayed, 1)
		addon.delayed[1]()
		Equal(table.concat(names, ","), "General,Trade,MyFriends,QuestTogether,QuestTogetherZ12")
		Equal(addon.announcementChannelLocalID, 4)
		Equal(#addon.delayed, 1) -- swap events do not create a feedback timer loop
		local prior = swaps
		Equal(addon:MoveAnnouncementChannelsToEnd(), true)
		Equal(swaps, prior)
		names = { "QuestTogetherZ12", addon.announcementChannelName }
		Equal(addon:MoveAnnouncementChannelsToEnd(), true)
		Equal(names[1], addon.announcementChannelName)
		-- Channels joining later go ahead of both QT channels.
		names[3] = "General"
		addon.blocked = true
		Equal(addon:MoveAnnouncementChannelsToEnd(), false)
		Equal(names[1], addon.announcementChannelName)
		addon.blocked = false
		Equal(addon:MoveAnnouncementChannelsToEnd(), true)
		Equal(names[1], "General")
		Equal(names[2], addon.announcementChannelName)
		Equal(names[3], "QuestTogetherZ12")
		addon:ScheduleAnnouncementChannelOrder()
		addon.channelOrderWork = nil -- reset/disable invalidates queued work
		prior = swaps
		addon.delayed[#addon.delayed]()
		Equal(swaps, prior)
	end
)

QuestTogether:RegisterTest(
	"QT slash chat sends once to fresh primary channel ID without local echo or retry",
	function()
		local addon = NewCommsFixture()
		function addon:IsRuntimeRestrictionTypeActive()
			return self.blocked == true
		end
		function addon:HideAnnouncementChannelFromChatWindows() end
		local sends = {}
		addon.API.SendChannelChatMessage = function(message, id)
			sends[#sends + 1] = { message, id }
			return not addon.failed
		end
		Equal(addon:SendQTChannelChat("Hi everyone!"), true)
		Equal(#sends, 1)
		Equal(sends[1][1], "Hi everyone!")
		Equal(sends[1][2], 7)
		addon.channelID = 12
		Equal(addon:SendQTChannelChat("Hello again"), true)
		Equal(sends[2][2], 12)
		addon.failed = true
		Equal(addon:SendQTChannelChat("attempt"), false)
		Equal(#addon.delayed, 0)
		Equal(#addon.printed, 0)
		Equal(#addon.wire, 0)
		addon.blocked = true
		Equal(addon:SendQTChannelChat("restricted"), false)
		addon.blocked = false
		addon.isEnabled = false
		Equal(addon:SendQTChannelChat("disabled"), false)
		Equal(#sends, 3)
	end
)

QuestTogether:RegisterTest("channel ordering rejects inaccessible metadata and stops on failed swaps", function()
	local addon = NewCommsFixture()
	function addon:IsRuntimeRestricted()
		return false
	end
	function addon:IsRuntimeRestrictionTypeActive()
		return false
	end
	local secret = setmetatable({}, {
		__tostring = function()
			error("unreadable channel name")
		end,
	})
	function addon:CanAccessValue(value)
		return value ~= secret
	end
	local swaps = 0
	addon.API.GetChatChannelList = function()
		return { 1, secret, false, 2, "General", false }
	end
	addon.API.SwapChatChannelIndices = function()
		swaps = swaps + 1
		return false
	end
	Equal(addon:MoveAnnouncementChannelsToEnd(), false)
	Equal(swaps, 0)
	addon.API.GetChatChannelList = function()
		return { 1, addon.announcementChannelName, false, 2, "General", false }
	end
	Equal(addon:MoveAnnouncementChannelsToEnd(), false)
	Equal(swaps, 1)
	Equal(addon.announcementChannelLocalID, nil)
	addon.API.SwapChatChannelIndices = nil
	Equal(addon:MoveAnnouncementChannelsToEnd(), false)
	Equal(swaps, 1)
	Equal(addon:AnnouncementChannelChatFilter(nil, nil, "hi", "Friend", "", "4. questtogether"), true)
end)

QuestTogether:RegisterTest("nearby range uses physical map proportions keeps minimum and covers entire zone", function()
	local addon = NewCommsFixture()
	UseNativeLocationModel(addon)
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.API.IsWarModeFeatureEnabled = function()
		return false
	end
	local remote = { mapID = 37, coordX = 60, coordY = 50 }
	Equal(addon:GetNearbyAnnouncementRange(), 25)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	addon.db.profile.nearbyAnnouncementRange = 5
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	remote.coordX, remote.coordY = 53, 54
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	remote.coordY = 54.01
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.db.profile.nearbyAnnouncementRange = 25
	remote.coordX, remote.coordY = 80, 50 -- 1200 yards on a 4000x2000 map
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	remote.coordX, remote.coordY = 50, 80 -- 600 yards along the shorter axis
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	addon.GetPlayerAnnouncementLocationInfo = function()
		return { mapID = 37, coordX = 0, coordY = 0 }
	end
	remote.coordX, remote.coordY = 100, 100
	addon.db.profile.nearbyAnnouncementRange = 100
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	remote.mapID = 38 -- Keep the requested zone-boundary rule even at Entire Zone.
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	remote.mapID, remote.coordX = 37, 101
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.GetLocationPinMapWorldSize = function()
		return nil
	end
	remote.coordX, remote.coordY = 50, 50
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
end)

QuestTogether:RegisterTest(
	"nearby percentage slider validates and refreshes profiles without writing on initialization",
	function()
		local addon = NewCommsFixture()
		addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
		local writes = 0
		function addon:SetOption(key, value)
			Equal(key, "nearbyAnnouncementRange")
			self.db.profile[key] = value
			writes = writes + 1
			return true
		end
		local slider = { callbacks = {} }
		function slider:RegisterCallback(event, callback, owner)
			self.callbacks[event] = { callback, owner }
		end
		function slider:SetValue(value)
			self.value = value
			local listener = self.callbacks.OnValueChanged
			if listener then
				listener[1](listener[2], value)
			end
		end
		addon:ConfigureNearbyRangeSlider(slider)
		Equal(writes, 0)
		Equal(slider.value, 25)
		slider:SetValue(60)
		Equal(writes, 1)
		Equal(addon.db.profile.nearbyAnnouncementRange, 60)
		addon.db.profile = { nearbyAnnouncementRange = 10 }
		slider:RefreshNearbyRange()
		Equal(slider.value, 10)
		Equal(writes, 1)
		for _, invalid in ipairs({ 4, 101, -1, math.huge, "invalid", false }) do
			Equal(addon:NormalizeNearbyAnnouncementRange(invalid), nil)
		end
	end
)

QuestTogether:RegisterTest(
	"Global QT chat does not need locations while Zone Only requires fresh matching zones",
	function()
		local addon = NewCommsFixture()
		addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
		function addon:IsRuntimeRestricted()
			return false
		end
		function addon:IsRuntimeRestrictionTypeActive()
			return false
		end
		function addon:FindVisiblePlayerNameplateForSender()
			return nil
		end
		addon.API.GetBestMapForUnit = function()
			return 37
		end
		addon.db.profile.showChatBubbles = false
		local function Receive()
			return addon:CHAT_MSG_CHANNEL(
				"CHAT_MSG_CHANNEL",
				"hello",
				"Friend-Realm",
				"",
				addon.announcementChannelName
			)
		end
		Equal(Receive(), true) -- Global, no known player or location
		addon.db.profile.qtChatScope = "zone_only"
		Equal(Receive(), false)
		addon.playerLocationState = { peers = { ["Friend-Realm"] = { mapID = 37, receivedAt = addon.now, mask = 3 } } }
		Equal(Receive(), true)
		local peer = addon.playerLocationState.peers["Friend-Realm"]
		peer.mapID = 38
		Equal(Receive(), false)
		peer.mapID, peer.receivedAt = 37, addon.now - 120
		Equal(Receive(), false)
		peer.receivedAt, peer.mask = addon.now, 0
		Equal(Receive(), false)
		addon.db.profile.qtChatScope = "global"
		addon.playerLocationState = nil
		addon.API.GetBestMapForUnit = function()
			error("Global must not read location")
		end
		Equal(Receive(), true)
	end
)

QuestTogether:RegisterTest(
	"nearby range and QT chat scope persist valid profile options and reject invalid choices",
	function()
		local addon = NewCommsFixture()
		addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
		Equal(addon:SetOption("nearbyAnnouncementRange", 60), true)
		Equal(addon:GetNearbyAnnouncementRange(), 60)
		Equal(addon:SetOption("nearbyAnnouncementRange", 101), false)
		Equal(addon:GetNearbyAnnouncementRange(), 60)
		Equal(addon:SetOption("qtChatScope", "zone_only"), true)
		Equal(addon:GetOption("qtChatScope"), "zone_only")
		Equal(addon:SetOption("qtChatScope", "invalid"), false)
		Equal(addon:GetOption("qtChatScope"), "zone_only")
		addon.db.profile.nearbyAnnouncementRange = "invalid"
		addon:NormalizeSettingsProfile()
		Equal(addon:GetNearbyAnnouncementRange(), 25)
	end
)

QuestTogether:RegisterTest("partner search announces only explicit off to on transitions", function()
	local addon = NewLocationReceiver()
	local announcements, broadcasts = 0, 0
	function addon:AnnounceQuestPartnerSearch()
		announcements = announcements + 1
	end
	function addon:BroadcastQuestPartnerStatus()
		broadcasts = broadcasts + 1
	end
	function addon:RefreshMinimapPartnerGlow() end
	function addon:RefreshOptionsWindow() end
	Equal(addon:SetOption("lookingForQuestPartners", false), true)
	Equal(announcements, 0)
	Equal(addon:SetOption("lookingForQuestPartners", true), true)
	Equal(announcements, 1)
	Equal(addon:SetOption("lookingForQuestPartners", true), true)
	Equal(announcements, 1)
	Equal(addon:SetOption("lookingForQuestPartners", false), true)
	Equal(announcements, 1)
	Equal(addon:SetOption("lookingForQuestPartners", "true"), false)
	Equal(announcements, 1)
	Equal(addon:SetOption("lookingForQuestPartners", true), true)
	Equal(announcements, 2)
	Equal(broadcasts, 5)
end)

QuestTogether:RegisterTest(
	"partner announcement cooldown leaves status changes immediate and never queues retries",
	function()
		local addon = NewLocationReceiver()
		local announcements, statuses, glows = 0, 0, 0
		function addon:SendAnnouncementWireEvent()
			announcements = announcements + 1
			return not self.failSend
		end
		function addon:BroadcastQuestPartnerStatus()
			statuses = statuses + 1
		end
		function addon:RefreshMinimapPartnerGlow()
			glows = glows + 1
		end
		function addon:RefreshOptionsWindow() end
		local function ToggleOn()
			assert(addon:SetOption("lookingForQuestPartners", false))
			assert(addon:SetOption("lookingForQuestPartners", true))
			Equal(addon:GetOption("lookingForQuestPartners"), true)
		end
		ToggleOn()
		Equal(announcements, 1)
		addon.now = 129.9
		ToggleOn()
		Equal(announcements, 1)
		Equal(statuses, 4)
		Equal(glows, 4)
		addon.qtPlayerPresenceState = nil -- Metadata lifecycle must not reset the cooldown.
		ToggleOn()
		Equal(announcements, 1)
		addon.now = 130
		ToggleOn()
		Equal(announcements, 2)
		addon.now, addon.failSend = 160, true
		ToggleOn()
		ToggleOn()
		Equal(announcements, 3)
		Equal(#addon.delayed, 0)
		-- A clock reset starts a fresh interval instead of suppressing indefinitely.
		addon.now = 1
		ToggleOn()
		Equal(announcements, 4)
	end
)

QuestTogether:RegisterTest(
	"partner search crosses the zone once through normal transport without changing quest range",
	function()
		local sender, receiver = NewLocationReceiver(), NewLocationReceiver()
		sender.suppressLocalAnnouncementDisplayDuringTests = false
		sender.API.UnitFullName = function()
			return "Friend", "Realm"
		end
		sender.API.UnitName = function()
			return "Friend"
		end
		sender.db.profile.lookingForQuestPartners = true
		local localMapID, remoteMapID, localWarMode = 37, 37, false
		function sender:GetPlayerAnnouncementLocationInfo()
			return { mapID = remoteMapID, zoneName = "Elwynn", coordX = 99, coordY = 99, warMode = false }
		end
		function receiver:GetPlayerAnnouncementLocationInfo()
			return { mapID = localMapID, zoneName = "Elwynn", coordX = 1, coordY = 1, warMode = localWarMode }
		end
		receiver.db.profile.nearbyAnnouncementRange = 5
		function receiver:GetLocationPinMapWorldSize()
			error("LFQP must not need map dimensions")
		end
		function sender:AnnounceToNonQTParty()
			error("partner search is a QT announcement")
		end
		function receiver:RecordQTPlayerPresence() end
		sender.db.profile.announceQuestPartners = false
		Equal(sender:AnnounceQuestPartnerSearch(), false)
		Equal(#sender.wire, 0)
		sender.db.profile.announceQuestPartners = true
		Equal(sender:AnnounceQuestPartnerSearch(), true)
		assert(#sender.printed == 1, "local partner search should print once")
		local wire = sender.wire[1][2]
		local event, command = ReadRecord(sender, wire)
		Equal(command, "ANN")
		Equal(event.eventType, "LOOKING_FOR_QUEST_PARTNERS")
		Equal(event.text, QuestTogether.Translate("Looking for questing partners") .. " :)")
		Equal(event.iconAsset, "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
		local iconTag = receiver:GetAnnouncementIconChatTag(event.eventType, 14, event.iconAsset, event.iconKind)
		assert(
			iconTag:find("QuestTogetherPartnerIcon", 1, true),
			"LFQP uses local glow artwork with a legacy-safe wire icon"
		)
		receiver:OnCommReceived(sender.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, "QuestTogether")
		receiver:OnCommReceived(sender.commPrefix, wire, "PARTY", "Friend-Realm")
		assert(#receiver.printed == 1, "remote partner search should print once across routes")
		Equal(receiver.printed[1], QuestTogether.Translate("Looking for questing partners") .. " :)")
		event.eventType = "QUEST_PROGRESS"
		Equal(receiver:HandleAnnouncementEvent(event, false), false)
		event.eventType = "LOOKING_FOR_QUEST_PARTNERS"
		localMapID = 38
		Equal(receiver:HandleAnnouncementEvent(event, false), false)
		localMapID, localWarMode = 37, true
		Equal(receiver:HandleAnnouncementEvent(event, false), false)
		localWarMode = false
		receiver.db.profile.showProgressFor = "party_only"
		Equal(receiver:HandleAnnouncementEvent(event, false), false)
		receiver.db.profile.showProgressFor = "party_nearby"
		receiver.db.profile.announceQuestPartners = false
		Equal(receiver:HandleAnnouncementEvent(event, false), false)
		receiver.db.profile.announceQuestPartners = true
		function receiver:IsIgnoredPlayerName()
			return true
		end
		Equal(receiver:HandleAnnouncementEvent(event, false), false)
		Equal(#receiver.printed, 1)
		local count = #sender.wire
		sender.isEnabled = false
		Equal(sender:AnnounceQuestPartnerSearch(), false)
		sender.isEnabled = true
		function sender:IsRuntimeRestricted()
			return true
		end
		Equal(sender:AnnounceQuestPartnerSearch(), false)
		function sender:IsRuntimeRestricted()
			return false
		end
		sender.db.profile.lookingForQuestPartners = false
		Equal(sender:AnnounceQuestPartnerSearch(), false)
		Equal(#sender.wire, count)
		-- Sharing disabled still redacts location; the new event cannot bypass it.
		sender.now = sender.now + 30
		sender.db.profile.lookingForQuestPartners = true
		sender.db.profile.sharePlayerLocation = false
		Equal(sender:AnnounceQuestPartnerSearch(), true)
		local privateEvent = ReadRecord(sender, sender.wire[#sender.wire][2])
		Equal(privateEvent.mapID, "")
		Equal(privateEvent.coordX, "")
	end
)

QuestTogether:RegisterTest("ping localizes available identity and zone while preserving sender fallback", function()
	local a = NewCommsFixture()
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	a.API.GetLocalizedClassName = function(id)
		if id == "MAGE" then
			return "Local Mage"
		end
	end
	a.API.GetMapInfo = function(id)
		if id == 37 then
			return { name = "Local Forest" }
		end
	end
	a.API.GetLocalizedRaceName = function(id)
		if id == 3 then
			return "Local Dwarf"
		end
	end
	a.nearbyStreamState = { capabilities = { ["Remote-Realm"] = { receivedAt = a.now, raceID = 3 } } }
	local pong = {
		senderName = "Remote-Realm",
		className = "Magier",
		classFile = "MAGE",
		raceName = "Zwerg",
		zoneName = "Wald",
		mapID = 37,
	}
	local text = a:BuildPingResponseMessage(pong)
	assert(
		text:find("Local Mage", 1, true) and text:find("Local Forest", 1, true) and text:find("Local Dwarf", 1, true)
	)
	assert(not text:find("Magier", 1, true) and not text:find("Zwerg", 1, true) and not text:find("Wald", 1, true))
	a.API.GetLocalizedClassName, a.API.GetMapInfo, a.API.GetLocalizedRaceName =
		function() end, function() end, function() end
	text = a:BuildPingResponseMessage(pong)
	assert(text:find("Magier", 1, true) and text:find("Zwerg", 1, true) and text:find("Wald", 1, true))
	a.blocked = true
	a.API.GetLocalizedClassName, a.API.GetMapInfo =
		function()
			error("restricted lookup")
		end, function()
			error("restricted lookup")
		end
	text = a:BuildPingResponseMessage(pong)
	assert(text:find("Magier", 1, true) and text:find("Wald", 1, true))
end)

QuestTogether:RegisterTest("compare completion matches native tracker and survives wire encoding", function()
	for _, native in ipairs({ true, false }) do
		local a = NewSnapshotComparisonFixture()
		a.GetQuestShareableStatusLabel = function()
			return "Yes"
		end
		a.API.GetQuestLogInfo = function()
			return { questID = 123, title = "Delivery quest", isComplete = not native }
		end
		a.API.IsQuestComplete = function(id)
			Equal(id, 123)
			return native
		end
		local entry = a:BuildQuestCompareEntries()[1]
		Equal(entry.isComplete, native)
		Equal(assert(a:CopyCommRecord("QCENTRY", entry)).isComplete, native)
	end
end)
QuestTogether:RegisterTest("compare completion falls back safely when native data cannot be read", function()
	for _, value in ipairs({ "missing", "nil", "invalid", "throws", "inaccessible" }) do
		local addon = NewSnapshotComparisonFixture()
		function addon:GetQuestShareableStatusLabel()
			return "Yes"
		end
		addon.API.GetQuestLogInfo = function()
			return { questID = 123, title = "Ready quest", isComplete = true }
		end
		local unreadable = {}
		function addon:CanAccessValue(v)
			return v ~= unreadable
		end
		if value ~= "missing" then
			addon.API.IsQuestComplete = function()
				if value == "throws" then
					error("unavailable")
				end
				if value == "invalid" then
					return "false"
				end
				if value == "inaccessible" then
					return unreadable
				end
			end
		end
		Equal(addon:BuildQuestCompareEntries()[1].isComplete, true)
		function addon:IsWorkBlocked()
			return true
		end
		addon.API.IsQuestComplete = function()
			error("restricted native read")
		end
		Equal(addon:BuildQuestCompareEntries(), nil)
	end
end)

QuestTogether:RegisterTest("immutable snapshot identity and full UTF8 titles cross bounded shared fragments", function()
	local a = NewCommsFixture()
	local title = string.rep("é", 200)
	local response = {
		requestId = "comparison",
		snapshotId = "snapshot-1",
		revision = "revision-1",
		count = 1,
		entries = { { questId = 1, questTitle = title } },
	}
	local frames = assert(
		a:BuildCommFrames(
			"QCRS",
			response,
			{ session = "100-1234", messageId = "1", requestId = "comparison", stamp = 1800000000 }
		)
	)
	assert(#frames > 1)
	for _, wire in ipairs(frames) do
		assert(#wire <= 255)
	end
	local decoded = ReadRecord(a, frames)
	Equal(decoded.snapshotId, response.snapshotId)
	Equal(decoded.entries[1].questTitle, title)
	Equal(a:EncodeCommRecord("QCRS", { requestId = "comparison", count = 0, entries = {} }), nil)
end)
