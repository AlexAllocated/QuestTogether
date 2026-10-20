-- Cosmetic identity only. No developer permissions, diagnostic consent, or
-- profile data are inferred from these certificates. Private keys never go on wire.
local QT = _G.QuestTogether
local L = QT.Translate
local MAX_PEERS, MAX_JOBS, TTL = 512, 8, 300

local function Hex(value)
	return (value:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
local function Unhex(value, bytes)
	if type(value) ~= "string" or #value ~= bytes * 2 or value:find("[^0-9a-f]") then return nil end
	return (value:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end
local function Parse(certificate)
	if type(certificate) ~= "string" or #certificate ~= 233 then return nil end
	local id, public, signature = certificate:match("^QTVIP1%.([0-9a-f]+)%.([0-9a-f]+)%.([0-9a-f]+)$")
	if not Unhex(id, 16) or not Unhex(public, 32) or not Unhex(signature, 64) then return nil end
	return { id = id, public = Unhex(public, 32), signature = Unhex(signature, 64),
		message = "QTVIP1\n" .. id .. "\n" .. public, text = certificate }
end
local function Now(a) return a.API.GetTime() end
local function Current(a, s)
	return rawget(a, "vipState") == s and a.isEnabled and not a.isLoggingOut
		and rawget(a, "communicationState") == s.communication and not s.communication.departing
end
local function Store(a)
	-- Tests supply their own storage; production uses a separate account-wide
	-- SavedVariables root, never included in diagnostic/profile snapshots.
	local store = rawget(a, "vipStore")
	if store then return store end
	if a ~= QT then a.vipStore = {}; return a.vipStore end
	if type(_G.QuestTogetherVIP) ~= "table" then _G.QuestTogetherVIP = {} end
	a.vipStore = _G.QuestTogetherVIP
	return a.vipStore
end
local function Proof(certificate, sender, session, issued, active)
	return table.concat({ "QTVIPPROOF1", certificate, sender, session, tostring(issued), active and "on" or "off" }, "\n")
end
local function State(a)
	local s = rawget(a, "vipState")
	if not s then
		s = { communication = a:InitializeCommunications(), jobs = {}, peers = {}, order = {},
			cooldowns = {}, cooldownOrder = {}, nextPublish = Now(a) + 3, nextInbound = 0 }
		a.vipState = s
	end
	return s
end
local function Changed(a)
	if a.InvalidatePlayerLocationPresentation then a:InvalidatePlayerLocationPresentation() end
	if a.RefreshVIPWindow then a:RefreshVIPWindow() end
	if a.RefreshMinimapIdentityIcon then a:RefreshMinimapIdentityIcon() end
end
function QT:GetVIPClaimCode()
	local store = Store(self)
	if type(store.claim) ~= "string" or not store.claim:match("^QTCLAIM1%.[0-9a-f]+$") or #store.claim ~= 41 then
		-- Correlation token only: no secret or authentication strength relies on RNG.
		local parts = {}
		for i = 1, 4 do parts[i] = string.format("%08x", self.API.Random(1, 2147483647)) end
		store.claim = "QTCLAIM1." .. table.concat(parts)
	end
	return store.claim
end
function QT:IsVIPActivated()
	local s = rawget(self, "vipState")
	return s ~= nil and s.credential ~= nil
end
function QT:IsLocalVIPVerificationPending()
	local store, s = Store(self), rawget(self, "vipState")
	if store.visible == false or (s and s.credential) then return false end
	if s and s.localJob then return true end
	-- The initial quest scan can run before the first identity tick.
	return (not s or not s.loaded) and Parse(store.certificate) ~= nil and Unhex(store.seed, 32) ~= nil
end
function QT:GetVIPStatus()
	local s = rawget(self, "vipState")
	if s and s.localJob then return L("Checking VIP activation...") end
	if self:IsVIPActivated() then return Store(self).visible == false and L("VIP active; cosmetics hidden.") or L("VIP active.") end
	return (s and s.status) or L("VIP has not been activated.")
end
function QT:IsVIPDisplayEnabled() return Store(self).visible ~= false end
function QT:SetVIPDisplayEnabled(enabled)
	Store(self).visible = enabled == true
	local s = rawget(self, "vipState")
	if s then
		-- Coalesce rapid toggles and stay outside receivers' verification cooldown.
		s.nextPublish, s.proof, s.signing = math.max(0, (s.lastSubmitted or -12) + 12), nil, nil
		self:CancelCommunicationOwner(s, "cancelled")
	end
	Changed(self)
end
function QT:IsVerifiedVIP(name)
	if not self.isEnabled or self.isLoggingOut then return false end
	name = self:NormalizeMemberName(name)
	if not name or self:IsIgnoredPlayerName(name) then return false end
	local s = rawget(self, "vipState")
	if not s or not Current(self, s) then return false end
	if self:IsSelfSender(name) then return s.credential ~= nil and Store(self).visible ~= false end
	local peer = s.peers[name]
	return peer ~= nil and peer.active and Now(self) >= peer.received and Now(self) < peer.expires
		and self:IsPeerSessionObservationCurrent(name, peer.session, peer.sampledAt)
end
function QT:RetireVIPPeer(name)
	local s = rawget(self, "vipState")
	if not s then return end
	s.peers[name] = nil
	for _, job in ipairs(s.jobs) do if job.sender == name then job.cancelled = true end end
end
function QT:ResetVIPIdentity()
	local s = rawget(self, "vipState")
	if s then self:CancelCommunicationOwner(s, "cancelled") end
	self.vipState = nil
	if self.RefreshMinimapIdentityIcon then self:RefreshMinimapIdentityIcon() end
end
local function CheckCredential(a, seed, certificate)
	local cert, issuer = Parse(certificate), Unhex(a.vipIssuerPublicKeyHex, 32)
	if not cert or not issuer or not Unhex(seed, 32) then return nil end
	return coroutine.create(function()
		if not a.Ed25519.Verify(issuer, cert.message, cert.signature, coroutine.yield) then return false end
		return a.Ed25519.PublicKey(Unhex(seed, 32), coroutine.yield) == cert.public
	end)
end
function QT:ImportVIPActivation(code)
	if not self.isEnabled or self.isLoggingOut or type(code) ~= "string" or #code > 512 then return false end
	code = code:gsub("%s", "")
	local claim, seed, certificate = code:match("^QTVIPKEY1%.([0-9a-f]+)%.([0-9a-f]+)%.(QTVIP1%..+)$")
	local s = State(self)
	local verifier = claim and "QTCLAIM1." .. claim == self:GetVIPClaimCode() and CheckCredential(self, seed, certificate)
	if not verifier then
		s.status = L("Invalid activation code. Use the code issued for this claim.")
		Changed(self)
		return false
	end
	s.localJob = { verifier = verifier, seed = seed, certificate = certificate, import = true }
	s.loaded = true
	Changed(self)
	return true
end
function QT:HandleVIPIdentity(data, sender, context)
	local now, stamp = Now(self), self:GetAnnouncementServerTime()
	if not self.isEnabled or self.isLoggingOut or self:IsSelfSender(sender) or self:IsIgnoredPlayerName(sender)
		or not Parse(data.certificate) or not Unhex(data.signature, 64)
		or type(data.issuedAt) ~= "number" or data.issuedAt % 1 ~= 0
		or not stamp or stamp < data.issuedAt - 30 or stamp - data.issuedAt >= TTL
		or data.session ~= context.session or type(data.active) ~= "boolean"
		or not self:CanAcceptPeerEpoch(sender, context.session, data.issuedAt) then return false end
	local s = State(self)
	if not Current(self, s) or #s.jobs >= MAX_JOBS or now < s.nextInbound
		or (s.cooldowns[sender] and now < s.cooldowns[sender]) then return false end
	local old = s.peers[sender]
	if old and old.session == data.session and old.issuedAt >= data.issuedAt then return false end
	s.nextInbound = now + 0.1
	s.cooldowns[sender] = now + 10
	s.cooldownOrder[#s.cooldownOrder + 1] = { sender, now + 10 }
	if #s.cooldownOrder > MAX_PEERS then
		local first = table.remove(s.cooldownOrder, 1)
		if s.cooldowns[first[1]] == first[2] then s.cooldowns[first[1]] = nil end
	end
	local cert, issuer = Parse(data.certificate), Unhex(self.vipIssuerPublicKeyHex, 32)
	if not issuer then return false end
	local signature, session, issued, active = Unhex(data.signature, 64), data.session, data.issuedAt, data.active
	local job = { sender = sender, session = session, issuedAt = issued, active = active,
		stamp = issued, received = now, sampledAt = now - math.max(0, stamp - issued),
		expires = now + TTL - math.max(0, stamp - issued) }
	job.verifier = coroutine.create(function()
		if not self.Ed25519.Verify(issuer, cert.message, cert.signature, coroutine.yield) then return false end
		return self.Ed25519.Verify(cert.public, Proof(cert.text, sender, session, issued, active), signature, coroutine.yield)
	end)
	s.jobs[#s.jobs + 1] = job
	return true
end
local function Step(job, budget)
	for _ = 1, budget do
		local ok, result = coroutine.resume(job.verifier)
		if not ok then return true, false end -- Never log coroutine errors containing private material.
		if coroutine.status(job.verifier) == "dead" then return true, result end
	end
	return false
end
function QT:UpdateVIPIdentity()
	if not self.isEnabled or self.isLoggingOut then return end
	local s = State(self)
	if not Current(self, s) then return end
	local store, now = Store(self), Now(self)
	if not s.loaded then
		s.loaded = true
		local verifier = CheckCredential(self, store.seed, store.certificate)
		if verifier then s.localJob = { verifier = verifier, seed = store.seed, certificate = store.certificate } end
	end
	-- Fixed arithmetic slices, one local job plus one rotating remote job.
	-- No synchronous signing/verification on UI or packet callbacks.
	if s.localJob then
		local job = s.localJob
		local done, valid = Step(job, 12)
		if done then
			s.localJob = nil
			if valid then
				s.credential = { seed = job.seed, certificate = job.certificate }
				if job.import then store.seed, store.certificate = job.seed, job.certificate end
				s.nextPublish, s.proof, s.signing = 0, nil, nil
				self:CancelCommunicationOwner(s, "superseded")
			else s.status = L("VIP activation could not be verified.") end
			Changed(self)
		end
	end
	if #s.jobs > 0 then
		local job = table.remove(s.jobs, 1)
		if not job.cancelled and now < job.expires and not self:IsIgnoredPlayerName(job.sender) then
			local done, valid = Step(job, 12)
			if not done then s.jobs[#s.jobs + 1] = job
			elseif valid and Current(self, s) and self:CanAcceptPeerEpoch(job.sender, job.session, job.stamp) then
				local old = s.peers[job.sender]
				if (not old or old.session ~= job.session or old.issuedAt < job.issuedAt)
					and self:RecordPeerEpoch(job.sender, job.session, job.stamp) then
					s.peers[job.sender] = job
					job.verifier = nil
					s.order[#s.order + 1] = job
					if #s.order > MAX_PEERS then
						local first = table.remove(s.order, 1)
						if s.peers[first.sender] == first then s.peers[first.sender] = nil end
					end
					Changed(self)
				end
			end
		end
	end
	if s.credential and not s.localJob and now >= s.nextPublish then
		if not s.signing and not s.proof then
			local issued = self:GetAnnouncementServerTime()
			local sender = self:NormalizeMemberName(self:GetPlayerFullName())
			if not issued or not sender then return end
			local certificate, seed = s.credential.certificate, Unhex(s.credential.seed, 32)
			local session, active = s.communication.session, store.visible ~= false
			local issuedAt = math.max(math.floor(issued), (s.lastIssuedAt or 0) + 1)
			if issuedAt > issued + 30 then s.nextPublish = now + 30; return end
			s.lastIssuedAt = issuedAt
			local data = { certificate = certificate, issuedAt = issuedAt, session = session, active = active }
			s.signing = { data = data, verifier = coroutine.create(function()
				return Hex(self.Ed25519.Sign(seed, Proof(certificate, sender, session, data.issuedAt, active), coroutine.yield))
			end) }
		end
		if s.signing then
			local done, signature = Step(s.signing, 12)
			if done then
				if type(signature) == "string" then
					s.proof = s.signing.data
					s.proof.signature = signature
				else s.nextPublish = now + 30 end
				s.signing = nil
			end
		end
		if s.proof then
			local proof = s.proof
			local stamp = self:GetAnnouncementServerTime()
			if not stamp or stamp - proof.issuedAt >= 240 then s.proof = nil; return end
			local ok = self:Emit("VIP", proof, { { distribution = "CHANNEL", channelName = self.announcementChannelName } }, {
				owner = s, expires = now + 30, key = "vip", isCurrent = function()
					return Current(self, s) and s.credential ~= nil and s.credential.certificate == proof.certificate
						and (store.visible ~= false) == proof.active
				end,
				onComplete = function(accepted, result)
					if not accepted and result ~= "ambiguous" and Current(self, s)
						and s.lastIssuedAt == proof.issuedAt and (store.visible ~= false) == proof.active then
						-- Admission can precede the asynchronous channel join.
						-- A cancelled/expired route must not postpone first discovery for two minutes.
						s.nextPublish = math.min(s.nextPublish, Now(self) + 5)
					end
				end,
			})
			s.nextPublish = now + (ok and 120 or 5)
			if ok then s.proof, s.lastSubmitted = nil, now end
		end
	end
end
