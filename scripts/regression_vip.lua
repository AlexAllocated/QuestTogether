-- Private network/UI fixtures. Real issuer cryptography runs offline in services/vip.
local QT = _G.QuestTogether
local CERT = "QTVIP1." .. string.rep("1", 32) .. "." .. string.rep("2", 64) .. "." .. string.rep("3", 128)
local function Peer(net, name)
	local a = net:AddPeer(name)
	a.vipIssuerPublicKeyHex = string.rep("4", 64)
	a.Ed25519 = {
		Hash = QT.Ed25519.Hash,
		Verify = function(_, _, signature, checkpoint)
			for _ = 1, 30 do checkpoint() end
			return signature ~= string.rep("\0", 64)
		end,
		PublicKey = function(_, checkpoint) checkpoint(); return string.rep(string.char(34), 32) end,
		Sign = function(_, _, checkpoint) checkpoint(); return string.rep("s", 64) end,
	}
	function a:Emit(operation, ...)
		local ok, reason, ticket = QT.Emit(self, operation, ...)
		if operation == "VIP" then self.vipAdmission = tostring(ok) .. ":" .. tostring(reason) end
		return ok, reason, ticket
	end
	function a:HandleVIPIdentity(data, sender, context, callback)
		local accepted = QT.HandleVIPIdentity(self, data, sender, context, callback)
		self.vipReceived = tostring(accepted) .. ":" .. tostring(data.session == context.session)
		return accepted
	end
	return a
end
local function WaitFor(net, predicate)
	for _ = 1, 120 do
		if predicate() then return end
		net:Advance(1)
	end
	assert(predicate(), "verified VIP delivery did not complete within its bounded lifetime")
