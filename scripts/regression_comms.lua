-- Live-safe fixtures: these tests only replace fields on private addon objects.
local QuestTogether = _G.QuestTogether

local function Equal(actual, expected)
	if actual ~= expected then
		error("expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function NewCommsFixture()
	local addon = setmetatable({
		isEnabled = true,
		isLocalDeveloper = true,
		partyMembers = {},
		pendingPingRequests = {},
		pendingQuestCompareRequests = {},
		questCompareResponseQueue = false,
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
	function addon:PrepareDeveloperPingRequest(request) return request end
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
	local a=NewCommsFixture()
	a.db={profile=QuestTogether:DeepCopy(QuestTogether.DEFAULTS.profile),global={}}
	a.name=name or "Dev-Realm"
	a.PrepareDeveloperPingRequest=QuestTogether.PrepareDeveloperPingRequest
	a.API.GetServerTime=function() return 1791300000+math.floor(a.now) end
	function a:GetPlayerFullName() return self.name end
	function a:IsSelfSender(n) return self:NormalizeMemberName(n)==self.name end
	function a:IsRuntimeRestricted() return false end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshPlayerLocationPins() end
	function a:HideAnnouncementChannelFromChatWindows() end
	function a:BuildPartyVisualMetadataPayload() return "" end
	function a:ReadLocalPlayerLocation()
		self.reads=(self.reads or 0)+1
		return {mapID=12,x=0.42,y=0.63,faction="Alliance",warMode=false}
	end
	function a:BuildDiagnosticReport(_, extraFields)
		local lines = { "QT diagnostic snapshot\n"..string.rep("Long diagnostic state\n",70) }
		for _, field in ipairs(extraFields or {}) do lines[#lines+1] = field[1] .. "=" .. tostring(field[2]) end
		return table.concat(lines, "\n")
	end
	local seed=("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"):gsub("..",function(x) return string.char(tonumber(x,16)) end)
	a.developerPublicKeyHex="d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	function a:SignDeveloperRequest(message) return self.Ed25519.Sign(seed,message) end
	function a:GetDebugController() return {ShowReport=function(_,body,title) a.report,a.reportTitle=body,title end} end
	function a:PrintPingResponse(response) self.printed[#self.printed+1]=response end
	local clock=a:CreateTestClock(100)
	a.API.GetTime=function() return clock:GetTime() end
	a.API.Delay=function(seconds,callback) clock:After(seconds,callback) end
	a.clock=clock
	return a
end

local function FinishDeveloperVerification(peer)
	local steps = 0
	while peer.developerRequestState and #peer.developerRequestState.jobs > 0 do
		steps = steps + 1
		assert(steps < 2000, "incremental verifier did not finish")
		peer.clock:RunNext()
	end
end

QuestTogether:RegisterTest("developer verification budgets work and cancels on opt-out without reading diagnostics", function()
	local peer = DeveloperFixture("Friend-Realm")
	local work, callback = 0, false
	peer.Ed25519 = { NewVerification = function()
		return coroutine.create(function()
			for _ = 1, 100 do work = work + 1; coroutine.yield() end
			return true
		end)
	end }
	local request = { requestId = "dev-1791300100-1234-1", issuedAt = peer:GetAnnouncementServerTime(),
		developerRequest = true, supportsPagedPong = true, supportsDirectComms = true,
		signature = string.rep("0", 128) }
	Equal(peer:QueueDeveloperPingVerification(request, "Dev-Realm", function() callback = true end), true)
	Equal(work, 0)
	peer.clock:RunNext()
	Equal(work, 8, "missing profiler still has a hard step limit")
	Equal(callback, false); Equal(peer.reads, nil)
	local milliseconds = 0
	peer.API.ProfileMilliseconds = function() milliseconds = milliseconds + 0.6; return milliseconds end
	peer.clock:RunNext()
	Equal(work, 10, "frame budget yields before the step limit")
	peer:SetOption("shareDeveloperDiagnostics", false)
	peer:SetOption("shareDeveloperDiagnostics", true)
	peer.clock:Drain()
	Equal(work, 10); Equal(callback, false); Equal(peer.reads, nil)
end)

QuestTogether:RegisterTest("developer verification copies requests bounds admission and backs off invalid senders", function()
	local peer, verified = DeveloperFixture("Friend-Realm"), {}
	peer.Ed25519 = { NewVerification = function(_, message)
		return coroutine.create(function() coroutine.yield(); return not message:find("Bad-Realm", 1, true) end)
	end }
	local function request(id)
		return { requestId = "dev-1791300100-1234-" .. id, issuedAt = peer:GetAnnouncementServerTime(),
			developerRequest = true, supportsPagedPong = true, signature = string.rep("0", 128) }
	end
	local original = request(1)
	Equal(peer:QueueDeveloperPingVerification(original, "Good-Realm", function(copy) verified[#verified + 1] = copy end), true)
	original.requestId, original.targetName = "tampered", "Other-Realm"
	Equal(peer:QueueDeveloperPingVerification(request(2), "Good-Realm", function() end), false, "one pending job per sender")
	for index = 2, 4 do Equal(peer:QueueDeveloperPingVerification(request(index), "Peer" .. index .. "-Realm", function() end), true) end
	Equal(peer:QueueDeveloperPingVerification(request(5), "Overflow-Realm", function() end), false)
	FinishDeveloperVerification(peer)
	Equal(verified[1].requestId, "dev-1791300100-1234-1"); Equal(verified[1].targetName, nil)
	Equal(verified[1].developerVerified, true)
	Equal(peer:QueueDeveloperPingVerification(request(6), "Bad-Realm", function() error("invalid request accepted") end), true)
	FinishDeveloperVerification(peer)
	Equal(peer:QueueDeveloperPingVerification(request(7), "Bad-Realm", function() end), false)
	peer.clock:Advance(5)
	Equal(peer:QueueDeveloperPingVerification(request(7), "Bad-Realm", function() end), true)
	peer.developerRequestState = nil -- Same cancellation fence used by departure/reset.
	peer.clock:Drain()
end)

QuestTogether:RegisterTest("profile switches copies and resets retire developer verification and queued replies", function()
	for _, change in ipairs({ "switch", "copy", "reset" }) do
		local peer = DeveloperFixture("Friend-Realm")
		local work, callbacks = 0, 0
		peer.Ed25519 = { NewVerification = function()
			return coroutine.create(function()
				for _ = 1, 40 do work = work + 1; coroutine.yield() end
				return true
			end)
		end }
		-- Exercise the real profile methods; UI refreshes belong to separate
		-- private fixtures and must not touch the player's live windows here.
		for _, method in ipairs({ "EnsureQuestLogChatFrame", "CloseQuestLogChatFrame", "RefreshPartyRoster", "RefreshNameplateAugmentation",
			"RefreshActiveAnnouncementBubbles", "RefreshPersonalBubbleAnchorVisualState",
			"RefreshPersonalBubbleEditModeDialog", "RefreshMinimapButton", "RefreshManagedWindowLayouts",
			"OnPlayerLocationOptionsChanged", "BroadcastQuestPartnerStatus", "RefreshOptionsWindow",
			"RefreshProfilesWindow", "QueuePartyNavigationUpdate", "RefreshWindowThemes" }) do peer[method] = function() end end
		peer.hasLoggedIn = true
		peer.activeCharacterKey, peer.activeProfileKey = peer.name, "Initial"
		peer.db.profile.chatLogDestination = "main"
		peer.db.profiles = { Initial = peer.db.profile, Private = peer:DeepCopy(peer.db.profile) }
		peer.db.profiles.Private.shareDeveloperDiagnostics = false
		peer.db.profileKeys = { [peer.name] = "Initial" }
		local request = { requestId = "dev-1791300100-1234-1", issuedAt = peer:GetAnnouncementServerTime(),
			developerRequest = true, supportsPagedPong = true, signature = string.rep("0", 128) }
		assert(peer:QueueDeveloperPingVerification(request, "Dev-Realm", function()
			callbacks = callbacks + 1
			peer:ReadLocalPlayerLocation()
		end))
		peer.clock:RunNext()
		Equal(work, 8)
		assert(peer:SendPagedPong("old-profile", string.rep("x", 800), { { distribution = "WHISPER", target = "Dev-Realm" } }, true))
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
		Equal(work, 8); Equal(callbacks, 0); Equal(peer.reads, nil)
		Equal(#peer.wire, sent)
		Equal(peer.developerRequestState, nil)
	end
end)

QuestTogether:RegisterTest("developer verification bounds failed senders and discards work when the clock rewinds", function()
	local peer = DeveloperFixture("Friend-Realm")
	peer.API.GetServerTime = function() return 1791300000 + math.floor(peer.clock:GetTime()) end
	peer.Ed25519 = { NewVerification = function() return coroutine.create(function() return false end) end }
	local function Reject(id, sender)
		local request = { requestId = "dev-1791300100-1234-" .. id, issuedAt = peer:GetAnnouncementServerTime(),
			developerRequest = true, supportsPagedPong = true, signature = string.rep("0", 128) }
		assert(peer:QueueDeveloperPingVerification(request, sender, function() error("invalid signature accepted") end))
		FinishDeveloperVerification(peer)
		local count = 0
		for _ in pairs(peer.developerRequestState.failures) do count = count + 1 end
		assert(count <= 64, "invalid identities must not grow an unbounded failure cache")
		peer.clock:Advance(5)
	end
	-- Build long backoffs through actual failures, then churn fresh identities.
	-- Their longer retention overlaps enough newcomers to exercise eviction.
	for round = 1, 5 do
		for index = 1, 8 do Reject(round * 10 + index, "Repeat" .. index .. "-Realm") end
	end
	for index = 1, 150 do Reject(1000 + index, "Peer" .. index .. "-Realm") end
	peer.Ed25519 = { NewVerification = function()
		return coroutine.create(function() for _ = 1, 40 do coroutine.yield() end; return true end)
	end }
	local request = { requestId = "dev-1791300100-1234-999", issuedAt = peer:GetAnnouncementServerTime(),
		developerRequest = true, supportsPagedPong = true, signature = string.rep("0", 128) }
	assert(peer:QueueDeveloperPingVerification(request, "Dev-Realm", function() error("retired clock lifetime accepted") end))
	peer.clock:RunNext()
	peer.clock.now = peer.clock.now - 1
	-- Model the timer firing after a reset of the monotonic clock.
	peer.clock.timers[1].callback()
	Equal(peer.developerRequestState, nil)
	peer.clock:Drain()
end)

QuestTogether:RegisterTest("developer Ed25519 signatures match RFC8032 and reject altered content",function()
	local E=QuestTogether.Ed25519
	local function unhex(s) return (s:gsub("..",function(x) return string.char(tonumber(x,16)) end)) end
	local seed=unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
	local key=unhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
	local sig=unhex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
	Equal(E.PublicKey(seed),key)
	Equal(E.Sign(seed,""),sig)
	Equal(E.Verify(key,"",sig),true)
	Equal(E.Verify(key,"changed",sig),false)
	Equal(E.Verify(key,"",sig:sub(1,63)),false)
	Equal(E.Verify(key,"",sig:sub(1,32)..string.rep(string.char(255),32)),false)
	for _, message in ipairs({ "", "changed" }) do
		local verifier, slices = E.NewVerification(key, message, sig), 0
		while coroutine.status(verifier) ~= "dead" do
			local ok, valid = coroutine.resume(verifier)
			assert(ok); slices = slices + 1
			if coroutine.status(verifier) == "dead" then Equal(valid, message == "") end
		end
		assert(slices > 100, "verification must expose bounded arithmetic steps")
	end
end)

QuestTogether:RegisterTest("signed global pong keeps opted-in private position separate from public locations",function()
	local dev,peer=DeveloperFixture(),DeveloperFixture("Friend-Realm")
	peer.db.profile.sharePlayerLocation=false
	local ok,id=dev:SendPingRequest()
	Equal(ok,true)
	Equal(#dev.wire[1][2]<=255,true)
	peer:OnCommReceived(peer.commPrefix,dev.wire[1][2],"CHANNEL",dev.name,7,peer.announcementChannelName)
	FinishDeveloperVerification(peer)
	for _=1,100 do peer.clock:Advance(0.2) end
	assert(#peer.wire>=1)
	-- Reverse delivery and duplicates must still produce one complete report.
	for i=#peer.wire,1,-1 do
		local packet=peer.wire[i]
		Equal(packet[3],"WHISPER"); Equal(packet[4],dev.name); assert(#packet[2]<=255)
		dev:OnCommReceived(dev.commPrefix,packet[2],"WHISPER",peer.name)
		dev:OnCommReceived(dev.commPrefix,packet[2],"WHISPER",peer.name)
	end
	Equal(dev.pendingPingRequests[id].remoteReplies,1)
	Equal(dev.printed[2].coordX,"42.0")
	Equal(dev.printed[2].locationShared,false)
	local rows={}; dev:AppendDeveloperLocationRows(rows)
	Equal(#rows,1); Equal(rows[1].publicLocationHidden,true)
	Equal(dev.playerLocationState.peers[peer.name].mask,0)
	Equal(dev.playerLocationState.peers[peer.name].mapID,nil)
	dev.clock:Advance(121); rows={}; dev:AppendDeveloperLocationRows(rows); Equal(#rows,0)
end)

local function Pong(a, shared, sampleTime)
	return { senderName = "Friend-Realm", developer = true, locationShared = shared,
		mapID = "12", coordX = "42", coordY = "63", classFile = "MAGE", className = "Mage",
		raceName = "Human", faction = "Alliance", level = "60", warMode = "0",
		sampledAt = sampleTime or a:GetAnnouncementServerTime() }
end

QuestTogether:RegisterTest("shared developer pong refreshes the normal cache and obeys normal map filters",function()
	local a = DeveloperFixture()
	a:AcceptDeveloperPingResponse(Pong(a, true), {developerRequest=true})
	local row = a:GetVisiblePlayerLocations("map")[1]
	assert(row); Equal(row, a.playerLocationState.peers["Friend-Realm"])
	Equal(row.x, 0.42); Equal(row.level, 60); Equal(row.classFile, "MAGE")
	Equal(row.developerOnly, nil); Equal(a.developerPlayerData["Friend-Realm"], nil)
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

QuestTogether:RegisterTest("manual location refresh preserves sample age and real LOC sequence",function()
	local a = DeveloperFixture()
	local payload = "1,1000-1,8,3,12,0.1,0.2,MAGE,Mage,Human,Alliance,60,0"
	assert(a:HandlePlayerLocationMessage(payload, "Friend-Realm", 30))
	a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime()-20), {developerRequest=true})
	local row = a.playerLocationState.peers["Friend-Realm"]
	Equal(row.sampledAt, 80); Equal(row.lifetime, 580)
	Equal(row.session, "1000-1"); Equal(row.sequence, 8)
	Equal(row.x, 0.42)
	-- A higher sequence may still contain a sample older than the manual refresh.
	Equal(a:HandlePlayerLocationMessage(payload:gsub(",8,", ",9,", 1), "Friend-Realm", 25), false)
	Equal(a:HandlePlayerLocationMessage(payload:gsub(",8,", ",10,", 1), "Friend-Realm", 5), true)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.1)
	-- Delayed pongs cannot move the location back again.
	a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime()-20), {developerRequest=true})
	Equal(a.playerLocationState.peers["Friend-Realm"].sequence, 10)
	Equal(a.playerLocationState.peers["Friend-Realm"].x, 0.1)
	a.clock:Advance(595)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
end)

QuestTogether:RegisterTest("hidden pongs withdraw public positions without persisting private coordinates",function()
	local a = DeveloperFixture()
	a.activeCharacterKey = a.name
	a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime()-10), {developerRequest=true})
	a:AcceptDeveloperPingResponse(Pong(a, false), {developerRequest=true})
	local row = a.playerLocationState.peers["Friend-Realm"]
	Equal(row.mask, 0); Equal(row.x, nil); Equal(row.mapID, nil)
	Equal(a:GetVisiblePlayerLocations("map")[1].publicLocationHidden, true)
	a:SavePlayerLocationCache()
	Equal(#a.db.global.playerLocationCache.rows, 0)
	-- Neither an older nor a tied shared pong can undo a privacy withdrawal.
	for _, age in ipairs({0, 10}) do
		a:AcceptDeveloperPingResponse(Pong(a, true, a:GetAnnouncementServerTime()-age), {developerRequest=true})
		Equal(a.playerLocationState.peers["Friend-Realm"].mask, 0)
	end
	a.clock:Advance(121)
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
	Equal(a:GetRecentPlayerLocationMapID("Friend-Realm"), nil)
end)

QuestTogether:RegisterTest("new public broadcasts replace hidden developer snapshots even with filtered maps",function()
	local a = DeveloperFixture()
	a:AcceptDeveloperPingResponse(Pong(a, false), {developerRequest=true})
	a.clock:Advance(1)
	assert(a:HandlePlayerLocationMessage("1,1000-1,1,3,12,0.1,0.2,MAGE,Mage,Human,Alliance,60,0", "Friend-Realm", 0))
	Equal(a.developerPlayerData["Friend-Realm"], nil)
	a.db.profile.mapPartyOnly = true
	Equal(#a:GetVisiblePlayerLocations("map"), 0)
end)

QuestTogether:RegisterTest("shared pong locations survive normal reload caching and later live LOC updates",function()
	local a = DeveloperFixture()
	a.activeCharacterKey = a.name
	a:AcceptDeveloperPingResponse(Pong(a, true), {developerRequest=true})
	a:SavePlayerLocationCache()
	Equal(#a.db.global.playerLocationCache.rows, 1)
	local b = DeveloperFixture()
	b.activeCharacterKey, b.db.global = a.name, a.db.global
	b:RestorePlayerLocationCache()
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.42)
	assert(b:HandlePlayerLocationMessage("1,1000-1,1,3,12,0.1,0.2,MAGE,Mage,Human,Alliance,60,0", "Friend-Realm", 0))
	Equal(b:GetVisiblePlayerLocations("map")[1].x, 0.1)
end)

QuestTogether:RegisterTest("newer shared pong removes red private dot and stale hidden replies cannot undo it",function()
	local a = DeveloperFixture()
	a:AcceptDeveloperPingResponse(Pong(a, false, a:GetAnnouncementServerTime()-10), {developerRequest=true})
	a:AcceptDeveloperPingResponse(Pong(a, true), {developerRequest=true})
	Equal(a.developerPlayerData["Friend-Realm"], nil)
	Equal(a:GetVisiblePlayerLocations("map")[1].developerOnly, nil)
	a:AcceptDeveloperPingResponse(Pong(a, false, a:GetAnnouncementServerTime()-5), {developerRequest=true})
	Equal(a.developerPlayerData["Friend-Realm"], nil)
	Equal(a.playerLocationState.peers["Friend-Realm"].mask, 3)
end)

QuestTogether:RegisterTest("signed shared pong pages refresh normal locations through the real response handler",function()
	local dev, peer = DeveloperFixture(), DeveloperFixture("Friend-Realm")
	peer.db.profile.sharePlayerLocation = true
	local ok, id = dev:SendPingRequest(); Equal(ok, true)
	peer:OnCommReceived(peer.commPrefix, dev.wire[1][2], "CHANNEL", dev.name, 7, peer.announcementChannelName)
	FinishDeveloperVerification(peer)
	for _=1,100 do peer.clock:Advance(0.2) end
	for i=#peer.wire,1,-1 do
		dev:OnCommReceived(dev.commPrefix, peer.wire[i][2], "WHISPER", peer.name)
	end
	Equal(dev.pendingPingRequests[id].remoteReplies, 1)
	Equal(dev.playerLocationState.peers[peer.name].x, 0.42)
	Equal(dev.developerPlayerData[peer.name], nil)
	dev.clock:Advance(211)
	Equal(#dev:GetVisiblePlayerLocations("map"), 1)
end)

QuestTogether:RegisterTest("manual public refreshes use the normal bounded location cache",function()
	local a = DeveloperFixture()
	function a:GetPlayerLocationPriorityOrigin() return nil end
	for i=1,513 do
		local response = Pong(a, true)
		response.senderName = "Peer" .. i .. "-Realm"
		a:AcceptDeveloperPingResponse(response, {developerRequest=true})
	end
	local count = 0
	for _ in pairs(a.playerLocationState.peers) do count = count + 1 end
	Equal(count, 512)
	Equal(next(a.developerPlayerData), nil)
end)

QuestTogether:RegisterTest("malformed expired and unverified pongs cannot refresh public locations",function()
	local a = DeveloperFixture()
	for _, change in ipairs({"coordinates", "expired", "future", "consent", "unverified", "ignored"}) do
		local pong, pending = Pong(a, true), {developerRequest=true}
		if change == "coordinates" then pong.coordX = "nan"
		elseif change == "expired" then pong.sampledAt = pong.sampledAt - 600
		elseif change == "future" then pong.sampledAt = pong.sampledAt + 31
		elseif change == "consent" then pong.locationShared = nil
		elseif change == "unverified" then pending.developerRequest = false
		else function a:IsIgnoredPlayerName() return true end end
		a:AcceptDeveloperPingResponse(pong, pending)
		Equal(#a:GetVisiblePlayerLocations("map"), 0)
	end
end)

QuestTogether:RegisterTest("developer diagnostic permission blocks reads and cancels a paged reply mid-send",function()
	local dev,peer=DeveloperFixture(),DeveloperFixture("Friend-Realm")
	peer.db.profile.shareDeveloperDiagnostics=false
	local ok=dev:SendPingRequest(); Equal(ok,true)
	peer:OnCommReceived(peer.commPrefix,dev.wire[1][2],"CHANNEL",dev.name,7,peer.announcementChannelName)
	Equal(#peer.wire,0); Equal(peer.reads,nil)
	peer.db.profile.shareDeveloperDiagnostics=true
	peer.recentCommMessageSignatures={}
	peer:OnCommReceived(peer.commPrefix,dev.wire[1][2],"CHANNEL",dev.name,7,peer.announcementChannelName)
	FinishDeveloperVerification(peer)
	Equal(#peer.wire,1)
	peer.db.profile.shareDeveloperDiagnostics=false
	for _=1,100 do peer.clock:Advance(0.2) end
	Equal(#peer.wire,1)
end)

QuestTogether:RegisterTest("developer request signatures bind sender target purpose and time",function()
	local dev=DeveloperFixture()
	local ok=dev:SendPingRequest("Friend-Realm",true); Equal(ok,true)
	local wire=dev.wire[1][2]
	for _,change in ipairs({"sender","target","purpose","expired","signature"}) do
		local peer=DeveloperFixture("Friend-Realm")
		local _,payload=peer:DeserializeWireMessage(wire)
		local request=peer:DecodePingRequestPayload(payload)
		local sender=dev.name
		if change=="sender" then sender="Impostor-Realm"
		elseif change=="target" then request.targetName="Other-Realm"
		elseif change=="purpose" then request.debugRequest=false
		elseif change=="expired" then request.issuedAt=request.issuedAt-400
		else request.signature=string.rep("0",128) end
		local accepted = false
		peer:QueueDeveloperPingVerification(request,sender,function() accepted = true end)
		FinishDeveloperVerification(peer)
		Equal(accepted,false)
	end
	local peer=DeveloperFixture("Friend-Realm")
	local request=peer:DecodePingRequestPayload(wire:sub(6))
	local accepted = false
	Equal(peer:QueueDeveloperPingVerification(request,dev.name,function() accepted = true end),true)
	Equal(accepted,false, "no synchronous verification")
	FinishDeveloperVerification(peer)
	Equal(accepted,true)
	peer.clock:Advance(6)
	Equal(peer:QueueDeveloperPingVerification(request,dev.name,function() end),false)
end)

QuestTogether:RegisterTest("targeted remote debug opens the peer report without changing the local log",function()
	local dev,peer=DeveloperFixture(),DeveloperFixture("Friend-Realm")
	dev.debugLogLines={{text="local only",category="DEBUG"}}
	local ok,id=dev:SendPingRequest(peer.name,true); Equal(ok,true)
	Equal(dev.wire[1][3],"WHISPER"); Equal(dev.wire[1][4],peer.name)
	Equal(#dev.printed,0)
	peer:OnCommReceived(peer.commPrefix,dev.wire[1][2],"WHISPER",dev.name)
	FinishDeveloperVerification(peer)
	for _=1,400 do peer.clock:Advance(0.2) end
	for _,packet in ipairs(peer.wire) do dev:OnCommReceived(dev.commPrefix,packet[2],"WHISPER",peer.name) end
	Equal(dev.pendingPingRequests[id].remoteReplies,1)
	Equal(dev.report,peer:BuildDeveloperDiagnosticSnapshot())
	Equal(dev.reportTitle,peer.name)
	Equal(dev.debugLogLines[1].text,"local only")
end)

local function BusyDiagnosticFixture()
	local peer = DeveloperFixture("Friend-Realm")
	peer.BuildDiagnosticReport = QuestTogether.BuildDiagnosticReport
	peer.GetRuntimeWorkStateStore = QuestTogether.GetRuntimeWorkStateStore
	function peer:GetDiagnosticEnvironment() return {} end
	function peer:GetPlayerTracker() return {} end
	function peer:IsWorkBlocked() return true end
	peer.API.IsWorldMapVisible = function() return false end
	for _, command in ipairs({ "QTNAV", "QTN2", "ANN", "LVL", "LOC", "QTPR", "QTVR", "QTLF", "QTLQ", "QJST",
		"QJON", "QTPG", "QPGR", "QPGM", "QCMP", "QCQE", "QCDN", "QCOB", "QTB1", "QTDQ", "QTCI",
		"QTHQ", "QTHD", "QTPH", "QTSR", "QTSP", "QTSX", "QSHR", "PING", "PONG", "PONP" }) do
		peer:RecordCommsTraffic("received", command .. "|1")
	end
	for index = 1, 20 do
		peer:ScheduleDeferredWork("nameplate_tint_refresh", "nameplate" .. index, function() end,
			0, "ScheduleNameplateHealthTintRefresh")
	end
	peer:RecordDiagnosticError("outbound completion", string.rep("Lua error in addon callback; ", 43))
	function peer:BuildDeveloperDiagnosticSnapshot()
		self.builtReport = QuestTogether.BuildDeveloperDiagnosticSnapshot(self)
		return self.builtReport
	end
	return peer
end

QuestTogether:RegisterTest("large signed diagnostic reports survive real paging and reordered delivery", function()
	local dev, peer = DeveloperFixture(), BusyDiagnosticFixture()
	local ok, id = dev:SendPingRequest(peer.name, true)
	Equal(ok, true)
	assert(#dev.wire[1][2] <= 255)
	local request = peer:DecodePingRequestPayload(dev.wire[1][2]:sub(6))
	Equal(request.supportsLargePong, true)
	peer:OnCommReceived(peer.commPrefix, dev.wire[1][2], "WHISPER", dev.name)
	FinishDeveloperVerification(peer)
	for _ = 1, 1200 do
		if not peer.pingPageQueue or #peer.pingPageQueue.jobs == 0 then break end
		peer.clock:Advance(0.2)
	end
	assert(peer.builtReport and #peer:EscapePayload(peer.builtReport) > 16384)
	assert(#peer.builtReport <= 32768)
	Equal(#peer.pingPageQueue.jobs, 0)
	for index = #peer.wire, 1, -1 do
		local wire = peer.wire[index][2]
		assert(wire:match("^PONP|2,") and #wire <= 255)
		dev:OnCommReceived(dev.commPrefix, wire, "WHISPER", peer.name)
	end
	Equal(dev.pendingPingRequests[id].remoteReplies, 1)
	Equal(dev.report, peer.builtReport)
	assert(dev.report:find("option.shareDeveloperDiagnostics=true", 1, true))
end)

QuestTogether:RegisterTest("completed diagnostic reports survive departure without reviving sampled player state", function()
	for _, shared in ipairs({ true, false }) do
		local dev, name = DeveloperFixture(), "Friend-Realm"
		dev.API.GetServerTime = function() return 1791300000 + math.floor(dev.clock:GetTime()) end
		local ok, id = dev:SendPingRequest(name, true)
		Equal(ok, true)
		local response = Pong(dev, shared)
		response.requestId, response.diagnosticText = id, string.rep("Completed diagnostic report\n", 100)
		response.lookingForQuestPartners = true
		local pages = assert(dev:BuildPongPages(id, dev:EncodePingResponsePayload(response, true), 2))
		dev:RecordQTPlayerPresence(name, true)
		Equal(dev:IsKnownQTPlayer(name), true)
		dev.clock:Advance(2)
		assert(dev:RecordPeerDeparture(name, dev.API.GetTime(), "100000-1234", 2))
		for _, wire in ipairs(pages) do dev:OnCommReceived(dev.commPrefix, wire, "WHISPER", name) end
		Equal(dev.pendingPingRequests[id].remoteReplies, 1)
		Equal(dev.report, response.diagnosticText)
		Equal(dev.reportTitle, name)
		Equal(dev:IsKnownQTPlayer(name), false)
		Equal(dev:IsPlayerLookingForQuestPartners(name), false)
		Equal(#dev:GetVisiblePlayerLocations("map"), 0)
		Equal(dev.developerPlayerData[name], nil)
	end
end)

QuestTogether:RegisterTest("legacy diagnostic requesters receive an explicit oversized report result", function()
	local dev, peer = DeveloperFixture(), BusyDiagnosticFixture()
	local ok, id = dev:SendPingRequest(peer.name, true)
	Equal(ok, true)
	local request = peer:DecodePingRequestPayload(dev.wire[1][2]:sub(6))
	request.supportsLargePong = false
	peer:OnCommReceived(peer.commPrefix, "PING|" .. peer:EncodePingRequestPayload(request), "WHISPER", dev.name)
	FinishDeveloperVerification(peer)
	for _ = 1, 100 do peer.clock:Advance(0.2) end
	for _, packet in ipairs(peer.wire) do
		assert(packet[2]:match("^PONP|1,") and #packet[2] <= 255)
		dev:OnCommReceived(dev.commPrefix, packet[2], "WHISPER", peer.name)
	end
	Equal(dev.pendingPingRequests[id].remoteReplies, 1)
	assert(dev.report:find("diagnostics.status=report_too_large", 1, true))
end)

QuestTogether:RegisterTest("large pong budget covers worst case escaping and remains targeted and negotiated", function()
	local dev = DeveloperFixture()
	local _, id = dev:SendPingRequest("Friend-Realm", true)
	local report = string.rep("%,|\n", 8192)
	local payload = dev:EncodePingResponsePayload({ requestId=id, senderName="Friend-Realm", developer=true,
		diagnosticText=report }, true)
	local pages = assert(dev:BuildPongPages(id, payload, 2))
	assert(#payload > 98000 and #pages < 1024)
	Equal(dev:BuildPongPages(id, string.rep("x", 102401), 2), nil)
	Equal(dev:HandlePongPage(pages[1]:sub(6), "Other-Realm"), false)
	dev.pendingPingRequests[id].supportsLargePong = false
	Equal(dev:HandlePongPage(pages[1]:sub(6), "Friend-Realm"), false)
	dev.pendingPingRequests[id].supportsLargePong = true
	for _, wire in ipairs(pages) do
		assert(#wire <= 255)
		dev:OnCommReceived(dev.commPrefix, wire, "WHISPER", "Friend-Realm")
	end
	Equal(dev.report, report)
	local _, globalID = dev:SendPingRequest()
	Equal(dev:HandlePongPage("2," .. globalID .. ",1,2,hello", "Friend-Realm"), false)
end)

QuestTogether:RegisterTest("large pong assembly rejects format changes and expires within its request", function()
	local dev = DeveloperFixture()
	local _, id = dev:SendPingRequest("Friend-Realm", true)
	Equal(dev:HandlePongPage("2," .. id .. ",1,2,hello", "Friend-Realm"), true)
	Equal(dev:HandlePongPage("1," .. id .. ",2,2,world", "Friend-Realm"), false)
	Equal(dev:HandlePongPage("2," .. id .. ",2,2,world", "Friend-Realm"), false)
	local _, nextID = dev:SendPingRequest("Friend-Realm", true)
	local pending = dev.pendingPingRequests[nextID]
	Equal(pending.expiresAt, pending.startedAt + 300)
	Equal(dev:HandlePongPage("2," .. nextID .. ",1,2,hello", "Friend-Realm"), true)
	Equal(pending.expiresAt, pending.startedAt + 600)
	dev.clock:Advance(541)
	Equal(dev.pendingPingRequests[nextID], pending, "the original request timer honors the negotiated deadline")
	Equal(dev:HandlePongPage("2," .. nextID .. ",2,2,world", "Friend-Realm"), false)
end)

QuestTogether:RegisterTest("pong paging rejects unsolicited conflicting excessive and expired fragments",function()
	local a=DeveloperFixture()
	local _,id=a:SendPingRequest()
	local payload=a:EncodePingResponsePayload({requestId=id,senderName="Friend-Realm",zoneName=string.rep("Координаты",60)},true)
	local pages=a:BuildPongPages(id,payload)
	assert(#pages>1)
	Equal(a:HandlePongPage(pages[1]:sub(6),"Friend-Realm"),true)
	Equal(a:HandlePongPage(pages[1]:sub(6,-2).."x","Friend-Realm"),false)
	for i=2,#pages do Equal(a:HandlePongPage(pages[i]:sub(6),"Friend-Realm"),false) end
	Equal(a:HandlePongPage("1,unsolicited,1,2,hello","Other-Realm"),false)
	Equal(a:HandlePongPage("1,"..id..",1,999999,hello","Other-Realm"),false)
	Equal(a:HandlePongPage(pages[1]:sub(6),"Other-Realm"),true)
	a.clock:Advance(301)
	Equal(a:HandlePongPage(pages[2]:sub(6),"Other-Realm"),false)
	Equal(a:BuildPongPages(id,string.rep("x",17000)),nil)
end)

QuestTogether:RegisterTest("paged pong reassembles long localized fields exactly and waits for every page",function()
	local a=DeveloperFixture()
	local _,id=a:SendPingRequest()
	local zone=string.rep("Долина, остров | 漢字 % ",70)
	local response={requestId=id,senderName="Untrusted-Realm",zoneName=zone,raceName="Ночная эльфийка",coordX="42.5",coordY="63.2",mapID="12"}
	local payload=a:EncodePingResponsePayload(response,true)
	local pages=a:BuildPongPages(id,payload)
	assert(#pages>3)
	for i=#pages,2,-1 do
		assert(#pages[i]<=255)
		Equal(a:HandlePongPage(pages[i]:sub(6),"Friend-Realm"),true)
	end
	Equal(a.pendingPingRequests[id].remoteReplies,0)
	Equal(a:HandlePongPage(pages[1]:sub(6),"Friend-Realm"),true)
	Equal(a.pendingPingRequests[id].remoteReplies,1)
	Equal(a.printed[2].senderName,"Friend-Realm")
	Equal(a.printed[2].zoneName,zone)
	Equal(a.printed[2].raceName,response.raceName)
	Equal(a.printed[2].coordX,"42.5")
	Equal(a:HandlePongPage(pages[1]:sub(6),"Friend-Realm"),false)
end)

QuestTogether:RegisterTest("delayed diagnostic replies honor opt-out and reset before reading private positions",function()
	for _,reason in ipairs({"opt-out","reset"}) do
		local a=DeveloperFixture("Friend-Realm")
		a:InitializeGeographicComms()
		Equal(a:ScheduleGeographicPingReply("test",{{distribution="WHISPER",target="Dev-Realm"}},true,{developerVerified=true}),true)
		if reason=="opt-out" then a.db.profile.shareDeveloperDiagnostics=false else a:ResetCommsState() end
		a.clock:Advance(30)
		Equal(a.reads,nil)
		Equal(#a.wire,0)
	end
end)

QuestTogether:RegisterTest("announcement timestamps measure delayed delivery and leave old peers unknown", function()
	local sender, receiver = NewCommsFixture(), NewCommsFixture()
	local epoch = 1791086400
	sender.API.GetServerTime = function() return epoch end
	receiver.API.GetServerTime = function() return epoch + 210 end
	function receiver:HandleAnnouncementEvent(event) self.lastEvent = event end
	function receiver:RefreshQTPlayerPlatePresence() end
	local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 2/5", 123)
	Equal(event.occurredAt, epoch)
	local wire = "ANN|" .. sender:EncodeAnnouncementPayload(event)
	Equal(#wire <= 255, true)
	receiver:OnCommReceived(receiver.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, receiver.announcementChannelName)
	Equal(receiver.lastEvent.occurredAt, epoch)
	local diagnostics = receiver:GetCommsDiagnostics()
	Equal(diagnostics.announcementAgeLast, 210)
	Equal(diagnostics.announcementAgeSamples, 1)
	receiver:OnCommReceived(receiver.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, receiver.announcementChannelName)
	Equal(diagnostics.announcementAgeSamples, 1) -- duplicate delivery isn't another age sample
	Equal(diagnostics.traffic.ANN.received, 2)
	Equal(diagnostics.traffic.ANN.duplicate, 1)
	Equal(diagnostics.traffic.ANN.receivedBytes, #wire * 2)
	local legacy = wire:gsub(",%d+$", "")
	receiver.now = receiver.now + 1
	receiver:OnCommReceived(receiver.commPrefix, legacy, "CHANNEL", "Friend-Realm", 7, receiver.announcementChannelName)
	Equal(receiver.lastEvent.occurredAt, nil)
	Equal(diagnostics.announcementAgeUnknown, 1)
	event.occurredAt = epoch + 999
	receiver:RecordAnnouncementLatency(sender:DecodeAnnouncementPayload(sender:EncodeAnnouncementPayload(event)))
	Equal(diagnostics.announcementAgeUnknown, 2)
	event.occurredAt = "invalid"
	Equal(sender:DecodeAnnouncementPayload(sender:EncodeAnnouncementPayload(event)).occurredAt, nil)
	sender.API.GetServerTime = function() error("clock unavailable") end
	Equal(sender:GetAnnouncementServerTime(), nil)
end)

QuestTogether:RegisterTest("transport counters count each route attempt and bound unknown command buckets", function()
	local addon = NewCommsFixture()
	addon.API.GetChannelName = function(name) return name == addon.announcementChannelName and 6 or 7 end
	addon.API.SendAddonMessage = function(_, _, route) return route == "CHANNEL" and 0 or 3 end
	addon.API.IsInParty = function() return true end
	Equal(addon:SendWireMessageToAnnouncementRoutes("LOC|sample"), true)
	local diagnostics = addon:GetCommsDiagnostics()
	Equal(diagnostics.traffic.LOC.sent, 1)
	Equal(diagnostics.traffic.LOC.failed, 1)
	Equal(diagnostics.traffic.LOC.throttled, 1)
	Equal(diagnostics.traffic.LOC.sentBytes, 10)
	for i = 1, 100 do addon:RecordCommsTraffic("received", "UNKNOWN" .. i .. "|sample") end
	local count = 0
	for _ in pairs(diagnostics.traffic) do count = count + 1 end
	Equal(count, 2)
	Equal(diagnostics.traffic.OTHER.received, 100)
end)

QuestTogether:RegisterTest("unknown addon packets do not fall through into human channel chat", function()
	local addon = NewCommsFixture()
	function addon:CHAT_MSG_CHANNEL() error("addon traffic cannot become human chat") end
	function addon:RecordQTPlayerPresence() error("unknown commands cannot identify peers") end
	addon:OnCommReceived(addon.commPrefix, "FUTURE|Quest 844 — Objective 1: 5/7", "CHANNEL", "Friend-Realm", 7, addon.announcementChannelName)
	Equal(#addon.printed, 0)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("plain QT channel chat displays once without relaying or discovering peers", function()
	local addon = NewCommsFixture()
	local options = { showChatLogs = true, showChatBubbles = true }
	local bubbles, plate = {}, {}
	function addon:GetOption(key) return options[key] end
	function addon:PrintConsoleAnnouncement(text, _, _, eventType, icon, kind)
		Equal(eventType, "QT_CHAT")
		Equal(icon, "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon")
		Equal(kind, "texture")
		self.printed[#self.printed + 1] = text
	end
	function addon:IsRuntimeRestrictionTypeActive() return self.restricted == true end
	function addon:IsSelfSender(name) return name == "MyPlayer-Realm" end
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
	function addon:RecordQTPlayerPresence() error("plain chat cannot establish addon presence") end
	local function Receive(text, sender, channel, base)
		return addon:CHAT_MSG_CHANNEL("CHAT_MSG_CHANNEL", text, sender or "Friend-Realm", "",
			channel or "7. " .. addon.announcementChannelName, nil, nil, nil, 7,
			base, nil, 1, "Player-1-ABC")
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
	local inaccessible = setmetatable({}, { __tostring = function() error("inaccessible chat read") end })
	function addon:CanAccessValue(value) return value ~= inaccessible end
	Equal(Receive(inaccessible), false)
	Equal(Receive("hello", inaccessible), false)
	Equal(Receive("hello", nil, inaccessible, inaccessible), false)
	options.showChatLogs = true
	Receive(string.rep("é", 130))
	Equal(#addon.printed[#addon.printed], 254)
	addon.restricted = true
	Equal(Receive("restricted"), false)
	addon.restricted = false
	function addon:IsIgnoredPlayerName() return true end
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
	Equal(#addon.printed, 2)
	Equal(addon.printed[2].sender, "Anakin Othername")
	Equal(addon.printed[2].label, "Anakin Othername")
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
	addon.API.UnitFullName = function() return nil, nil end
	addon.GetPlayerFullName = function() return nil end
	addon.API.GetRealmName = function() error("regional profile fallback must not read a realm") end
	Equal(addon:GetCurrentCharacterKey(), "Anakin")
	Equal(addon:GetPersonalBubbleAnchorKey(), "Anakin")
	addon.API.UnitFullName = function() return "Anakin", "Ofthesea" end
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
	function addon:IsRuntimeRestricted() return false end
	function addon:GetLocationPinMapWorldSize() return 4000, 2000 end
	addon.GetPlayerAnnouncementLocationInfo = QuestTogether.GetPlayerAnnouncementLocationInfo
	addon.CanPublishPlayerLocation = function() return true end
	addon.API.GetBestMapForUnit = function() return 37 end
	addon.API.GetMapInfo = function() return { mapID = 37, name = "Elwynn Forest" } end
	addon.API.GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end
end

QuestTogether:RegisterTest("Forever metadata never reads or displays realms and War Mode", function()
	local addon = NewRegionalNameFixture()
	UseNativeLocationModel(addon)
	addon.API.GetRealmName = function() error("Forever has no realm identity") end
	addon.API.IsWarModeFeatureEnabled = function() error("regional clients have no War Mode") end
	addon.API.IsWarModeActive = function() error("unsupported mode must not be polled") end
	Equal(addon:SupportsWarMode(), false)
	local location = addon:GetPlayerAnnouncementLocationInfo()
	Equal(location.warMode, nil)
	Equal(location.mapID, 37)
	local metadata = addon:GetPlayerPingMetadata()
	Equal(metadata.realmName, "")
	Equal(metadata.warMode, "")
	Equal(metadata.senderName, "Anakin Ofthesea")
	metadata.requestId = "regional-ping"
	local decoded = addon:DecodePingResponsePayload(addon:EncodePingResponsePayload(metadata))
	Equal(decoded.realmName, "")
	Equal(decoded.warMode, "")
	Equal(decoded.senderName, metadata.senderName)
	local event = addon:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	Equal(event.warMode, "")
	Equal(addon:DecodeAnnouncementPayload(addon:EncodeAnnouncementPayload(event)).warMode, "")
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
				if capability == "enabled" then return true end
				if capability == "disabled" then return false end
				return nil
			end
			if capability == "missing" then addon.API.IsWarModeFeatureEnabled = nil end
			addon.API.IsWarModeActive = function()
				polls = polls + 1
				if state == "on" then return true end
				if state == "off" then return false end
			end
			local expected = ""
			if capability == "enabled" and state ~= "unknown" then expected = state == "on" and "1" or "0" end
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
	local inaccessible = setmetatable({}, { __tostring = function() error("inaccessible mode formatted") end })
	function addon:CanAccessValue(value) return value ~= inaccessible end
	addon.API.IsWarModeActive = function() return false end
	addon.API.IsWarModeFeatureEnabled = function() return inaccessible end
	Equal(addon:SupportsWarMode(), nil)
	Equal(addon:NormalizeAnnouncementWarModeValue(inaccessible), nil)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.API.IsWarModeFeatureEnabled = function() error("capability unavailable") end
	Equal(addon:SupportsWarMode(), nil)
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.API.IsWarModeFeatureEnabled = function() return false end
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	addon.API.IsWarModeFeatureEnabled = function() return true end
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	remote.warMode = "1"
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
end)

QuestTogether:RegisterTest("Forever nearby announcements use map distance without Retail War Mode", function()
	local sender, receiver = NewRegionalNameFixture(), NewRegionalNameFixture()
	UseNativeLocationModel(sender)
	UseNativeLocationModel(receiver)
	receiver.API.UnitFullName = function() return "Anakin", "Othername" end
	receiver.IsAnnouncementSenderNearbyByLocation = QuestTogether.IsAnnouncementSenderNearbyByLocation
	receiver.ShouldShowAnnouncementsForRemoteSender = QuestTogether.ShouldShowAnnouncementsForRemoteSender
	receiver.GetOption = function(_, key)
		if key == "showProgressFor" then return "party_nearby" end
		return key == "showChatLogs"
	end
	local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
	for _, legacyMode in ipairs({ "", "0", "1" }) do
		event.warMode = legacyMode
		assert(sender:SendAnnouncementWireEvent(event))
		receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire][2], "CHANNEL", "Anakin Ofthesea", 7,
			receiver.announcementChannelName)
		receiver.now = receiver.now + 1
	end
	Equal(#receiver.printed, 3)
	event.mapID = "999"
	assert(sender:SendAnnouncementWireEvent(event))
	receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire][2], "CHANNEL", "Anakin Ofthesea", 7,
		receiver.announcementChannelName)
	Equal(#receiver.printed, 3)
	event.mapID, event.coordX, event.coordY = "37", "90", "90"
	assert(sender:SendAnnouncementWireEvent(event))
	receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire][2], "CHANNEL", "Anakin Ofthesea", 7,
		receiver.announcementChannelName)
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
	local addon = NewCommsFixture()
	for _, result in ipairs({ 1, 2, 3, 7, 8, 11, false }) do
		addon.API.SendAddonMessage = function()
			return result
		end
		Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	end
	addon.API.SendAddonMessage = function()
		return nil
	end
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	addon.API.SendAddonMessage = function()
		error("transport failed")
	end
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	for _, result in ipairs({ 0, true }) do
		addon.API.SendAddonMessage = function()
			return result
		end
		Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), true)
	end
	Equal(addon:GetCommsDiagnostics().failedRoutes, 9)
	Equal(addon:GetCommsDiagnostics().sentRoutes, 2)
end)

QuestTogether:RegisterTest("comms resolves channel target after rejoining", function()
	local addon = NewCommsFixture()
	addon.channelID = 0
	addon.announcementChannelLocalID = 2
	function addon:EnsureAnnouncementChannelJoined()
		self.channelID = 9
		self.announcementChannelLocalID = 9
		return true
	end
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), true)
	Equal(addon.wire[1][4], 9)
end)

QuestTogether:RegisterTest("announcement packets fit escaped byte budget without cutting UTF8", function()
	local addon = NewCommsFixture()
	local text = string.rep("写真", 30)
	local payload = addon:EncodeAnnouncementPayload(Event(text))
	local decoded = addon:DecodeAnnouncementPayload(payload)
	Equal(#("ANN|" .. payload) <= 255, true)
	Equal(decoded ~= nil, true)
	Equal(#decoded.text % 3, 0)
	Equal(string.sub(text, 1, #decoded.text), decoded.text)
	Equal(addon:SendAnnouncementWireEvent(Event(text)), true)
	Equal(#addon.wire[1][2] <= 255, true)
end)

QuestTogether:RegisterTest("announcement local text limit preserves complete UTF8", function()
	local addon = NewCommsFixture()
	local text = addon:SanitizeAnnouncementText(string.rep("写", 100))
	Equal(#text, 219)
	Equal(string.sub(text, -3), "写")
end)

QuestTogether:RegisterTest("quest comparison titles fit escaped packet budget", function()
	local addon = NewCommsFixture()
	local payload = addon:EncodeQuestCompareEntryPayload({
		requestId = "qcmp-123",
		senderName = "Friend-Realm",
		classFile = "MAGE",
		questId = "12345",
		questTitle = string.rep("写真", 80),
	})
	Equal(#("QCQE|" .. payload) <= 255, true)
	local decoded = addon:DecodeQuestCompareEntryPayload(payload)
	Equal(decoded.questId, "12345")
	Equal(#decoded.questTitle % 3, 0)
end)

QuestTogether:RegisterTest("oversized transport messages fail before sending", function()
	local addon = NewCommsFixture()
	Equal(addon:SendWireMessageToAnnouncementRoutes(string.rep("x", 256)), false)
	Equal(#addon.wire, 0)
	Equal(addon:GetCommsDiagnostics().invalidMessages, 1)
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
	local addon = NewCommsFixture()
	addon.pendingQuestCompareRequests.test = { targetName = "Friend-Realm", count = 0 }
	local entry = { requestId = "test", senderName = "Friend-Realm", questId = "12345" }
	Equal(addon:HandleQuestCompareEntry(entry), true)
	addon.now = 105
	Equal(addon:HandleQuestCompareEntry(entry), false)
	Equal(addon.pendingQuestCompareRequests.test.count, 1)
	Equal(#addon.printed, 0) -- Partial generations stay private until complete.
end)

QuestTogether:RegisterTest("quest comparison waits for entries after early completion marker", function()
	local addon = NewCommsFixture()
	addon.pendingQuestCompareRequests.test = { targetName = "Friend-Realm", count = 0 }
	Equal(addon:HandleQuestCompareDone({ requestId = "test", senderName = "Friend-Realm", count = 2 }), true)
	Equal(#addon.printed, 0)
	Equal(addon:HandleQuestCompareEntry({ requestId = "test", senderName = "Friend-Realm", questId = "100" }), true)
	Equal(addon.pendingQuestCompareRequests.test ~= nil, true)
	Equal(addon:HandleQuestCompareEntry({ requestId = "test", senderName = "Friend-Realm", questId = "200" }), true)
	Equal(addon.pendingQuestCompareRequests.test, nil)
	Equal(addon.printed[3], "done:2")
end)

QuestTogether:RegisterTest("ping responses deduplicate each sender for entire request", function()
	local addon = NewCommsFixture()
	addon.pendingPingRequests.test = { responders = {} }
	local response = { requestId = "test", senderName = "Friend-Realm" }
	Equal(addon:HandlePingResponse(response), true)
	addon.now = 105
	Equal(addon:HandlePingResponse(response), false)
	Equal(addon:HandlePingResponse({ requestId = "test", senderName = "Friend-OtherRealm" }), true)
	Equal(#addon.printed, 2)
end)

QuestTogether:RegisterTest("ping round trip reaches current-channel peers with distinct channel IDs and Forever names", function()
	for _, regional in ipairs({ false, true }) do
		local function Peer(first, surname, currentID, legacyID)
			local addon = NewCommsFixture()
			addon.clock = addon:CreateTestClock(addon.now)
			addon.API.GetTime = function() return addon.clock:GetTime() end
			addon.API.Delay = function(seconds, callback) addon.clock:After(seconds, callback) end
			addon.channelRequestSequence = 0
			addon.logs = {}
			addon.API.RegionalUniqueNamesEnabled = function() return regional end
			addon.API.UnitFullName = function() return first, surname end
			addon.API.UnitName = function() return first end
			addon.API.GetChannelName = function(name)
				return name == addon.announcementChannelName and currentID or legacyID
			end
			function addon:Debugf(_, format, ...) self.logs[#self.logs + 1] = string.format(format, ...) end
			function addon:RefreshQTPlayerPlatePresence() end
			function addon:HideAnnouncementChannelFromChatWindows() end
			return addon
		end
		local localPeer = Peer("Barbara", "Myers", 8, 9)
		local remote = Peer("Seras", "Aran", 3, 4)
		local ok, id = localPeer:SendPingRequest()
		Equal(ok, true)
		Equal(#localPeer.printed, 1) -- local pong alone proves no delivery
		Equal(#localPeer.wire, 1)
		Equal(localPeer.wire[1][4], 8)
		-- Deliver actual packets with recipient-local channel IDs.
		remote:OnCommReceived(remote.commPrefix, localPeer.wire[1][2], "CHANNEL", localPeer:GetPlayerFullName(), 3, remote.announcementChannelName)
		Equal(#remote.wire, 1)
		Equal(remote.wire[1][3], "WHISPER")
		Equal(remote.wire[1][4], localPeer:GetPlayerFullName())
		for _, packet in ipairs(remote.wire) do
			local current = packet[4] == 3
			localPeer:OnCommReceived(localPeer.commPrefix, packet[2], packet[3], remote:GetPlayerFullName(), current and 8 or 9,
				current and localPeer.announcementChannelName or localPeer.announcementChannelName)
		end
		Equal(#localPeer.printed, 2)
		Equal(localPeer.printed[2], remote:GetPlayerFullName())
		Equal(localPeer.pendingPingRequests[id].remoteReplies, 1)
		localPeer.clock:Advance(300)
		Equal(localPeer.pendingPingRequests[id], nil)
		assert(table.concat(localPeer.logs, "\n"):find("remoteReplies=1", 1, true))
		-- Late responses remain identifiable in diagnostics after the timeout.
		localPeer.clock:Advance(11)
		localPeer:OnCommReceived(localPeer.commPrefix, remote.wire[1][2], "CHANNEL", remote:GetPlayerFullName(), 9, localPeer.announcementChannelName)
		Equal(#localPeer.printed, 2)
		assert(table.concat(localPeer.logs, "\n"):find("ping reply unmatched", 1, true))
	end
end)

QuestTogether:RegisterTest("ping accepts a delayed three minute reply once and expires after five minutes", function()
	local addon = NewCommsFixture()
	local clock = addon:CreateTestClock(3745.484)
	addon.API.GetTime = function() return clock:GetTime() end
	addon.API.Delay = function(seconds, callback) clock:After(seconds, callback) end
	local ok, id = addon:SendPingRequest()
	Equal(ok, true)
	clock:Advance(209.956) -- observed live channel delay
	local response = { requestId = id, senderName = "Friend-Realm" }
	Equal(addon:HandlePingResponse(response), true)
	clock:Advance(1)
	Equal(addon:HandlePingResponse(response), false)
	Equal(#addon.printed, 2)
	Equal(#addon.wire, 1) -- no retries or extra messages while waiting
	clock:Advance(90)
	Equal(addon.pendingPingRequests[id], nil)
	Equal(addon:HandlePingResponse({ requestId = id, senderName = "Other-Realm" }), false)
end)

QuestTogether:RegisterTest("ping retention stays bounded and rejects expired or reset requests", function()
	local addon = NewCommsFixture()
	local ids = {}
	for i = 1, 9 do
		addon.now = addon.now + 1
		local ok, id = addon:SendPingRequest()
		Equal(ok, true)
		ids[i] = id
	end
	Equal(addon.pendingPingRequests[ids[1]], nil)
	local count = 0
	for _ in pairs(addon.pendingPingRequests) do count = count + 1 end
	Equal(count, 8)
	addon.delayed[1]() -- evicted request's callback cannot remove newer work
	Equal(addon.pendingPingRequests[ids[9]] ~= nil, true)
	addon.now = addon.now + 301 -- expiry also enforced before delayed timer execution
	Equal(addon:HandlePingResponse({ requestId = ids[9], senderName = "Friend-Realm" }), false)
	local ok, id = addon:SendPingRequest()
	Equal(ok, true)
	addon.pendingPingRequests = {} -- reset/reload never trusts an old request ID
	Equal(addon:HandlePingResponse({ requestId = id, senderName = "Friend-Realm" }), false)
end)

QuestTogether:RegisterTest("ping replies use only the requesting group or named channel", function()
	local addon = NewCommsFixture()
	local request = { requestId = "route-test", requesterName = "Friend-Realm" }
	Equal(addon:HandlePingRequest(request, "PARTY"), true)
	Equal(#addon.wire, 1)
	Equal(addon.wire[1][3], "PARTY")
	Equal(addon:HandlePingRequest(request, "CHANNEL", 7, "7. QuestTogether"), true)
	Equal(#addon.wire, 2)
	Equal(addon.wire[2][3], "CHANNEL")
	Equal(addon:HandlePingRequest(request, "CHANNEL", 7, "OtherChannel"), false)
	Equal(addon:HandlePingRequest(request, "WHISPER"), false)
	Equal(#addon.wire, 2)
end)

QuestTogether:RegisterTest("stale quest compare timeout cannot clear a replacement request", function()
	local addon = NewCommsFixture()
	Equal(addon:RequestQuestCompare("Friend-Realm"), true)
	local requestId = next(addon.pendingQuestCompareRequests)
	local replacement = { targetName = "Friend-Realm", count = 1 }
	addon.pendingQuestCompareRequests[requestId] = replacement
	addon.delayed[1]()
	Equal(addon.pendingQuestCompareRequests[requestId], replacement)
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("incomplete quest comparison reports timeout instead of completion", function()
	local addon = NewCommsFixture()
	Equal(addon:RequestQuestCompare("Friend-Realm"), true)
	local requestId = next(addon.pendingQuestCompareRequests)
	addon:HandleQuestCompareDone({ requestId = requestId, senderName = "Friend-Realm", count = 2 })
	addon:HandleQuestCompareEntry({ requestId = requestId, senderName = "Friend-Realm", questId = "100" })
	addon.delayed[1]()
	Equal(addon.pendingQuestCompareRequests[requestId], nil)
	Equal(addon.printed[1], "Quest comparison timed out (1 quests received).")
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

QuestTogether:RegisterTest("incoming sender identity remains transport authoritative", function()
	local addon = NewCommsFixture()
	local seen
	function addon:HandleAnnouncementEvent(event)
		seen = event.senderName
	end
	local event = Event()
	event.senderName = "MyPlayer-Realm"
	addon:OnCommReceived(addon.commPrefix, "ANN|" .. addon:EncodeAnnouncementPayload(event), "PARTY", "Friend-Realm")
	Equal(seen, "Friend-Realm")
end)

QuestTogether:RegisterTest("disabled comm receiver does not dispatch announcements", function()
	local addon = NewCommsFixture()
	addon.isEnabled = false
	local count = 0
	function addon:HandleAnnouncementEvent()
		count = count + 1
	end
	addon:OnCommReceived(addon.commPrefix, "ANN|" .. addon:EncodeAnnouncementPayload(Event()), "PARTY", "Friend-Realm")
	Equal(count, 0)
end)

QuestTogether:RegisterTest("quest compare done rejects invalid or fractional counts", function()
	local addon = NewCommsFixture()
	for _, count in ipairs({ "bad", "-1", "1.5" }) do
		Equal(addon:DecodeQuestCompareDonePayload("1,test,Friend-Realm,MAGE," .. count), nil)
	end
end)

local function NewLevelUpFixture()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.emotes = {}
	addon.API.Random = function() return 1 end
	addon.API.DoEmote = function(token, target)
		addon.emotes[#addon.emotes + 1] = { token = token, target = target }
	end
	addon.API.CanTargetUnitForEmote = function(unit) return unit == "target" or unit == "nameplate1" end
	addon.API.UnitExists = function(unit) return unit == "player" or unit == "target" or unit == "nameplate1" end
	addon.API.UnitIsPlayer = function() return true end
	addon.API.UnitGUID = function(unit) return unit == "player" and "Player-self" or "Player-1-ABC" end
	addon.API.UnitFullName = function(unit) return unit == "player" and "MyPlayer" or "Friend", "Realm" end
	addon.API.UnitName = function(unit) return unit == "player" and "MyPlayer" or "Friend" end
	function addon:IsRuntimeRestricted() return false end
	function addon:IsRuntimeRestrictionTypeActive() return false end
	function addon:FindVisiblePlayerNameplateForSender() return nil end
	function addon:FindNearbyPlayerUnitTokenForSender() return "target" end
	function addon:IsAnnouncementSenderNearbyByLocation() return false end
	function addon:ShowAnnouncementBubbleOnUnitNameplate() error("level-up should only play an emote") end
	function addon:ShowAnnouncementBubbleOnNameplate() error("level-up should only play an emote") end
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
	addon.API.UnitFullName = function(unit) return unit == "player" and "MyPlayer" or "Friend", "Realm" end
	addon.API.UnitName = function(unit) return unit == "player" and "MyPlayer" or "Friend" end
	addon.API.UnitExists = function(unit) return unit == "player" or unit == "target" end
	addon.API.UnitIsPlayer = function() return true end
	addon.API.UnitGUID = function(unit) return unit == "player" and "Player-self" or "Player-friend" end
	addon.API.IsMounted = function() return false end
	addon.API.GetFaction = function() return "Neutral" end
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
	local wire = command .. "|" .. addon:EncodeAnnouncementPayload(event)
	Equal(#wire <= 255, true)
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", sender or "Friend-Realm", 7, addon.announcementChannelName)
end

QuestTogether:RegisterTest("received celebrations reject unsupported and malformed emote tokens", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, token in ipairs({ "rude", "not-an-emote", "cheer rude", "cheer\nrude", "|Hplayer:Friend|hcheer|h", "\0cheer", "123", "true", "" }) do
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

QuestTogether:RegisterTest("received out-of-list special celebrations are rejected regardless of mount or faction", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "WORLD_QUEST_COMPLETED", "BONUS_OBJECTIVE_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, token in ipairs({ " MOUNTSPECIAL ", " FORTHEHORDE ", " FORTHEALLIANCE " }) do
			for _, faction in ipairs({ "Alliance", "Horde", "Neutral" }) do
				local addon = NewRemoteCelebrationFixture()
				addon.API.IsMounted = function() return true end
				addon.API.GetFaction = function() return faction end
				ReceiveCelebration(addon, eventType, token)
				Equal(addon:GetCommsDiagnostics().acceptedAnnouncements, 1)
				Equal(#addon.emotes, 0)
			end
		end
	end
end)

QuestTogether:RegisterTest("received celebration validation retains identity scope and option checks", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, blockedBy in ipairs({ "option", "scope", "ignored", "self", "identity" }) do
			local addon = NewRemoteCelebrationFixture()
			if blockedBy == "option" then
				local option = eventType == "PLAYER_LEVEL_UP" and "emoteOnNearbyPlayerLevelUp" or "emoteOnNearbyPlayerQuestCompletion"
				addon.db.profile[option] = false
			elseif blockedBy == "scope" then
				addon.db.profile.showProgressFor = "party_only"
			elseif blockedBy == "ignored" then
				addon.IsIgnoredPlayerName = function() return true end
			end
			local sender = blockedBy == "self" and "MyPlayer-Realm" or (blockedBy == "identity" and "Other-Realm" or "Friend-Realm")
			ReceiveCelebration(addon, eventType, "CHEER", sender)
			Equal(#addon.emotes, 0)
		end
	end
end)

QuestTogether:RegisterTest("remote celebration validation never stringifies inaccessible or non-string tokens", function()
	local addon = NewRemoteCelebrationFixture()
	local inaccessible = setmetatable({}, { __tostring = function() error("inaccessible token stringified") end })
	local accessible = setmetatable({}, { __tostring = function() error("non-string token stringified") end })
	addon.CanAccessValue = function(_, value) return value ~= inaccessible end
	for _, token in ipairs({ inaccessible, accessible, 123, true, false }) do
		Equal(addon:GetSafeRemoteCompletionEmote(token), nil)
	end
	Equal(addon:GetSafeRemoteCompletionEmote(nil), nil)
end)

QuestTogether:RegisterTest("remote celebrations cannot expand their shipped list through runtime mutation", function()
	local addon = NewRemoteCelebrationFixture()
	addon.completionEmotes = { "rude", "mountspecial", "forthealliance", "forthehorde" }
	addon.API.Random = function() error("unsupported incoming emotes must not pick a substitute") end
	for _, token in ipairs(addon.completionEmotes) do
		ReceiveCelebration(addon, "QUEST_COMPLETED", token)
	end
	Equal(#addon.emotes, 0)
	Equal(addon:GetSafeRemoteCompletionEmote("cheer"), "cheer")
end)

QuestTogether:RegisterTest("remote rejected celebrations never query mount or faction or choose a fallback", function()
	local addon = NewRemoteCelebrationFixture()
	addon.API.IsMounted = function() error("mount state is irrelevant") end
	addon.API.GetFaction = function() error("faction is irrelevant") end
	addon.API.Random = function() error("no replacement emote") end
	for _, token in ipairs({ "mountspecial", "forthealliance", "forthehorde", "rude" }) do
		Equal(addon:GetSafeRemoteCompletionEmote(token), nil)
	end
end)

QuestTogether:RegisterTest("level-up sends one shared emote token on party and nearby routes", function()
	local addon = NewLevelUpFixture()
	addon.db.profile.emoteOnQuestCompletion = false
	addon.API.IsInParty = function() return true end
	Equal(addon:PLAYER_LEVEL_UP("PLAYER_LEVEL_UP", 20), true)
	Equal(#addon.wire, 2)
	Equal(addon.wire[1][3], "PARTY")
	Equal(addon.wire[2][3], "CHANNEL")
	Equal(addon.wire[1][2], addon.wire[2][2])
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	Equal(command, "LVL")
	local event = addon:DecodeAnnouncementPayload(payload)
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
	addon.CanAccessValue = function() return false end
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
	addon.FindNearbyPlayerUnitTokenForSender = function() return nil end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.db.profile.showProgressFor = "party_nearby"
	addon.partyMembers = {}
	addon.db.profile.devLogAllAnnouncements = true
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1)
	addon.IsAnnouncementSenderNearbyByLocation = function() return true end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 1) -- Coordinates cannot establish visibility in this layer.
	addon.FindVisiblePlayerNameplateForSender = function()
		return { GetUnit = function() return "nameplate1" end }
	end
	addon:HandleAnnouncementEvent(LevelUpEvent(), false)
	Equal(#addon.emotes, 2)
	Equal(addon.emotes[2].target, "nameplate1")
	Equal(#addon.printed, 0)
end)

QuestTogether:RegisterTest("level-up wire uses transport identity and suppresses duplicates self and ignored senders", function()
	local addon = NewLevelUpFixture()
	addon.FindNearbyPlayerUnitTokenForSender = function(_, _, senderName)
		Equal(senderName, "Friend-Realm")
		return "target"
	end
	local event = LevelUpEvent()
	event.senderName = "Spoofed-Realm"
	local wire = "LVL|" .. addon:EncodeAnnouncementPayload(event)
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Friend-Realm")
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, addon.announcementChannelName)
	Equal(#addon.emotes, 1)
	Equal(#addon.printed, 0)
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "MyPlayer-Realm")
	addon.IsIgnoredPlayerName = function() return true end
	addon:OnCommReceived(addon.commPrefix, wire, "PARTY", "Ignored-Realm")
	Equal(#addon.emotes, 1)
end)

QuestTogether:RegisterTest("remote celebrations require a current visible matching unit even with dev logging", function()
	for _, eventType in ipairs({ "QUEST_COMPLETED", "WORLD_QUEST_COMPLETED", "BONUS_OBJECTIVE_COMPLETED", "PLAYER_LEVEL_UP" }) do
		for _, failure in ipairs({ "coordinates", "other layer", "gone", "recycled GUID", "wrong name", "not player", "restricted", "chat restricted", "unknown", "error" }) do
			local addon = NewRemoteCelebrationFixture()
			addon.db.profile.showChatLogs = true
			addon.db.profile.devLogAllAnnouncements = true
			addon.IsAnnouncementSenderNearbyByLocation = function() return true end
			if failure == "coordinates" then
				addon.FindNearbyPlayerUnitTokenForSender = function() return nil end
			elseif failure == "other layer" then
				addon.API.CanTargetUnitForEmote = function() return false end
			elseif failure == "gone" then
				addon.FindNearbyPlayerUnitTokenForSender = function() return "target" end
				addon.API.UnitExists = function() return false end
			elseif failure == "recycled GUID" then
				addon.FindNearbyPlayerUnitTokenForSender = function() return "target" end
				addon.API.UnitGUID = function() return "Player-other" end
			elseif failure == "wrong name" then
				addon.FindNearbyPlayerUnitTokenForSender = function() return "target" end
				addon.API.UnitFullName = function() return "SomeoneElse", "Realm" end
			elseif failure == "not player" then
				addon.FindNearbyPlayerUnitTokenForSender = function() return "target" end
				addon.API.UnitIsPlayer = function() return false end
			elseif failure == "restricted" then
				addon.IsRuntimeRestricted = function() return true end
			elseif failure == "chat restricted" then
				addon.IsRuntimeRestrictionTypeActive = function(_, kind) return kind == "chat" end
			elseif failure == "unknown" then
				local inaccessible = {}
				addon.CanAccessValue = function(_, value) return value ~= inaccessible end
				addon.API.CanTargetUnitForEmote = function() return inaccessible end
			elseif failure == "error" then
				addon.API.CanTargetUnitForEmote = function() error("unit unavailable") end
			end
			ReceiveCelebration(addon, eventType, "cheer")
			Equal(#addon.emotes, 0)
			if eventType ~= "PLAYER_LEVEL_UP" then Equal(#addon.printed, 1) end
			Equal(#addon.delayed, 0) -- Never defer a reaction until someone becomes visible.
		end
	end
end)

QuestTogether:RegisterTest("remote plate celebrations handle recycled forbidden and unreadable plate units", function()
	for _, failure in ipairs({ "valid", "recycled", "forbidden", "getter error", "unreadable" }) do
		local addon = NewRemoteCelebrationFixture()
		local inaccessible = {}
		addon.CanAccessValue = function(_, value) return value ~= inaccessible end
		addon.API.UnitExists = function(unit) return unit == "nameplate1" end
		addon.API.UnitGUID = function() return failure == "recycled" and "Player-other" or "Player-friend" end
		local plate = {
			IsForbidden = function() return failure == "forbidden" end,
			GetUnit = function()
				if failure == "forbidden" or failure == "getter error" then error("do not read plate") end
				return failure == "unreadable" and inaccessible or "nameplate1"
			end,
		}
		addon.FindVisiblePlayerNameplateForSender = function() return plate end
		ReceiveCelebration(addon, "QUEST_COMPLETED", "cheer")
		Equal(#addon.emotes, failure == "valid" and 1 or 0)
	end
end)

QuestTogether:RegisterTest("self celebrations do not require remote target visibility", function()
	local addon = NewLevelUpFixture()
	addon.API.CanTargetUnitForEmote = function() error("self emotes must not use remote targeting") end
	addon.API.UnitExists = function() return false end
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
	addon:OnCommReceived(addon.commPrefix, "LVL|" .. addon:EncodeAnnouncementPayload(event), "PARTY", "Friend-Realm")
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
		RegisterEvent = function(_, name) registered[name] = true end,
		UnregisterEvent = function(_, name) registered[name] = nil end,
	}
	addon:RegisterRuntimeEvents()
	Equal(registered.PLAYER_LEVEL_UP, true)
	addon:UnregisterRuntimeEvents()
	Equal(registered.PLAYER_LEVEL_UP, nil)
end)

QuestTogether:RegisterTest("localized announcement metadata and default icon fit a real send", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function() return "Алесандра", "Гордунни" end
	addon.API.UnitGUID = function() return "Player-1602-12345678" end
	function addon:GetPlayerClassFile() return "DEATHKNIGHT" end
	function addon:GetPlayerAnnouncementLocationInfo()
		return { mapID = 2248, zoneName = "Остров Дорн", coordX = 50.1, coordY = 40.2, warMode = false }
	end
	local event = addon:BuildLocalAnnouncementEvent("QUEST_ACCEPTED", "Quest accepted: A normal quest", 12345)
	Equal(event.iconAsset, "Interface/GossipFrame/AvailableQuestIcon")
	Equal(addon:SendAnnouncementWireEvent(event), true)
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	local decoded = addon:DecodeAnnouncementPayload(payload)
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
	_, payload = addon:DeserializeWireMessage(addon.wire[2][2])
	decoded = addon:DecodeAnnouncementPayload(payload)
	Equal(#addon.wire[2][2] <= 255, true)
	Equal(decoded.senderName, event.senderName)
	Equal(decoded.text, event.text)
	Equal(decoded.zoneName, "")
	Equal(decoded.mapID, "2248")
	Equal(decoded.coordX, "50.1")
	Equal(decoded.coordY, "40.2")
end)

QuestTogether:RegisterTest("localized ping metadata sends without shortening player identity", function()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function() return "Алесандра", "Гордунни" end
	addon.API.UnitRace = function() return "Ночная эльфийка" end
	addon.API.UnitClass = function() return "Рыцарь смерти", "DEATHKNIGHT" end
	addon.API.UnitLevel = function() return 80 end
	function addon:GetPlayerAnnouncementLocationInfo()
		return { zoneName = "Остров Дорн", mapID = 2248, coordX = 50.1, coordY = 40.2, warMode = false }
	end
	local requestId = "ping-Character-12345678-1234"
	Equal(addon:SendPingResponse(requestId), true)
	local _, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	local response = addon:DecodePingResponsePayload(payload)
	Equal(#addon.wire[1][2] <= 255, true)
	Equal(response.senderName, "Алесандра-Гордунни")
	Equal(response.requestId, requestId)
	Equal(response.raceName, "Ночная эльфийка")
	-- Long optional labels can be omitted, but mandatory identity survives.
	function addon:GetPlayerAnnouncementLocationInfo() return { zoneName = string.rep("Долина", 40) } end
	Equal(addon:SendPingResponse(requestId), true)
	_, payload = addon:DeserializeWireMessage(addon.wire[2][2])
	response = addon:DecodePingResponsePayload(payload)
	Equal(#addon.wire[2][2] <= 255, true)
	Equal(response.senderName, "Алесандра-Гордунни")
	Equal(response.requestId, requestId)
	Equal(response.zoneName, "")
end)

QuestTogether:RegisterTest("wire escaping preserves UTF8 and legacy percent encoded payloads", function()
	local addon = NewCommsFixture()
	local original = "Дорн, 100% | test\0\n"
	local escaped = addon:EscapePayload(original)
	Equal(addon:UnescapePayload(escaped), original)
	Equal(escaped:find(",", 1, true), nil)
	Equal(escaped:find("|", 1, true), nil)
	Equal(escaped:find("\0", 1, true), nil)
	Equal(addon:UnescapePayload("%D0%94%D0%BE%D1%80%D0%BD%2C%20test"), "Дорн, test")
end)

local function InstallResponseClock(addon)
	addon.delayed = {}
	addon.API.Delay = function(seconds, callback)
		addon.delayed[#addon.delayed + 1] = { seconds = seconds, callback = callback }
	end
end

local function RunResponseTimer(addon)
	local timer = table.remove(addon.delayed, 1)
	if not timer then return false end
	addon.now = addon.now + timer.seconds
	timer.callback()
	return true
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
	local a = NewCommsFixture()
	local clock = QuestTogether:CreateTestClock(100)
	a.API.GetTime = function() return clock:GetTime() end
	a.API.Delay = function(delay, callback) clock:After(delay, callback) end
	SetComparisonEntries(a, 2)
	a:InitializeGeographicComms()
	a:GetTransportState().blockedUntil = 110
	assert(a:HandleQuestCompareRequest({requestId="paced-response",requesterName="Peer-Realm",targetName="MyPlayer-Realm",replyDistribution="CHANNEL"}))
	for _=1,35 do clock:Advance(0.2); a:DrainGeographicQueue() end
	Equal(#a.wire,0); Equal(#a.questCompareResponseQueue.jobs,1)
	Equal(a.questCompareResponseQueue.jobs[1].attempts,0)
	for _=1,35 do clock:Advance(0.2); a:DrainGeographicQueue() end
	Equal(#a.questCompareResponseQueue.jobs,0); Equal(#a.wire,3)
	assert(a.wire[3][2]:find("QCDN|",1,true))
end)

QuestTogether:RegisterTest("existing channels install filters once and avoid per-packet chat cleanup", function()
	local a = NewCommsFixture()
	local filters, cleanups = 0, 0
	a.announcementChannelChatFiltersRegistered = false
	a.API.AddMessageEventFilter = function() filters = filters + 1 end
	function a:HideAnnouncementChannelFromChatWindows() cleanups = cleanups + 1 end
	function a:IsRuntimeRestricted() return false end
	for _ = 1, 20 do assert(a:EnsureAnnouncementChannelJoined()) end
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
	function a:SendAnnouncementWireEvent(event) self.sentEvent = event; return true end
	function a:AnnounceToNonQTParty(event) self.partyEvent = event end
	function a:HandleAnnouncementEvent(event) self.localEvent = event end
	a.suppressLocalAnnouncementDisplayDuringTests = false
	assert(a:PublishAnnouncementEvent("QUEST_PROGRESS", "Progress"))
	Equal(builds, 1)
	Equal(a.sentEvent, a.partyEvent)
	Equal(a.sentEvent, a.localEvent)
end)

QuestTogether:RegisterTest("oversized or nul-containing inbound transport is rejected before decoding", function()
	local a = NewCommsFixture()
	function a:DeserializeWireMessage() error("invalid packet reached parser") end
	a:OnCommReceived(a.commPrefix, "ANN|" .. string.rep("x", 252), "PARTY", "Peer-Realm")
	a:OnCommReceived(a.commPrefix, "PING|1,a\0b", "PARTY", "Peer-Realm")
end)

QuestTogether:RegisterTest("quest comparison paces and retries delivery before completing the real receiver", function()
	local sender, receiver = NewCommsFixture(), NewCommsFixture()
	InstallResponseClock(sender)
	InstallResponseClock(receiver)
	sender.API.UnitFullName = function() return "Friend", "Realm" end
	sender.API.UnitName = function() return "Friend" end
	sender.partyMembers["MyPlayer-Realm"] = {}
	SetComparisonEntries(sender, 12)
	Equal(receiver:RequestQuestCompare("Friend-Realm"), true)
	local requestId = next(receiver.pendingQuestCompareRequests)
	Equal(receiver.delayed[1].seconds >= 120, true)
	local attempts, rejected, lastAttemptAt = 0, false, nil
	sender.API.SendAddonMessage = function(prefix, message, route)
		Equal(route, "PARTY")
		if lastAttemptAt then Equal(sender.now - lastAttemptAt >= 0.099, true) end
		lastAttemptAt = sender.now
		attempts = attempts + 1
		if attempts == 2 then rejected = true; return 3 end
		receiver.now = sender.now
		receiver:OnCommReceived(prefix, message, route, "Friend-Realm")
		return 0
	end
	sender:OnCommReceived(sender.commPrefix, receiver.wire[1][2], "PARTY", "MyPlayer-Realm")
	Equal(attempts, 1)
	Equal(receiver.pendingQuestCompareRequests[requestId].count, 1)
	for _ = 1, 20 do if not RunResponseTimer(sender) then break end end
	Equal(rejected, true)
	Equal(attempts, 14)
	Equal(receiver.pendingQuestCompareRequests[requestId], nil)
	Equal(#receiver.printed, 13)
	Equal(receiver.printed[13], "done:12")
	Equal(#sender.questCompareResponseQueue.jobs, 0)
	Equal(sender.questCompareResponseQueue.packets, 0)
end)

QuestTogether:RegisterTest("quest comparison retry exhaustion never advertises a partial result as complete", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 3)
	local attempts, donePackets = 0, 0
	addon.API.SendAddonMessage = function(_, message)
		attempts = attempts + 1
		if message:find("^QCDN|") then donePackets = donePackets + 1 end
		return attempts == 1 and 0 or 3
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "retry", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	for _ = 1, 10 do if not RunResponseTimer(addon) then break end end
	Equal(attempts, 6)
	Equal(donePackets, 0)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(addon:GetCommsDiagnostics().failedComparisons, 1)
end)

QuestTogether:RegisterTest("quest comparison queues expire and old callbacks cannot send after reset", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 3)
	local request = { requestId = "old", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }
	Equal(addon:HandleQuestCompareRequest(request), true)
	local expiredCount = #addon.wire
	addon.now = addon.now + 451
	RunResponseTimer(addon)
	Equal(#addon.wire, expiredCount)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	request.requestId = "reset"
	Equal(addon:HandleQuestCompareRequest(request), true)
	local oldTimer = table.remove(addon.delayed, 1)
	addon:ResetCommsState()
	request.requestId = "replacement"
	Equal(addon:HandleQuestCompareRequest(request), true)
	local replacementQueue, before = addon.questCompareResponseQueue, #addon.wire
	oldTimer.callback()
	Equal(addon.questCompareResponseQueue, replacementQueue)
	Equal(#addon.wire, before)
	addon.isEnabled = false
	RunResponseTimer(addon)
	Equal(#addon.wire, before)
end)

QuestTogether:RegisterTest("quest comparison response memory has job and packet bounds", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 1)
	for index = 1, 4 do
		Equal(addon:HandleQuestCompareRequest({ requestId = tostring(index), targetName = "MyPlayer-Realm" }), true)
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "overflow", targetName = "MyPlayer-Realm" }), false)
	Equal(#addon.questCompareResponseQueue.jobs, 4)
	addon:ResetCommsState()
	SetComparisonEntries(addon, 40)
	for index = 1, 3 do
		Equal(addon:HandleQuestCompareRequest({ requestId = tostring(index), targetName = "MyPlayer-Realm" }), true)
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "fourth", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.questCompareResponseQueue.jobs, 4)
	Equal(addon.questCompareResponseQueue.jobs[4].entries, nil)
	Equal(addon.questCompareResponseQueue.packets <= 128, true)
	addon:ResetCommsState()
	SetComparisonEntries(addon, 101)
	Equal(addon:HandleQuestCompareRequest({ requestId = "large", targetName = "MyPlayer-Realm" }), false)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
end)

QuestTogether:RegisterTest("oversized mandatory wire identity is rejected rather than truncated", function()
	local addon = NewCommsFixture()
	local identity = string.rep("Длинное", 50) .. "-Realm"
	local event = Event("1/5 objectives")
	event.senderName = identity
	Equal(addon:SendAnnouncementWireEvent(event), false)
	local payload = addon:EncodePingResponsePayload({ requestId = "test", senderName = identity })
	Equal(addon:DecodePingResponsePayload(payload).senderName, identity)
	Equal(addon:SendWireMessageToAnnouncementRoutes("PONG|" .. payload), false)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("empty quest comparisons share the response packet cooldown", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 0)
	Equal(addon:HandleQuestCompareRequest({ requestId = "first", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 1)
	Equal(addon:HandleQuestCompareRequest({ requestId = "second", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 1)
	RunResponseTimer(addon)
	Equal(#addon.wire, 2)
	local _, payload = addon:DeserializeWireMessage(addon.wire[2][2])
	Equal(addon:DecodeQuestCompareDonePayload(payload).count, 0)
end)

QuestTogether:RegisterTest("paced successful comparisons finish within legacy ten second window", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 25)
	local startedAt, lastAttemptAt = addon.now, nil
	local completedAt, sentCount = nil, 0
	addon.API.SendAddonMessage = function(_, message, route)
		Equal(route, "PARTY")
		if lastAttemptAt then Equal(addon.now - lastAttemptAt >= 0.099, true) end
		lastAttemptAt = addon.now
		sentCount = sentCount + 1
		if message:find("^QCDN|") then
			local _, payload = addon:DeserializeWireMessage(message)
			Equal(addon:DecodeQuestCompareDonePayload(payload).count, 25)
			completedAt = addon.now
		end
		return 0
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "legacy", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	Equal(sentCount, 1)
	for _ = 1, 30 do if not RunResponseTimer(addon) then break end end
	Equal(sentCount, 26)
	Equal(completedAt ~= nil and completedAt - startedAt < 10, true)
end)

QuestTogether:RegisterTest("failed comparison sends back off longer than successful packet pacing", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 2)
	local attempts = 0
	addon.API.SendAddonMessage = function()
		attempts = attempts + 1
		return attempts == 2 and 3 or 0
	end
	Equal(addon:HandleQuestCompareRequest({ requestId = "backoff", targetName = "MyPlayer-Realm" }), true)
	local normalDelay = addon.delayed[1].seconds
	RunResponseTimer(addon)
	Equal(addon.delayed[1].seconds >= 1, true)
	Equal(addon.delayed[1].seconds > normalDelay, true)
	RunResponseTimer(addon)
	Equal(addon.delayed[1].seconds, normalDelay)
end)

QuestTogether:RegisterTest("queued group comparisons stop when requester leaves the roster", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 3)
	addon.partyMembers["Friend-Realm"] = {}
	Equal(addon:HandleQuestCompareRequest({ requestId = "group", requesterName = "Friend-Realm", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	Equal(#addon.wire, 1)
	addon.partyMembers = { ["NewFriend-Realm"] = {} }
	RunResponseTimer(addon)
	Equal(#addon.wire, 1)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
end)

QuestTogether:RegisterTest("queued channel comparisons resolve changed channel identifiers per packet", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 2)
	Equal(addon:HandleQuestCompareRequest({ requestId = "channel", targetName = "MyPlayer-Realm", replyDistribution = "CHANNEL" }), true)
	Equal(addon.wire[1][4], 7)
	addon.channelID = 9
	RunResponseTimer(addon)
	Equal(addon.wire[2][4], 9)
end)

QuestTogether:RegisterTest("queued group comparisons follow a still grouped requester into raid transport", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 2)
	addon.partyMembers["Friend-Realm"] = {}
	addon.API.IsInParty = function() return true end
	Equal(addon:HandleQuestCompareRequest({ requestId = "raid", requesterName = "Friend-Realm", targetName = "MyPlayer-Realm", replyDistribution = "PARTY" }), true)
	Equal(addon.wire[1][3], "PARTY")
	addon.API.IsInRaid = function() return true end
	RunResponseTimer(addon)
	Equal(addon.wire[2][3], "RAID")
end)

QuestTogether:RegisterTest("comparison snapshots wait for both quest count and every row before sending", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local phase = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return phase > 0 and 2 or nil end
	addon.API.GetQuestLogInfo = function(index)
		if index == 2 and phase < 2 then return nil end
		return { questID = index, title = "Quest " .. index, isComplete = false }
	end
	addon.GetQuestShareableStatusLabel = function() return "No" end
	Equal(addon:HandleQuestCompareRequest({ requestId = "loading", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 0)
	Equal(addon.questCompareResponseQueue.packets, 1)
	phase = 1
	RunResponseTimer(addon)
	Equal(#addon.wire, 0)
	phase = 2
	RunResponseTimer(addon)
	Equal(#addon.wire, 1)
	for _ = 1, 5 do if not RunResponseTimer(addon) then break end end
	Equal(#addon.wire, 3)
	local command, payload = addon:DeserializeWireMessage(addon.wire[3][2])
	Equal(command, "QCDN")
	Equal(addon:DecodeQuestCompareDonePayload(payload).count, 2)
	Equal(addon.questCompareResponseQueue.packets, 0)
end)

QuestTogether:RegisterTest("unavailable comparison count exhausts bounded snapshot retries without completion", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local reads = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() reads = reads + 1; return nil end
	Equal(addon:HandleQuestCompareRequest({ requestId = "unavailable", targetName = "MyPlayer-Realm" }), true)
	for _ = 1, 10 do if not RunResponseTimer(addon) then break end end
	Equal(reads, 5)
	Equal(#addon.wire, 0)
	Equal(#addon.delayed, 0)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(addon:GetCommsDiagnostics().failedComparisons, 1)
end)

QuestTogether:RegisterTest("missing comparison rows cannot become a certified partial quest log", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local missingReads = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 2 end
	addon.API.GetQuestLogInfo = function(index)
		if index == 2 then missingReads = missingReads + 1; return nil end
		return { questID = 123, title = "Readable quest" }
	end
	addon.GetQuestShareableStatusLabel = function() return "No" end
	Equal(addon:HandleQuestCompareRequest({ requestId = "partial", targetName = "MyPlayer-Realm" }), true)
	for _ = 1, 10 do if not RunResponseTimer(addon) then break end end
	Equal(missingReads, 5)
	Equal(#addon.wire, 0)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
end)

QuestTogether:RegisterTest("a readable empty quest log still completes a comparison", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 0 end
	Equal(addon:HandleQuestCompareRequest({ requestId = "empty", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 1)
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	Equal(command, "QCDN")
	Equal(addon:DecodeQuestCompareDonePayload(payload).count, 0)
end)

QuestTogether:RegisterTest("comparison snapshots defer restricted reads and reject changing counts", function()
	local addon = NewCommsFixture()
	local blocked, reads = true, 0
	addon.IsWorkBlocked = function() return blocked end
	addon.API.GetNumQuestLogEntries = function() reads = reads + 1; return reads == 1 and 0 or 1 end
	Equal(addon:BuildQuestCompareEntries(), nil)
	Equal(reads, 0)
	blocked = false
	Equal(addon:BuildQuestCompareEntries(), nil)
	Equal(reads, 2)
end)

QuestTogether:RegisterTest("self comparison reports an unavailable snapshot without claiming completion", function()
	local addon = NewCommsFixture()
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return nil end
	Equal(addon:RequestQuestCompare("MyPlayer-Realm"), false)
	Equal(#addon.printed, 1)
	Equal(addon.printed[1], "Quest comparison unavailable while the quest log is updating.")
end)

QuestTogether:RegisterTest("comparison snapshots wait for missing blank and inaccessible visible quest titles", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	local phase = 0
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 1 end
	addon.API.GetQuestLogInfo = function()
		local titles = { [1] = "   ", [2] = "inaccessible title", [3] = "Loaded quest" }
		return { questID = 123, title = titles[phase] }
	end
	addon.CanAccessValue = function(_, value) return value ~= "inaccessible title" end
	addon.GetQuestShareableStatusLabel = function() return "No" end
	Equal(addon:HandleQuestCompareRequest({ requestId = "title", targetName = "MyPlayer-Realm" }), true)
	Equal(#addon.wire, 0)
	for index = 1, 2 do
		phase = index
		RunResponseTimer(addon)
		Equal(#addon.wire, 0)
	end
	phase = 3
	RunResponseTimer(addon)
	Equal(#addon.wire, 1)
	local _, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	Equal(addon:DecodeQuestCompareEntryPayload(payload).questTitle, "Loaded quest")
	RunResponseTimer(addon)
	Equal(#addon.wire, 2)
end)

QuestTogether:RegisterTest("comparison snapshots can omit explicitly known header and hidden rows", function()
	local addon = NewCommsFixture()
	addon.IsWorkBlocked = function() return false end
	addon.API.GetNumQuestLogEntries = function() return 2 end
	addon.API.GetQuestLogInfo = function(index)
		if index == 1 then return { isHeader = true } end
		return { questID = 123, isHidden = true }
	end
	local entries = addon:BuildQuestCompareEntries()
	Equal(type(entries), "table")
	Equal(#entries, 0)
end)

local function NewSnapshotComparisonFixture()
	local addon = NewCommsFixture()
	local clock = addon:CreateTestClock(100)
	addon.restrictions = {}
	addon.questReads = 0
	addon.API.GetTime = function() return clock:GetTime() end
	addon.API.Delay = function(seconds, callback) clock:After(seconds, callback) end
	addon.API.InCombatLockdown = function() return addon.restrictions.combat == true end
	addon.API.IsWorldMapVisible = function() return addon.restrictions.map == true end
	addon.IsRuntimeRestrictionTypeActive = function(_, restrictionType)
		return addon.restrictions[restrictionType] == true
	end
	addon.API.GetNumQuestLogEntries = function()
		Equal(addon:IsWorkBlocked("quest_snapshot_refresh"), false)
		addon.questReads = addon.questReads + 1
		if addon.snapshotUnavailable then return nil end
		return 1
	end
	addon.API.GetQuestLogInfo = function()
		Equal(addon:IsWorkBlocked("quest_snapshot_refresh"), false)
		return { questID = 123, title = "Readable quest", isComplete = false }
	end
	addon.GetTrackedQuestStatusState = function() return { isOnQuest = true } end
	addon.API.IsPushableQuest = function() return nil end
	addon.partyMembers["Friend-Realm"] = {}
	return addon, clock
end

local function ReceiveSnapshotComparisonRequest(addon, requestId)
	local payload = addon:EncodeQuestCompareRequestPayload({
		requestId = requestId,
		requesterName = "Friend-Realm",
		targetName = "MyPlayer-Realm",
	})
	addon:OnCommReceived(addon.commPrefix, addon:SerializeWireMessage("QCMP", payload), "PARTY", "Friend-Realm")
end

QuestTogether:RegisterTest("queued comparisons recover after long combat map and encounter restrictions", function()
	for _, restriction in ipairs({ "combat", "map", "encounter" }) do
		local addon, clock = NewSnapshotComparisonFixture()
		addon.restrictions[restriction] = true
		ReceiveSnapshotComparisonRequest(addon, restriction)
		for _ = 1, 12 do clock:Advance(1) end
		Equal(#addon.questCompareResponseQueue.jobs, 1)
		Equal(addon.questCompareResponseQueue.jobs[1].snapshotAttempts, 0)
		Equal(addon.questCompareResponseQueue.packets, 1)
		Equal(addon.questReads, 0)
		Equal(#addon.wire, 0)
		addon.restrictions[restriction] = nil
		clock:Advance(1)
		Equal(#addon.wire, 1)
		local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
		Equal(command, "QCQE")
		Equal(addon:DecodeQuestCompareEntryPayload(payload).questId, "123")
		clock:Drain()
		Equal(#addon.wire, 2)
		command, payload = addon:DeserializeWireMessage(addon.wire[2][2])
		Equal(command, "QCDN")
		Equal(addon:DecodeQuestCompareDonePayload(payload).count, 1)
		Equal(#addon.questCompareResponseQueue.jobs, 0)
		Equal(addon.questCompareResponseQueue.packets, 0)
	end
end)

QuestTogether:RegisterTest("restriction deferrals preserve the bounded unavailable snapshot retry budget", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.snapshotUnavailable = true
	ReceiveSnapshotComparisonRequest(addon, "unavailable-around-combat")
	clock:Advance(1)
	clock:Advance(1)
	Equal(addon.questReads, 3)
	addon.restrictions.combat = true
	for _ = 1, 12 do clock:Advance(1) end
	Equal(addon.questReads, 3)
	Equal(addon.questCompareResponseQueue.jobs[1].snapshotAttempts, 3)
	addon.restrictions.combat = nil
	clock:Advance(1)
	Equal(#addon.questCompareResponseQueue.jobs, 1)
	clock:Advance(1)
	Equal(addon.questReads, 5)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(#addon.wire, 0)
	Equal(#clock.timers, 0)
end)

QuestTogether:RegisterTest("restricted comparison jobs still expire without reading or sending", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.restrictions.map = true
	ReceiveSnapshotComparisonRequest(addon, "expired-map")
	for _ = 1, 449 do clock:Advance(1) end
	Equal(#addon.questCompareResponseQueue.jobs, 1)
	clock:Advance(1)
	Equal(#addon.questCompareResponseQueue.jobs, 0)
	Equal(addon.questCompareResponseQueue.packets, 0)
	Equal(addon:GetCommsDiagnostics().failedComparisons, 1)
	addon.restrictions.map = nil
	clock:Advance(10)
	Equal(addon.questReads, 0)
	Equal(#addon.wire, 0)
	Equal(#clock.timers, 0)
end)

QuestTogether:RegisterTest("restricted comparison callbacks cannot revive canceled or disabled work", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.restrictions.combat = true
	ReceiveSnapshotComparisonRequest(addon, "old-combat")
	local oldCallback = clock.timers[1].callback
	addon:ResetCommsState()
	ReceiveSnapshotComparisonRequest(addon, "replacement-combat")
	local replacementQueue = addon.questCompareResponseQueue
	oldCallback()
	Equal(addon.questCompareResponseQueue, replacementQueue)
	Equal(#replacementQueue.jobs, 1)
	Equal(replacementQueue.scheduled, true)
	addon.isEnabled = false
	addon.restrictions.combat = nil
	clock:Advance(10)
	Equal(addon.questReads, 0)
	Equal(#addon.wire, 0)
	addon:ResetCommsState()
	addon.isEnabled = true
	clock:Advance(10)
	Equal(addon.questCompareResponseQueue, nil)
	Equal(#addon.wire, 0)
end)

QuestTogether:RegisterTest("comparison source wire and display preserve all three shareability states", function()
	for _, expected in ipairs({ "Yes", "No", "Unknown" }) do
		local addon = NewSnapshotComparisonFixture()
		addon.API.IsPushableQuest = function()
			if expected == "Yes" then return true end
			if expected == "No" then return false end
		end
		addon.GetQuestStatusLabel = function() return "Not Started" end
		addon.BuildChatLogQuestLabel = function(_, _, title) return title end
		Equal(addon:GetQuestShareableStatusLabel(123), expected)
		local entry = addon:BuildQuestCompareEntries()[1]
		Equal(addon:GetQuestCompareShareableToYouLabel(entry.isPushable), expected)
		Equal(addon:SendQuestCompareEntry("shareability", entry), true)
		local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
		Equal(command, "QCQE")
		local received = addon:DecodeQuestCompareEntryPayload(payload)
		Equal(received.questId, "123")
		Equal(received.classFile, "MAGE")
		Equal(addon:GetQuestCompareShareableToYouLabel(received.isPushable), expected)
		Equal(addon:BuildQuestCompareMessage("Friend-Realm", received),
			"Readable quest | Them: In Progress | You: Not Started | Shareable to You: " .. expected)
	end
end)

QuestTogether:RegisterTest("legacy comparison layouts retain known booleans and unknown shareability", function()
	local addon = NewCommsFixture()
	for _, hasClass in ipairs({ false, true }) do
		for _, token in ipairs({ "1", "0", "", "invalid" }) do
			local payload = "1,legacy,Friend-Realm," .. (hasClass and "MAGE," or "") .. "123,Old quest,0," .. token
			local entry = addon:DecodeQuestCompareEntryPayload(payload)
			Equal(entry.questId, "123")
			Equal(entry.classFile, hasClass and "MAGE" or "")
			Equal(entry.isComplete, false)
			Equal(addon:GetQuestCompareShareableToYouLabel(entry.isPushable),
				token == "1" and "Yes" or (token == "0" and "No" or "Unknown"))
		end
	end
end)

local function NewLocationReceiver()
	local addon = NewCommsFixture()
	addon.API.UnitFullName = function() return "Receiver", "Realm" end
	addon.API.UnitName = function() return "Receiver" end
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.db.profile.showProgressFor = "party_nearby"
	addon.db.profile.showChatLogs = true
	addon.db.profile.showChatBubbles = false
	addon.FindVisiblePlayerNameplateForSender = function() return nil end
	addon.FindNearbyPlayerUnitTokenForSender = function() return nil end
	function addon:IsRuntimeRestricted() return false end
	function addon:GetLocationPinMapWorldSize() return 4000, 2000 end
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
	local command, payload = addon:DeserializeWireMessage(addon.wire[1][2])
	local received = addon:DecodeAnnouncementPayload(payload)
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
		{ remoteID = 37, localID = 37, remoteName = "Same label", localName = "Same label", far = true, visible = false },
		{ remoteID = 37, localID = 37, remoteName = "Same label", localName = "Same label", differentWarMode = true, visible = false },
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
			return { mapID = case.localID, zoneName = case.localName, coordX = case.far and 90 or 50,
				coordY = 50, warMode = case.differentWarMode == true }
		end
		local event = sender:BuildLocalAnnouncementEvent("QUEST_PROGRESS", "Wolves: 1/8", 123)
		Equal(sender:SendAnnouncementWireEvent(event), true)
		receiver:OnCommReceived(receiver.commPrefix, sender.wire[1][2], "CHANNEL", "MyPlayer-Realm", 7, receiver.announcementChannelName)
		Equal(#receiver.printed, case.visible and 1 or 0)
	end
end)

QuestTogether:RegisterTest("announcement map extension preserves legacy layouts and rejects invalid IDs", function()
	local addon = NewCommsFixture()
	local function Payload(version, suffix)
		return tostring(version) .. ",QUEST_PROGRESS,Player-1-ID,MAGE,Friend-Realm,Wolves: 1/8,123,,,Zone,50,50,0,CHEER" .. suffix
	end
	for _, version in ipairs({ 1, 2, 3 }) do
		local legacy = addon:DecodeAnnouncementPayload(Payload(version, ""))
		Equal(legacy.mapID, "")
		Equal(legacy.zoneName, "Zone")
		Equal(legacy.emoteToken, "CHEER")
		Equal(addon:DecodeAnnouncementPayload(Payload(version, ",37")).mapID, "37")
	end
	for _, invalid in ipairs({ "0", "-1", "1.5", "nan", "inf", "garbage", "" }) do
		Equal(addon:DecodeAnnouncementPayload(Payload(3, "," .. invalid)).mapID, "")
	end
	local secret = setmetatable({}, { __tostring = function() error("secret map ID stringified") end })
	addon.CanAccessValue = function(_, value) return value ~= secret end
	local event = Event()
	event.mapID = secret
	Equal(addon:SanitizeAnnouncementEventData(event).mapID, "")
end)

QuestTogether:RegisterTest("announcement packet fitting retains numeric location when display labels are too large", function()
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
	local _, payload = sender:DeserializeWireMessage(wire)
	local received = sender:DecodeAnnouncementPayload(payload)
	Equal(received.zoneName, "")
	Equal(received.mapID, "2248")
	Equal(received.coordX, "50.0")
	Equal(received.coordY, "50.0")
	Equal(received.warMode, "0")
	receiver:OnCommReceived(receiver.commPrefix, wire, "CHANNEL", "MyPlayer-Realm", 7, receiver.announcementChannelName)
	Equal(#receiver.printed, 1)
end)

local function NewBubblePreviewFixture()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	addon.db.profile.showChatBubbles = true
	addon.db.profile.showChatLogs = false
	addon.partyMembers["Target-Realm"] = {}
	addon.API.UnitFullName = function(unit)
		return unit == "player" and "MyPlayer" or "Target", "Realm"
	end
	addon.API.UnitGUID = function(unit) return unit == "player" and "Player-self" or "Player-target" end
	addon.API.UnitExists = function(unit) return unit == "target" or unit == "nameplate1" or unit == "player" end
	addon.API.UnitIsPlayer = function() return true end
	addon.IsWorkBlocked = function() return false end
	local plate = { UnitFrame = { unit = "nameplate1" }, GetUnit = function() return "nameplate1" end }
	addon.ForEachVisibleNamePlate = function(_, callback) callback(plate) end
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
	addon.API.UnitExists = function(unit) return unit == "nameplate1" or unit == "player" end
	ok, name = addon:SendBubbleAnnouncementTest("Explicit player preview", "Target-Realm")
	Equal(ok, true)
	Equal(name, "Target-Realm")
	Equal(#addon.wire, 0)
	Equal(#addon.bubbles, 2)
end)

QuestTogether:RegisterTest("local bubble previews do not depend on transport and report suppression", function()
	local addon = NewBubblePreviewFixture()
	addon.SendAnnouncementWireEvent = function() error("a local preview must not use the network") end
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
	addon.Print = function(_, message) addon.messages[#addon.messages + 1] = message end
	addon.GetDebugController = function() return { HandleCommand = function() return false end } end
	addon.API.RegionalUniqueNamesEnabled = function() return regional end
	addon.API.ShouldDisplaySurname = function() return false end
	addon.API.UnitExists = function(unit)
		return unit == "player" or unit == "nameplate1" or unit == "nameplate2" or (hasTarget and unit == "target")
	end
	addon.API.UnitFullName = function(unit)
		if not regional then return unit == "player" and "MyPlayer" or "Target", "Realm" end
		if unit == "player" then return "MyPlayer", "Selfname" end
		return "Anakin", unit == "nameplate2" and "Elsewhere" or "Othername"
	end
	addon.API.UnitName = function(unit) return unit == "player" and "MyPlayer" or (regional and "Anakin" or "Target") end
	addon.API.UnitGUID = function(unit)
		return unit == "player" and "Player-self" or (unit == "nameplate2" and "Player-other" or "Player-target")
	end
	if regional then
		-- The other character with the same first name appears first, so a
		-- weakened first-name lookup would render on the wrong private frame.
		local firstPlate = addon.ForEachVisibleNamePlate
		local otherPlate = { UnitFrame = { unit = "nameplate2" }, GetUnit = function() return "nameplate2" end }
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

QuestTogether:RegisterTest("bubbletest slash keeps complete target text including quotes and player-like words", function()
	for _, regional in ipairs({ false, true }) do
		local addon = NewBubbleSlashFixture(regional, true)
		local text = '"Anakin Othername" Hello THERE'
		addon:HandleSlashCommand("preview ANNOUNCEMENT " .. text)
		Equal(#addon.bubbles, 1)
		Equal(addon.bubbles[1], text)
		Equal(#addon.wire, 0)
	end
end)

QuestTogether:RegisterTest("bubbletest slash rejects malformed names empty text and ambiguous first names", function()
	for _, regional in ipairs({ false, true }) do
		for _, arguments in ipairs({ '"" hello', '"   " hello', '"Anakin Othername hello', '"Anakin Othername"hello', '"Anakin Othername"', '"Anakin Othername"   ', "Target-Realm" }) do
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

QuestTogether:RegisterTest("rapid party comparison refreshes supersede obsolete peer responses and complete the newest session", function()
	local peer, requester = NewCommsFixture(), NewCommsFixture()
	local clock = QuestTogether:CreateTestClock(100)
	for _, addon in ipairs({ peer, requester }) do
		addon.API.GetTime = function() return clock:GetTime() end
		addon.API.IsInParty = function() return true end
		addon.API.Delay = function(delay, callback) clock:After(delay, callback) end
		addon.runtime.deferredWorkState = { entries = {}, generations = {} }
		addon.IsWorkBlocked = function() return false end
		addon.QueuePartyQuestCompareRender = function() end
		addon.partyQuestCompareSession = false
	end
	peer.API.UnitFullName = function() return "Friend", "Realm" end
	peer.API.UnitName = function() return "Friend" end
	peer.GetPlayerClassFile = function() return "" end -- Classless peers still reply.
	peer.partyMembers["MyPlayer-Realm"] = {}
	requester.partyMembers["Friend-Realm"] = {}
	requester.partyMemberOrder = { "Friend-Realm" }
	SetComparisonEntries(peer, 35)
	SetComparisonEntries(requester, 0)
	local timers = {}
	peer.API.Delay = function(delay, callback)
		timers[#timers + 1] = callback
		clock:After(delay, callback)
	end
	local ids = {}
	for index = 1, 4 do
		Equal(requester:RefreshPartyQuestCompare(), true)
		ids[index] = requester.partyQuestCompareSession.byName["Friend-Realm"].requestId
		peer:OnCommReceived(peer.commPrefix, requester.wire[#requester.wire][2], "PARTY", "MyPlayer-Realm")
	end
	local queue = peer.questCompareResponseQueue
	Equal(#queue.jobs, 1)
	Equal(queue.jobs[1].requestId, ids[4])
	Equal(queue.packets, 36)
	Equal(#peer.wire, 1) -- The first response packet was already sent before Refresh.
	Equal(#timers, 1) -- Supersession retains the existing cooldown callback.
	for index = 1, 3 do Equal(requester.pendingQuestCompareRequests[ids[index]], nil) end
	requester:OnCommReceived(requester.commPrefix, peer.wire[1][2], "PARTY", "Friend-Realm")
	local member = requester.partyQuestCompareSession.byName["Friend-Realm"]
	Equal(next(member.entries), nil) -- Delayed old packets cannot enter the new session.
	Equal(member.state, "loading")
	local delivered = 1
	for _ = 1, 40 do
		clock:Advance(0.1) -- The first tick is the callback created for the old response.
		while delivered < #peer.wire do
			delivered = delivered + 1
			local packet = peer.wire[delivered]
			local command, payload = peer:DeserializeWireMessage(packet[2])
			local data = command == "QCQE" and peer:DecodeQuestCompareEntryPayload(payload)
				or peer:DecodeQuestCompareDonePayload(payload)
			Equal(data.requestId, ids[4])
			Equal(packet[3], "PARTY")
			requester:OnCommReceived(requester.commPrefix, packet[2], packet[3], "Friend-Realm")
		end
	end
	Equal(member.state, "ready")
	Equal(member.supportsShareRequests, true)
	Equal(requester.pendingQuestCompareRequests[ids[4]], nil)
	local count = 0
	for _ in pairs(member.entries) do count = count + 1 end
	Equal(count, 35)
	Equal(#peer.wire, 37) -- One unavoidable old entry, then all 35 new entries and done.
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)
	clock:Advance(181)
	Equal(member.state, "ready")
	Equal(#peer.wire, 37)
end)

QuestTogether:RegisterTest("comparison supersession uses transport identity and preserves unrelated queue jobs and bounds", function()
	local addon = NewCommsFixture()
	InstallResponseClock(addon)
	SetComparisonEntries(addon, 1)
	local function Receive(id, transportSender, claimedSender, route)
		addon.partyMembers[transportSender] = {}
		local wire = addon:SerializeWireMessage("QCMP", addon:EncodeQuestCompareRequestPayload({
			requestId = id, requesterName = claimedSender or transportSender, targetName = "MyPlayer-Realm",
		}))
		addon:OnCommReceived(addon.commPrefix, wire, route or "PARTY", transportSender)
	end
	Receive("a-old", "Alpha-Realm")
	Receive("b", "Beta-Realm", "Alpha-Realm") -- Payload cannot cancel Alpha's authenticated job.
	Receive("c", "Gamma-Realm")
	Receive("d", "Delta-Realm")
	local queue = addon.questCompareResponseQueue
	Equal(#queue.jobs, 4)
	Equal(queue.jobs[1].requestId, "a-old")
	Equal(queue.jobs[2].requesterName, "Beta-Realm")
	local beta, gamma, delta = queue.jobs[2], queue.jobs[3], queue.jobs[4]
	Receive("a-new", "Alpha-Realm", "Beta-Realm", "RAID")
	Equal(#queue.jobs, 4)
	Equal(queue.jobs[1], beta)
	Equal(queue.jobs[2], gamma)
	Equal(queue.jobs[3], delta)
	Equal(queue.jobs[4].requestId, "a-new")
	Equal(queue.jobs[4].routes[1].distribution, "RAID")
	Equal(queue.packets, 8)
	local latest = queue.jobs[4]
	Receive("a-new", "Alpha-Realm", "Beta-Realm", "PARTY") -- Duplicate route delivery keeps the same job.
	Equal(queue.jobs[4], latest)
	Receive("overflow", "Epsilon-Realm")
	Equal(#queue.jobs, 4)
	Equal(queue.packets, 8)
	for _ = 1, 12 do if not RunResponseTimer(addon) then break end end
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)

	addon:ResetCommsState()
	SetComparisonEntries(addon, 60)
	Receive("large-a", "Alpha-Realm")
	Receive("large-b", "Beta-Realm")
	queue = addon.questCompareResponseQueue
	local old, other = queue.jobs[1], queue.jobs[2]
	Equal(queue.packets, 121) -- One Alpha entry has already left the queue.
	SetComparisonEntries(addon, 100)
	Receive("too-large-replacement", "Alpha-Realm")
	Equal(queue.jobs[1], other)
	Equal(queue.jobs[2].requestId, "too-large-replacement")
	Equal(queue.jobs[2].entries, nil)
	Equal(queue.packets, 62)
	SetComparisonEntries(addon, 1)
	Receive("small-replacement", "Alpha-Realm")
	Equal(queue.jobs[1], other)
	Equal(queue.jobs[2].requestId, "small-replacement")
	Equal(queue.packets, 63)
	for _ = 1, 70 do if not RunResponseTimer(addon) then break end end
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)
end)

QuestTogether:RegisterTest("restricted comparison refreshes replace pending snapshots without extra timers or stale replies", function()
	local addon, clock = NewSnapshotComparisonFixture()
	addon.restrictions.combat = true
	ReceiveSnapshotComparisonRequest(addon, "restricted-old")
	local oldTimer = clock.timers[1].callback
	clock:Advance(1)
	ReceiveSnapshotComparisonRequest(addon, "restricted-new")
	local queue = addon.questCompareResponseQueue
	Equal(#queue.jobs, 1)
	Equal(queue.jobs[1].requestId, "restricted-new")
	Equal(queue.jobs[1].snapshotAttempts, 0)
	Equal(queue.packets, 1)
	Equal(#clock.timers, 1)
	Equal(addon.questReads, 0)
	addon.restrictions.combat = nil
	clock:Advance(1)
	clock:Advance(0.1)
	Equal(#addon.wire, 2)
	for _, packet in ipairs(addon.wire) do
		local command, payload = addon:DeserializeWireMessage(packet[2])
		local data = command == "QCQE" and addon:DecodeQuestCompareEntryPayload(payload)
			or addon:DecodeQuestCompareDonePayload(payload)
		Equal(data.requestId, "restricted-new")
	end
	Equal(#queue.jobs, 0)
	Equal(queue.packets, 0)
	addon:ResetCommsState()
	oldTimer()
	Equal(addon.questCompareResponseQueue, nil)
	Equal(#addon.wire, 2)
end)

local function PartyChatFixture()
	local addon = NewCommsFixture()
	addon.suppressLocalAnnouncementDisplayDuringTests = false
	addon.qtPlayerPresenceState = { peers = {} }
	function addon:IsRuntimeRestrictionTypeActive() return self.chatRestricted == true end
	addon.chatMessages, addon.members = {}, { party1 = "Friend-Realm" }
	addon.partyOption, addon.eventOption = true, true
	addon.db = { profile = { hidePartyChatReminder = true } }
	function addon:GetOption(key)
		if key == "hidePartyChatReminder" then return self.db.profile.hidePartyChatReminder end
		if key == "announceToNonQTParty" then return self.partyOption end
		if key == "announceProgress" then return self.eventOption end
		return false
	end
	function addon:GetUnitFullName(unit) return self.members[unit] end
	addon.API.UnitExists = function(unit) return addon.members[unit] ~= nil end
	addon.API.IsInParty = function() return true end
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
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:RenderPartyChatReminder(request) self.rendered = request end
	function a:RefreshOptionsWindow() end
	function a:SetOption(key, value)
		if key == "announceToNonQTParty" then self.partyOption = value
		else self.db.profile[key] = value end
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
		a:UpdatePartyChatReminder(); a.now = 110; a:UpdatePartyChatReminder()
		Equal(a:AcknowledgePartyChatReminder(a.rendered, true, off), true)
		Equal(a.db.profile.hidePartyChatReminder, true)
		Equal(a.partyOption, not off)
		a:ResetPartyChatReminder()
		Equal(a:UpdatePartyChatReminder(), not off)
	end
	for _, stale in ipairs({ "profile", "leave", "known", "off", "disabled", "restricted", "unreadable" }) do
		local a = ReminderFixture()
		a:UpdatePartyChatReminder(); a.now = 110; a:UpdatePartyChatReminder()
		local old = a.rendered
		if stale == "profile" then a.db.profile = { hidePartyChatReminder = false }
		elseif stale == "leave" then a.members = {}
		elseif stale == "known" then a:RecordQTPlayerPresence("Friend-Realm", true)
		elseif stale == "off" then a.partyOption = false
		elseif stale == "disabled" then a.isEnabled = false
		elseif stale == "restricted" then a.blocked = true
		else a.API.UnitExists = function() return nil end end
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
	a:UpdatePartyChatReminder(); a.now = 115; a:UpdatePartyChatReminder()
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
	for _, scenario in ipairs({ "off", "eventOff", "disabled", "restricted", "solo", "raid", "unknownRaid", "unknownMember", "unknownName", "tests" }) do
		local a = PartyChatFixture()
		if scenario == "off" then a.partyOption = false
		elseif scenario == "eventOff" then a.eventOption = false
		elseif scenario == "disabled" then a.isEnabled = false
		elseif scenario == "restricted" then a.chatRestricted = true
		elseif scenario == "solo" then a.API.IsInParty = function() return false end
		elseif scenario == "raid" then a.API.IsInRaid = function() return true end
		elseif scenario == "unknownRaid" then a.API.IsInRaid = function() error("unavailable") end
		elseif scenario == "unknownMember" then a.API.UnitExists = function() return nil end
		elseif scenario == "unknownName" then a.GetUnitFullName = function() return nil end
		else a.suppressLocalAnnouncementDisplayDuringTests = true end
		Equal(a:AnnounceToNonQTParty(event), false)
		Equal(#a.chatMessages, 0)
	end
	local a = PartyChatFixture()
	a.API.IsInInstanceGroup = function() return true end
	Equal(a:AnnounceToNonQTParty(event), true)
	Equal(a.chatMessages[1][2], "INSTANCE_CHAT")
end)

QuestTogether:RegisterTest("party announcements contain bounded plain text and do not retry failures", function()
	local a = PartyChatFixture()
	Equal(a:AnnounceToNonQTParty({ eventType = "QUEST_PROGRESS", text = "|cffffffff|Hquest:1|h[Quest]|h|r\nDone |Ticon:16|t" }), true)
	Equal(a.chatMessages[1][1], "[QT] [Quest] Done")
	Equal(a:AnnounceToNonQTParty({ eventType = "QUEST_PROGRESS", text = string.rep("é", 150) }), true)
	assert(#a.chatMessages[2][1] <= 255)
	Equal(a.chatMessages[2][1], "[QT] " .. string.rep("é", 125))
	local attempts = 0
	a.API.SendPartyChatMessage = function() attempts = attempts + 1; error("blocked") end
	Equal(a:AnnounceToNonQTParty({ eventType = "QUEST_PROGRESS", text = "Progress" }), false)
	Equal(attempts, 1)
	Equal(#a.delayed, 0)
end)

QuestTogether:RegisterTest("local publication sends one party announcement independent of addon transport", function()
	local a = PartyChatFixture()
	function a:BuildLocalAnnouncementEvent(eventType, text) return { eventType = eventType, text = text } end
	function a:SendAnnouncementWireEvent() return false end
	function a:HandleAnnouncementEvent() end
	Equal(a:PublishAnnouncementEvent("QUEST_PROGRESS", "Progress"), true)
	Equal(#a.chatMessages, 1)
	-- Incoming events use HandleAnnouncementEvent, never the local publisher.
	Equal(a:AnnounceToNonQTParty({ eventType = "PLAYER_LEVEL_UP", text = "Level 10" }), true)
end)

QuestTogether:RegisterTest("major channel transition sends only current and rejects retired channel traffic", function()
	local addon = NewCommsFixture()
	local wire = addon:SerializeWireMessage("ANN", addon:EncodeAnnouncementPayload(Event()))
	Equal(addon:SendWireMessageToAnnouncementRoutes(wire), true)
	Equal(#addon.wire, 1)
	local received = 0
	function addon:HandleAnnouncementEvent() received = received + 1 end
	function addon:RecordQTPlayerPresence() end
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, "QuestTogetherAnnounce1")
	Equal(received, 0)
	addon:OnCommReceived(addon.commPrefix, wire, "CHANNEL", "Friend-Realm", 7, addon.announcementChannelName)
	Equal(received, 1)
	Equal(addon:IsAnnouncementChannelEvent("CHANNEL", 7, "General"), false)
	Equal(addon:AnnouncementChannelChatFilter(nil, nil, "hi", "Friend", "", "2. QuestTogetherAnnounce1"), false)
end)

QuestTogether:RegisterTest("current channel resolves fresh IDs after joins and fails without a route", function()
	local addon = NewCommsFixture()
	local available, joined = {}, {}
	addon.API.GetChannelName = function(name) return available[name] end
	addon.API.JoinPermanentChannel = function(name)
		joined[#joined + 1] = name
		if not addon.fail then available[name] = 11 end
	end
	function addon:RegisterAnnouncementChannelChatFilters() end
	function addon:HideAnnouncementChannelFromChatWindows() end
	addon.fail = true
	Equal(addon:SendWireMessageToAnnouncementRoutes("PING|test"), false)
	Equal(#joined, 1)
	Equal(#addon.wire, 0)
	addon.fail = false
	Equal(addon:SendWireMessageToAnnouncementRoutes("QCDN|test", nil, { { distribution = "CHANNEL", requiresChannelJoin = true } }), true)
	Equal(#addon.wire, 1)
	Equal(addon.wire[1][4], 11)
end)

QuestTogether:RegisterTest("QT channels sort last in human chat then regional order without disturbing other channel order", function()
	local addon = NewCommsFixture()
	addon:InitializeGeographicComms()
	addon.geographicCommsState.subscriptions.QuestTogetherZ12 = true
	local names = { "QuestTogetherZ12", "General", addon.announcementChannelName, "Trade", "MyFriends" }
	local swaps = 0
	function addon:IsRuntimeRestricted() return self.blocked == true end
	function addon:IsRuntimeRestrictionTypeActive() return false end
	addon.API.GetChatChannelList = function()
		local list = {}
		for i, name in ipairs(names) do
			list[#list + 1], list[#list + 2], list[#list + 3] = i, name, false
		end
		return list
	end
	addon.API.GetChannelName = function(name)
		for i, value in ipairs(names) do if name == value then return i end end
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
end)

QuestTogether:RegisterTest("QT slash chat sends once to fresh primary channel ID without local echo or retry", function()
	local addon = NewCommsFixture()
	function addon:IsRuntimeRestrictionTypeActive() return self.blocked == true end
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
end)

QuestTogether:RegisterTest("channel ordering rejects inaccessible metadata and stops on failed swaps", function()
	local addon = NewCommsFixture()
	function addon:IsRuntimeRestricted() return false end
	function addon:IsRuntimeRestrictionTypeActive() return false end
	local secret = setmetatable({}, { __tostring = function() error("unreadable channel name") end })
	function addon:CanAccessValue(value) return value ~= secret end
	local swaps = 0
	addon.API.GetChatChannelList = function() return { 1, secret, false, 2, "General", false } end
	addon.API.SwapChatChannelIndices = function() swaps = swaps + 1; return false end
	Equal(addon:MoveAnnouncementChannelsToEnd(), false)
	Equal(swaps, 0)
	addon.API.GetChatChannelList = function() return { 1, addon.announcementChannelName, false, 2, "General", false } end
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
	addon.API.IsWarModeFeatureEnabled = function() return false end
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
	addon.GetPlayerAnnouncementLocationInfo = function() return { mapID = 37, coordX = 0, coordY = 0 } end
	remote.coordX, remote.coordY = 100, 100
	addon.db.profile.nearbyAnnouncementRange = 100
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), true)
	remote.mapID = 38 -- Keep the requested zone-boundary rule even at Entire Zone.
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	remote.mapID, remote.coordX = 37, 101
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
	addon.GetLocationPinMapWorldSize = function() return nil end
	remote.coordX, remote.coordY = 50, 50
	Equal(addon:IsAnnouncementSenderNearbyByLocation(remote), false)
end)

QuestTogether:RegisterTest("nearby percentage slider validates and refreshes profiles without writing on initialization", function()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	local writes = 0
	function addon:SetOption(key, value)
		Equal(key, "nearbyAnnouncementRange")
		self.db.profile[key] = value
		writes = writes + 1
		return true
	end
	local label = { SetText = function(self, text) self.text = text end }
	local slider = { scripts = {} }
	function slider:SetScript(key, callback) self.scripts[key] = callback end
	function slider:SetValue(value)
		self.value = value
		if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
	end
	addon:ConfigureNearbyRangeSlider(slider, label)
	Equal(writes, 0)
	Equal(slider.value, 25)
	Equal(label.text:find("25%", 1, true) ~= nil, true)
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
end)

QuestTogether:RegisterTest("Global QT chat does not need locations while Zone Only requires fresh matching zones", function()
	local addon = NewCommsFixture()
	addon.db = { profile = addon:DeepCopy(addon.DEFAULTS.profile) }
	function addon:IsRuntimeRestricted() return false end
	function addon:IsRuntimeRestrictionTypeActive() return false end
	function addon:FindVisiblePlayerNameplateForSender() return nil end
	addon.API.GetBestMapForUnit = function() return 37 end
	addon.db.profile.showChatBubbles = false
	local function Receive()
		return addon:CHAT_MSG_CHANNEL("CHAT_MSG_CHANNEL", "hello", "Friend-Realm", "", addon.announcementChannelName)
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
	addon.API.GetBestMapForUnit = function() error("Global must not read location") end
	Equal(Receive(), true)
end)

QuestTogether:RegisterTest("nearby range and QT chat scope persist valid profile options and reject invalid choices", function()
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
end)

QuestTogether:RegisterTest("partner search announces only explicit off to on transitions", function()
	local addon = NewLocationReceiver()
	local announcements, broadcasts = 0, 0
	function addon:AnnounceQuestPartnerSearch() announcements = announcements + 1 end
	function addon:BroadcastQuestPartnerStatus() broadcasts = broadcasts + 1 end
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

QuestTogether:RegisterTest("partner announcement cooldown leaves status changes immediate and never queues retries", function()
	local addon = NewLocationReceiver()
	local announcements, statuses, glows = 0, 0, 0
	function addon:SendAnnouncementWireEvent()
		announcements = announcements + 1
		return not self.failSend
	end
	function addon:BroadcastQuestPartnerStatus() statuses = statuses + 1 end
	function addon:RefreshMinimapPartnerGlow() glows = glows + 1 end
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
end)

QuestTogether:RegisterTest("partner search crosses the zone once through normal transport without changing quest range", function()
	local sender, receiver = NewLocationReceiver(), NewLocationReceiver()
	sender.suppressLocalAnnouncementDisplayDuringTests = false
	sender.API.UnitFullName = function() return "Friend", "Realm" end
	sender.API.UnitName = function() return "Friend" end
	sender.db.profile.lookingForQuestPartners = true
	local localMapID, remoteMapID, localWarMode = 37, 37, false
	function sender:GetPlayerAnnouncementLocationInfo()
		return { mapID = remoteMapID, zoneName = "Elwynn", coordX = 99, coordY = 99, warMode = false }
	end
	function receiver:GetPlayerAnnouncementLocationInfo()
		return { mapID = localMapID, zoneName = "Elwynn", coordX = 1, coordY = 1, warMode = localWarMode }
	end
	receiver.db.profile.nearbyAnnouncementRange = 5
	function receiver:GetLocationPinMapWorldSize() error("LFQP must not need map dimensions") end
	function sender:AnnounceToNonQTParty() error("partner search is a QT announcement") end
	function receiver:RecordQTPlayerPresence() end
	sender.db.profile.announceQuestPartners = false
	Equal(sender:AnnounceQuestPartnerSearch(), false)
	Equal(#sender.wire, 0)
	sender.db.profile.announceQuestPartners = true
	Equal(sender:AnnounceQuestPartnerSearch(), true)
	assert(#sender.printed == 1, "local partner search should print once")
	local wire = sender.wire[1][2]
	local command, payload = sender:DeserializeWireMessage(wire)
	Equal(command, "ANN")
	local event = sender:DecodeAnnouncementPayload(payload)
	Equal(event.eventType, "LOOKING_FOR_QUEST_PARTNERS")
	Equal(event.text, QuestTogether.Translate("Looking for questing partners") .. " :)")
	Equal(event.iconAsset, "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
	local iconTag = receiver:GetAnnouncementIconChatTag(event.eventType, 14, event.iconAsset, event.iconKind)
	assert(iconTag:find("QuestTogetherPartnerIcon", 1, true), "LFQP uses local glow artwork with a legacy-safe wire icon")
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
	function receiver:IsIgnoredPlayerName() return true end
	Equal(receiver:HandleAnnouncementEvent(event, false), false)
	Equal(#receiver.printed, 1)
	local count = #sender.wire
	sender.isEnabled = false
	Equal(sender:AnnounceQuestPartnerSearch(), false)
	sender.isEnabled = true
	function sender:IsRuntimeRestricted() return true end
	Equal(sender:AnnounceQuestPartnerSearch(), false)
	function sender:IsRuntimeRestricted() return false end
	sender.db.profile.lookingForQuestPartners = false
	Equal(sender:AnnounceQuestPartnerSearch(), false)
	Equal(#sender.wire, count)
	-- Sharing disabled still redacts location; the new event cannot bypass it.
	sender.now = sender.now + 30
	sender.db.profile.lookingForQuestPartners = true
	sender.db.profile.sharePlayerLocation = false
	Equal(sender:AnnounceQuestPartnerSearch(), true)
	local _, privatePayload = sender:DeserializeWireMessage(sender.wire[#sender.wire][2])
	local privateEvent = sender:DecodeAnnouncementPayload(privatePayload)
	Equal(privateEvent.mapID, "")
	Equal(privateEvent.coordX, "")
end)

QuestTogether:RegisterTest("ping localizes available identity and zone while preserving sender fallback", function()
	local a = NewCommsFixture()
	function a:IsRuntimeRestricted() return self.blocked == true end
	a.API.GetLocalizedClassName = function(id) if id == "MAGE" then return "Local Mage" end end
	a.API.GetMapInfo = function(id) if id == 37 then return { name = "Local Forest" } end end
	a.API.GetLocalizedRaceName = function(id) if id == 3 then return "Local Dwarf" end end
	a.nearbyStreamState = { capabilities = { ["Remote-Realm"] = { receivedAt = a.now, raceID = 3 } } }
	local pong = { senderName = "Remote-Realm", className = "Magier", classFile = "MAGE", raceName = "Zwerg", zoneName = "Wald", mapID = 37 }
	local text = a:BuildPingResponseMessage(pong)
	assert(text:find("Local Mage", 1, true) and text:find("Local Forest", 1, true) and text:find("Local Dwarf", 1, true))
	assert(not text:find("Magier", 1, true) and not text:find("Zwerg", 1, true) and not text:find("Wald", 1, true))
	a.API.GetLocalizedClassName, a.API.GetMapInfo, a.API.GetLocalizedRaceName = function() end, function() end, function() end
	text = a:BuildPingResponseMessage(pong)
	assert(text:find("Magier", 1, true) and text:find("Zwerg", 1, true) and text:find("Wald", 1, true))
	a.blocked = true
	a.API.GetLocalizedClassName, a.API.GetMapInfo = function() error("restricted lookup") end, function() error("restricted lookup") end
	text = a:BuildPingResponseMessage(pong)
	assert(text:find("Magier", 1, true) and text:find("Wald", 1, true))
end)

QuestTogether:RegisterTest("compare completion matches native tracker and survives wire encoding", function()
	for _, native in ipairs({ true, false }) do
		local addon = NewSnapshotComparisonFixture()
		function addon:GetQuestShareableStatusLabel() return "Yes" end
		addon.API.GetQuestLogInfo = function() return { questID = 123, title = "Delivery quest", isComplete = not native } end
		addon.API.IsQuestComplete = function(id) Equal(id, 123); return native end
		local entry = addon:BuildQuestCompareEntries()[1]
		Equal(entry.isComplete, native)
		assert(addon:SendQuestCompareEntry("native-completion", entry))
		local _, payload = addon:DeserializeWireMessage(addon.wire[1][2])
		Equal(addon:DecodeQuestCompareEntryPayload(payload).isComplete, native)
	end
end)
QuestTogether:RegisterTest("compare completion falls back safely when native data cannot be read", function()
	for _, value in ipairs({ "missing", "nil", "invalid", "throws", "inaccessible" }) do
		local addon = NewSnapshotComparisonFixture()
		function addon:GetQuestShareableStatusLabel() return "Yes" end
		addon.API.GetQuestLogInfo = function() return { questID = 123, title = "Ready quest", isComplete = true } end
		local unreadable = {}
		function addon:CanAccessValue(v) return v ~= unreadable end
		if value ~= "missing" then addon.API.IsQuestComplete = function()
			if value == "throws" then error("unavailable") end
			if value == "invalid" then return "false" end
			if value == "inaccessible" then return unreadable end
		end end
		Equal(addon:BuildQuestCompareEntries()[1].isComplete, true)
		function addon:IsWorkBlocked() return true end
		addon.API.IsQuestComplete = function() error("restricted native read") end
		Equal(addon:BuildQuestCompareEntries(), nil)
	end
end)

QuestTogether:RegisterTest("expired pong assemblies release active capacity independently from failed sender tombstones",function()
	local a=NewCommsFixture()
	a.pendingPingRequests.paged={startedAt=a.now,expiresAt=a.now+300,responders={}}
	for index=1,64 do assert(a:HandlePongPage("1,paged,1,2,fragment","Peer"..index.."-Realm")) end
	a.now=a.now+121
	assert(a:HandlePongPage("1,paged,1,2,new","Fresh-Realm"))
	Equal(a:HandlePongPage("1,paged,2,2,old","Peer1-Realm"),false)
	local pending=a.pendingPingRequests.paged
	local count=0;for _ in pairs(pending.pages) do count=count+1 end
	Equal(count,1)
	assert(#pending.failedPageOrder<=64)
end)

QuestTogether:RegisterTest("snapshot identity negotiates without changing legacy comparison layouts or packet bounds", function()
	local a=NewCommsFixture()
	local token="1700000000-100000-123456789-1"
	local request={requestId="comparison",requesterName="Me-Realm",targetName="Peer-Realm",supportsSnapshotIdentity=true}
	Equal(a:DecodeQuestCompareRequestPayload(a:EncodeQuestCompareRequestPayload(request)).supportsSnapshotIdentity,true)
	request.supportsSnapshotIdentity=nil
	Equal(a:EncodeQuestCompareRequestPayload(request),"1,comparison,Me-Realm,Peer-Realm")
	local entry={requestId="comparison",senderName="Peer-Realm",classFile="MAGE",questId="1",questTitle=string.rep("é",200),snapshotId=token}
	local payload=a:EncodeQuestCompareEntryPayload(entry)
	assert(#payload+5<=255)
	local decoded=assert(a:DecodeQuestCompareEntryPayload(payload))
	Equal(decoded.snapshotId,token);Equal(#decoded.questTitle%2,0)
	local row={questId=1,objectiveIndex=1,text=string.rep("é",200),kind="monster",current=1,required=5,finished=false}
	payload=a:EncodeQuestCompareObjectivePayload("comparison",row,token)
	assert(#payload+5<=255)
	decoded=assert(a:DecodeQuestCompareObjectivePayload(payload))
	Equal(decoded.snapshotId,token);Equal(#decoded.text%2,0)
	payload=a:EncodeQuestCompareObjectivePayload("comparison",row)
	Equal(a:DecodeQuestCompareObjectivePayload(payload).snapshotId,nil)
	local done={requestId="comparison",senderName="Peer-Realm",classFile="MAGE",count=1,supportsObjectives=true,snapshotId=token}
	Equal(a:DecodeQuestCompareDonePayload(a:EncodeQuestCompareDonePayload(done)).snapshotId,token)
	for _,invalid in ipairs({"bad!",string.rep("1",65)}) do
		entry.snapshotId=invalid;done.snapshotId=invalid
		Equal(a:DecodeQuestCompareEntryPayload(a:EncodeQuestCompareEntryPayload(entry)),nil)
		Equal(a:DecodeQuestCompareDonePayload(a:EncodeQuestCompareDonePayload(done)),nil)
		Equal(a:DecodeQuestCompareObjectivePayload(a:EncodeQuestCompareObjectivePayload("comparison",row,invalid)),nil)
	end
end)

QuestTogether:RegisterTest("large diagnostic replies finish through the real queue with concurrent ordinary traffic", function()
	local dev, peer = DeveloperFixture(), BusyDiagnosticFixture()
	local report = string.rep("%,|\n", 8192)
	function peer:BuildDeveloperDiagnosticSnapshot() return report end
	peer:InitializeGeographicComms()
	local nativeSend = peer.API.SendAddonMessage
	local pageCount = 0
	peer.API.SendAddonMessage = function(prefix, wire, distribution, target)
		assert(#wire <= 255)
		local result = nativeSend(prefix, wire, distribution, target)
		if wire:match("^PONP|2,") then
			pageCount = pageCount + 1
			Equal(distribution, "WHISPER"); Equal(target, dev.name)
			dev:OnCommReceived(prefix, wire, distribution, peer.name)
		end
		return result
	end
	local ok, id = dev:SendPingRequest(peer.name, true)
	Equal(ok, true)
	local pending = dev.pendingPingRequests[id]
	peer:OnCommReceived(peer.commPrefix, dev.wire[1][2], "WHISPER", dev.name)
	-- Half a message per second of normal traffic leaves the bulk stream
	-- roughly 1.5 messages/second under the production shared token budget.
	local background = "ANN|" .. peer:EncodeAnnouncementPayload(Event("1/5 Things"))
	for step = 1, 2500 do
		dev.clock:Advance(0.2)
		peer.clock:Advance(0.2)
		if step % 10 == 0 then
			assert(peer:QueueGeographicWire(background, "concurrent announcement", {
				distribution = "WHISPER", target = dev.name,
			}))
		end
		peer:DrainGeographicQueue()
		if dev.report then break end
	end
	assert(pageCount > 450)
	Equal(dev.report, report)
	assert(dev.API.GetTime() - pending.startedAt > 300, "exercise the extended request timer")
	Equal(dev.pendingPingRequests[id], pending)
	Equal(pending.remoteReplies, 1)
	Equal(pending.expiresAt, pending.startedAt + 600)
	Equal(#peer.pingPageQueue.jobs, 0)
end)

QuestTogether:RegisterTest("large diagnostic job expiry and consent cancellation fence queued pages", function()
	for _, revoke in ipairs({ false, true }) do
		local peer = DeveloperFixture("Friend-Realm")
		peer:InitializeGeographicComms()
		peer:GetTransportState().blockedUntil = peer.API.GetTime() + 600
		assert(peer:SendPagedPong("dev-1791300100-1234-1", string.rep("x", 98000), {
			{ distribution = "WHISPER", target = "Dev-Realm" },
		}, true, 2))
		Equal(#peer.pingPageQueue.jobs, 1)
		Equal(#peer:GetTransportState().queue, 1)
		Equal(peer.pingPageQueue.jobs[1].expiresAt - peer.pingPageQueue.jobs[1].createdAt, 540)
		if revoke then peer:SetOption("shareDeveloperDiagnostics", false)
		else peer.clock:Advance(541) end
		peer:DrainGeographicQueue()
		Equal(#peer.pingPageQueue.jobs, 0)
		Equal(#peer:GetTransportState().queue, 0)
		Equal(#peer.wire, 0)
	end
end)

QuestTogether:RegisterTest("only valid negotiated large diagnostic pages extend the bounded request deadline", function()
	local dev = DeveloperFixture()
	local _, silentID = dev:SendPingRequest("Silent-Realm", true)
	local _, legacyID = dev:SendPingRequest("Legacy-Realm", true)
	local _, largeID = dev:SendPingRequest("Large-Realm", true)
	local pending = dev.pendingPingRequests[largeID]
	Equal(dev:HandlePongPage("2," .. silentID .. ",0,2,invalid", "Silent-Realm"), false)
	Equal(dev.pendingPingRequests[silentID].expiresAt, pending.startedAt + 300)
	Equal(dev:HandlePongPage("1," .. legacyID .. ",1,2,legacy", "Legacy-Realm"), true)
	Equal(dev.pendingPingRequests[legacyID].expiresAt, pending.startedAt + 300)
	Equal(dev:HandlePongPage("2," .. largeID .. ",1,3,large", "Large-Realm"), true)
	Equal(pending.expiresAt, pending.startedAt + 600)
	dev.clock:Advance(301)
	Equal(dev.pendingPingRequests[silentID], nil)
	Equal(dev.pendingPingRequests[legacyID], nil)
	Equal(dev.pendingPingRequests[largeID], pending)
	Equal(dev:HandlePongPage("2," .. largeID .. ",2,3,more", "Large-Realm"), true)
	Equal(pending.expiresAt, pending.startedAt + 600, "later pages cannot keep extending a request")
	dev.clock:Advance(299)
	Equal(dev.pendingPingRequests[largeID], nil)
	Equal(dev:HandlePongPage("2," .. largeID .. ",3,3,last", "Large-Realm"), false)
end)