end
local function VIPPackets(peer)
	local objects, packets = {}, {}
	for _, packet in ipairs(peer.sent) do
		local frame, body = peer:DecodeCommFrame(packet.wire)
		if frame and frame.operation == "MPUB" then
			local key = frame.session .. ":" .. frame.messageId .. ":" .. tostring(packet.target)
			local item = objects[key] or { parts = {}, packets = {} }; objects[key] = item
			item.parts[frame.part], item.packets[frame.part] = body, packet
			local complete = true; for part = 1, frame.total do if not item.parts[part] then complete = false end end
			if complete then
				local pub = peer:DecodeCommRecord("MPUB", table.concat(item.parts))
				if pub and pub.operation == "VIP" then
					for _, sent in ipairs(item.packets) do packets[#packets+1] = sent end
				end
				objects[key] = nil
			end
		end
	end
	return packets
end
local function Install(a)
	local claim = a:GetVIPClaimCode()
	assert(a:ImportVIPActivation("QTVIPKEY1." .. claim:sub(10) .. "." .. string.rep("5", 64) .. "." .. CERT))
end
local function VerifyProof(observer, name, data)
	assert(observer:HandleVIPIdentity(data, name, { session = data.session }))
	for _ = 1, 10 do observer:UpdateVIPIdentity() end
	assert(observer.vipState.peers[name] and observer.vipState.peers[name].issuedAt == data.issuedAt)
end
QT:RegisterTest("VIP renewals from different players can arrive together without starving a star", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local observer = Peer(net, "Observer-Realm")
	net:StartPeer(observer)
	for round = 1, 4 do
		for _, name in ipairs({ "First-Realm", "Second-Realm" }) do
			local data = { certificate = CERT, signature = string.rep("6", 128), session = "session",
				issuedAt = observer:GetAnnouncementServerTime(), active = true }
			assert(observer:HandleVIPIdentity(data, name, { session = "session" }),
				"independent proofs received in the same frame must fit the bounded verification queue")
			assert(not observer:HandleVIPIdentity(data, name, { session = "session" }), "duplicates must not consume another job")
		end
		net:Advance(2)
		assert(observer:IsVerifiedVIP("First-Realm") and observer:IsVerifiedVIP("Second-Realm"))
		net:Advance(118)
	end
end, { offline = true })
QT:RegisterTest("VIP renewals retain every distinct peer until the identity cache admits another peer", function()
	local net = QT:CreateTestNetwork()
	local observer = Peer(net, "Observer-Realm")
	local function Verify(name)
		local data = { certificate = CERT, signature = string.rep("6", 128), session = "session",
			issuedAt = observer:GetAnnouncementServerTime(), active = true }
		assert(observer:HandleVIPIdentity(data, name, { session = data.session }))
		for _ = 1, 10 do observer:UpdateVIPIdentity() end
		assert(observer:IsVerifiedVIP(name))
	end
	for index = 1, 512 do Verify("Peer" .. index .. "-Realm") end
	net:Advance(11)
	Verify("Peer2-Realm")
	assert(observer:IsVerifiedVIP("Peer1-Realm"), "renewing an existing peer must not evict an unrelated valid proof")
	assert(#observer.vipState.order == 512, "the cache limit counts current peers rather than historical renewals")
	Verify("Peer513-Realm")
	assert(not observer:IsVerifiedVIP("Peer1-Realm"), "a new peer may evict the oldest proof at capacity")
	assert(observer:IsVerifiedVIP("Peer2-Realm"), "the refreshed peer remains in the bounded cache")
	observer:RetireVIPPeer("Peer2-Realm")
	assert(#observer.vipState.order == 511, "retirement must remove obsolete order entries as well as the proof")
end)
QT:RegisterTest("VIP cached proof eligibility preserves exact identity withdrawal and original expiry", function()
	local net = QT:CreateTestNetwork()
	local observer, name = Peer(net, "Observer-Realm"), "VIP-Realm"
	local data = { certificate = CERT, signature = string.rep("6", 128), session = "session",
		issuedAt = observer:GetAnnouncementServerTime(), active = true }
	VerifyProof(observer, name, data)
	assert(observer:IsCurrentVerifiedVIPProof(name, data))
	for key, value in pairs({ certificate = CERT .. "x", signature = string.rep("7", 128), session = "other",
		issuedAt = data.issuedAt + 1, active = false }) do
		local changed = {}; for field, original in pairs(data) do changed[field] = original end
		changed[key] = value
		assert(not observer:IsCurrentVerifiedVIPProof(name, changed), key .. " must match the current signed proof")
	end
	assert(not observer:IsCurrentVerifiedVIPProof("Other-Realm", data))
	net:Advance(11)
	local withdrawn = { certificate = CERT, signature = string.rep("6", 128), session = data.session,
		issuedAt = observer:GetAnnouncementServerTime(), active = false }
	VerifyProof(observer, name, withdrawn)
	assert(not observer:IsCurrentVerifiedVIPProof(name, data), "old enabled proof must not survive withdrawal")
	assert(observer:IsCurrentVerifiedVIPProof(name, withdrawn), "the newest signed withdrawal remains replayable")
	local expires, callbacks = observer.vipState.peers[name].expires, 0
	assert(observer:HandleVIPIdentity(withdrawn, name, { session = withdrawn.session }, function() callbacks = callbacks + 1 end))
	assert(callbacks == 1 and observer.vipState.peers[name].expires == expires, "a verified duplicate must not renew the lease")
	observer.ignored[name] = true
	assert(not observer:IsCurrentVerifiedVIPProof(name, withdrawn))
	observer.ignored[name] = nil
	observer.communicationState.departing = true
	assert(not observer:IsCurrentVerifiedVIPProof(name, withdrawn))
	observer.communicationState.departing = nil
	assert(observer:IsCurrentVerifiedVIPProof(name, withdrawn))
	net:Advance(301)
	assert(not observer:IsCurrentVerifiedVIPProof(name, withdrawn), "cached replay ends at original signed expiry")
	data.issuedAt = observer:GetAnnouncementServerTime()
	VerifyProof(observer, name, data)
	assert(observer:RecordPeerEpoch(name, "replacement", data.issuedAt + 1))
	assert(not observer:IsCurrentVerifiedVIPProof(name, data), "a replacement peer session invalidates cached proof")
end)
QT:RegisterTest("VIP diagnostics distinguish cached proof health and record renewal gaps without private data", function()
	local net = QT:CreateTestNetwork()
	local observer = Peer(net, "Observer-Realm")
	local function Verify(name, active, session)
		local data = { certificate = CERT, signature = string.rep("6", 128), session = session or "session",
			issuedAt = observer:GetAnnouncementServerTime(), active = active ~= false }
		VerifyProof(observer, name, data)
		return data
	end
	Verify("Expired-Realm")
	net:Advance(301)
	Verify("Valid-Realm")
	Verify("Withdrawn-Realm", false)
	local stale = Verify("Session-Realm")
	observer:RecordPeerEpoch("Session-Realm", "replacement", stale.issuedAt + 1)
	Verify("Ignored-Realm")
	observer.ignored["Ignored-Realm"] = true
	observer.vipState.metrics.expired = 7
	local metrics = observer:GetVIPCommunicationMetrics()
	assert(metrics.proofsCached == 5 and metrics.proofsValid == 1 and metrics.proofsExpired == 1)
	assert(metrics.proofsWithdrawn == 1 and metrics.proofsSessionInvalid == 1 and metrics.proofsUnavailable == 1)
	assert(metrics.expired == 7, "existing expired verification jobs metric must keep its original meaning")
	for _, value in pairs(metrics) do assert(type(value) == "number", "diagnostics must expose only aggregate numbers") end
	Verify("Expired-Realm")
	metrics = observer:GetVIPCommunicationMetrics()
	assert(metrics.renewalGaps == 1 and math.abs(metrics.renewalGapLast - 1) < 0.000001
		and math.abs(metrics.renewalGapMax - 1) < 0.000001)
	net:Advance(11)
	Verify("Expired-Realm")
	assert(observer:GetVIPCommunicationMetrics().renewalGaps == 1, "an on-time renewal is not a gap")
	net:Advance(301)
	Verify("Valid-Realm", false)
	Verify("Withdrawn-Realm", true)
	Verify("Expired-Realm", true, "new-session")
	assert(observer:GetVIPCommunicationMetrics().renewalGaps == 1,
		"withdrawal, reenabling cosmetics, and a new session must not count as a missing renewal")
end)
QT:RegisterTest("VIP stars and locations survive a lost renewal with concurrent peers and reordered fragments", function()
	local net = QT:CreateTestNetwork({ fps = 5 })
	local observer, publishers = Peer(net, "Observer-Realm"), {}
	net:StartPeer(observer)
	for index = 1, 3 do
		local a = Peer(net, "VIP" .. index .. "-Realm")
		publishers[index] = a
		net:StartPeer(a)
	end
	net:Advance(20)
	for _, a in ipairs(publishers) do Install(a) end
	WaitFor(net, function()
		for _, a in ipairs(publishers) do
			if not observer:IsVerifiedVIP(a.name) or not observer:GetFreshPlayerLocation(a.name) then return false end
		end
		return true
	end)
	local lost = {}
	net.deliveryRule = function(packet, receiver)
		local frame = observer:DecodeCommFrame(packet.wire)
		if receiver == observer and frame.operation == "MPUB" then
			if frame.part == 2 and not lost[packet.sender] then
				lost[packet.sender] = true
				return { drop = true }
			end
			return { copies = 2, delay = frame.part == 1 and 0.5 or 0.05 }
		end
	end
	for _ = 1, 200 do
		net:Advance(2)
		for _, a in ipairs(publishers) do
			assert(observer:IsVerifiedVIP(a.name), "one lost renewal must not interrupt a verified star")
			assert(observer:GetFreshPlayerLocation(a.name), "VIP traffic must not starve location renewal")
		end
	end
	for _, a in ipairs(publishers) do assert(lost[a.name]) end
	assert(observer:GetVIPCommunicationMetrics().pending <= 8)
end, { offline = true })
QT:RegisterTest("local world transitions retain verified VIP proofs without renewing them or retaining pending work", function()
	local net = QT:CreateTestNetwork()
	local a = Peer(net, "Observer-Realm")
	local data = { certificate = CERT, signature = string.rep("6", 128), session = "peer-session",
		issuedAt = a:GetAnnouncementServerTime(), active = true }
	assert(a:HandleVIPIdentity(data, "Verified-Realm", { session = data.session }))
	for _ = 1, 10 do a:UpdateVIPIdentity() end
	assert(a:IsVerifiedVIP("Verified-Realm"))
	assert(a:HandleVIPIdentity(data, "Pending-Realm", { session = data.session }))
	local expires = a.vipState.peers["Verified-Realm"].expires
	a:EndCommsWorldSession(true)
	assert(not a:IsVerifiedVIP("Verified-Realm"), "departed local runtime must remain inactive")
	a.now = a.now + 5
	a:ResumeCommsWorldSession()
	assert(a:IsVerifiedVIP("Verified-Realm"), "zoning locally must not discard another player's valid proof")
	assert(#a.vipState.jobs == 0 and not a:IsVerifiedVIP("Pending-Realm"))
	assert(a.vipState.peers["Verified-Realm"].expires == expires, "zoning cannot renew a proof")
	a.now = expires
	assert(not a:IsVerifiedVIP("Verified-Realm"))
	a:EndCommsWorldSession()
	assert(a.vipState == nil, "disable/full reset must still clear identity state")
end)
QT:RegisterTest("reload scan announcement waits for VIP verification without replaying retired scans", function()
	for _, scenario in ipairs({ "valid", "invalid", "hidden", "ordinary", "logout", "lifetime" }) do
		local net = QT:CreateTestNetwork({ fps = 10 })
		local a = Peer(net, "VIP-Realm")
		a.vipStore = scenario == "ordinary" and {} or {
			seed = string.rep("5", 64),
			certificate = scenario == "invalid" and CERT:sub(1, 105) .. string.rep("0", 128) or CERT,
			visible = scenario ~= "hidden",
		}
		local printed = {}
		function a:PrintConsoleAnnouncement(text)
			printed[#printed + 1] = { text = text, vip = self:IsVerifiedVIP(self.name) }
		end
		net:StartPeer(a)
		a:PrintQuestScanAnnouncement(4)
		if scenario == "ordinary" or scenario == "hidden" then
			assert(#printed == 1 and not printed[1].vip, "ordinary or hidden cosmetics do not delay the scan")
		else
			assert(#printed == 0 and a.pendingQuestScanAnnouncement, "saved credentials are not trusted before verification")
			a:PrintQuestScanAnnouncement(5)
			if scenario == "logout" then a.isLoggingOut = true
			elseif scenario == "lifetime" then a.pendingQuestScanAnnouncement.lifetime = {} end
			net:Advance(2)
			a:FlushPendingQuestScanAnnouncement()
			if scenario == "logout" or scenario == "lifetime" then
				assert(#printed == 0 and not a.pendingQuestScanAnnouncement)
			else
				assert(#printed == 1 and printed[1].text == a:GetMonitoredQuestCountText(5))
				assert(printed[1].vip == (scenario == "valid"), "the verified result determines the prefix")
			end
		end
		net:Advance(1)
		assert(#printed <= 1, "later ticks must not duplicate the scan")
	end
end)
QT:RegisterTest("VIP proofs travel through paced fragmented global traffic and withdraw without sharing private keys", function()
	local net = QT:CreateTestNetwork({ fps = 10 })
	local vip, observer = Peer(net, "VIP-Realm"), Peer(net, "Observer-Realm")
	net:StartPeer(vip)
	net:StartPeer(observer)
	net:Advance(35) -- Asynchronous directory discovery and reciprocal handshakes precede the proof.
	Install(vip)
	assert(not vip:IsVerifiedVIP(vip.name))
	WaitFor(net, function() return observer:IsVerifiedVIP(vip.name) end)
	assert(vip:IsVerifiedVIP(vip.name))
	assert(vip:IsVIPActivated())
	assert(observer:IsVerifiedVIP(vip.name), "receiver must assemble and authenticate the public proof; admission="
		.. tostring(vip.vipAdmission) .. "; packets=" .. #vip.sent .. "; received=" .. tostring(observer.vipReceived)
		.. "; jobs=" .. #observer.vipState.jobs .. "; known=" .. tostring(observer.vipState.peers[vip.name] ~= nil))
	assert(not observer:IsVerifiedDeveloper(vip.name), "cosmetics never grant diagnostics authority")
	assert(not vip:IsVerifiedVIP(observer.name))
local packets = VIPPackets(vip)
	assert(#packets > 1, "exercise the actual fragmented mesh proof")
	for _, packet in ipairs(packets) do
		assert(#packet.wire <= 255 and packet.route == "WHISPER")
		assert(not packet.wire:find(vip.vipStore.seed, 1, true))
		assert(not packet.wire:find(vip.vipStore.claim, 1, true))
	end
	vip:SetVIPDisplayEnabled(false)
	assert(vip:IsVIPActivated(), "hiding cosmetics must not remove activation")
	assert(not vip:IsVerifiedVIP(vip.name))
	WaitFor(net, function() return not observer:IsVerifiedVIP(vip.name) end)
	assert(not observer:IsVerifiedVIP(vip.name), "withdrawal must retire the remote star")
	vip:SetVIPDisplayEnabled(true)
	WaitFor(net, function() return observer:IsVerifiedVIP(vip.name) end)
	assert(observer:IsVerifiedVIP(vip.name))
	local retired = vip.vipState
	vip:EndCommunicationSession()
	assert(vip.vipState == nil and retired ~= vip.vipState)
	assert(not vip:IsVerifiedVIP(vip.name))
end)

QT:RegisterTest("VIP inbound work is bounded and stale verification cannot revive retired identities", function()
	for _, boundary in ipairs({ "retire", "ignore", "disable", "logout", "session", "reset" }) do
		local net = QT:CreateTestNetwork()
		local a = Peer(net, "Observer-Realm")
		local data = { certificate = CERT, signature = string.rep("6", 128), session = "session",
			issuedAt = a:GetAnnouncementServerTime(), active = true }
		assert(a:HandleVIPIdentity(data, "Peer-Realm", { session = "session", stamp = data.issuedAt }))
		if boundary == "retire" then a:RetireVIPPeer("Peer-Realm")
		elseif boundary == "ignore" then a.ignored["Peer-Realm"] = true
		elseif boundary == "disable" then a.isEnabled = false
		elseif boundary == "logout" then a.isLoggingOut = true
		elseif boundary == "session" then a:RecordPeerEpoch("Peer-Realm", "next", data.issuedAt + 1)
		else a:ResetVIPIdentity() end
		for _ = 1, 10 do a:UpdateVIPIdentity() end
		assert(not a:IsVerifiedVIP("Peer-Realm"), boundary)
	end
	local a = Peer(QT:CreateTestNetwork(), "Observer-Realm")
	local data = { certificate = CERT, signature = string.rep("6", 128), session = "session",
		issuedAt = a:GetAnnouncementServerTime(), active = true }
	for i = 1, 40 do
		a.now = a.now + 0.2
		a:HandleVIPIdentity(data, "Peer" .. i .. "-Realm", { session = "session", stamp = data.issuedAt })
	end
	assert(#a.vipState.jobs == 8, "inbound crypto jobs must be bounded")
end)

QT:RegisterTest("VIP window offers contact claim and private activation with safe lifecycle", function()
	local a = setmetatable({ isEnabled = true, db = { profile = {} }, runtimeStateStore = {},
		PLAYER_VIP_ICON_TEXTURE = QT.PLAYER_VIP_ICON_TEXTURE }, { __index = QT })
	a.API = { GetTime = function() return 100 end, Random = function() return 123 end }
	a.parent = QT:CreateTestUIRegion(a)
	a.parent:SetSize(1280, 960)
	function a:IsWorkBlocked() return self.blocked == true end
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:GetOwnedUIParent() return self.parent end
	function a:GetOption(key) return key == "windowScale" and 100 or false end
	function a:CreateOwnedWindowFrame(kind, _, parent, template)
		return self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
	end
	function a:CreateOwnedUICleanupFrame() return self:CreateTestUIRegion({}) end
	function a:ImportVIPActivation(code) self.imported = code; return true end
	function a:OpenDiscordSupport() self.discordOpened = true end
	assert(a:OpenVIPWindow())
	local frame = a.vipWindow
	assert(frame.username:GetText() == "@chevcast")
	assert(frame.claim:GetText() == a:GetVIPClaimCode())
	assert(frame.activate.enabled == false, "blank activation must not be submitted")
	assert(frame:GetWidth() == 875 and frame:GetHeight() == 775 and frame.content:GetHeight() > frame.scroll:GetHeight(), "content must scroll without growing the window")
	assert(frame.activation.parent == frame.content and frame.activate.parent == frame, "only content scrolls; actions remain outside")
	frame.scroll:GetScript("OnMouseWheel")(frame.scroll, -1000)
	assert(frame.scrollOffset == frame.scrollMaximum and frame.scroll.verticalScroll == frame.scrollMaximum)
	frame.scroll:GetScript("OnMouseWheel")(frame.scroll, 1000)
	frame.activation:SetFocus()
	assert(frame.activation.vipContentTop >= frame.scrollOffset
		and frame.activation.vipContentTop + frame.activation:GetHeight() <= frame.scrollOffset + frame.scroll:GetHeight(), "focused activation field must be visible")
	frame.activation:ClearFocus()
	frame:SetSize(540, 400)
	assert(frame:GetHeight() == 400 and frame.activation:GetWidth() == frame.content:GetWidth())
	a.parent:SetSize(600, 400)
	frame:LayoutManagedWindow()
	assert(frame:GetHeight() * frame:GetScale() <= 400 * .94 and frame:GetWidth() * frame:GetScale() <= 600 * .94)
	frame.resizeGrip:GetScript("OnMouseDown")(frame.resizeGrip, "LeftButton")
	assert(frame.resizing)
	frame.activation:SetText("PRIVATE TEST CODE")
	frame.activate:Click()
	assert(a.imported == "PRIVATE TEST CODE" and frame.activation:GetText() == "")
	frame.discord:Click()
	assert(a.discordOpened)
	frame.activation:SetText("PRIVATE UNSUBMITTED CODE")
	frame.close:Click()
	assert(not frame:IsShown() and frame.activation:GetText() == "" and not frame.resizing)
	a.blocked = true
	assert(not a:OpenVIPWindow())
end)

_G.QuestTogether:RecordTestModule("scripts/regression_vip.lua")
