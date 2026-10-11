-- One small-party snapshot owns focus, native waypoint and follow intent.
-- No public-channel traffic or per-feature timers. Only follow intent persists.
local QT = _G.QuestTogether
local L = QT.Translate
local TTL = 90
local function Now(a)
	return a:SafeToNumber(a.API.GetTime and a.API.GetTime()) or 0
end
local function Number(a, v, lo, hi)
	v = a:SafeToNumber(v)
	return v and v >= lo and v <= hi and v == math.floor(v) and v or nil
end
local function Name(a, v)
	if not a:CanAccessValue(v) or type(v) ~= "string" or #v > 120 or v:find("[%c|,]") then
		return nil
	end
	return a:NormalizeMemberName(v)
end
local function Changed(a)
	if a.QueuePartyQuestCompareRender and rawget(a, "partyQuestCompareSession") then
		a:QueuePartyQuestCompareRender()
	end
end
function QT:GetPartyNavigationRoute()
	if not self.isEnabled or self.isLoggingOut or not self.API.IsInRaid or self.API.IsInRaid() then
		return nil
	end
	local route = self:GetGroupAnnouncementDistribution()
	if route ~= "PARTY" and route ~= "INSTANCE_CHAT" then
		return nil
	end
	local count = 0
	for _ in pairs(self.partyMembers or {}) do
		count = count + 1
	end
	return count >= 2 and count <= 5 and route or nil
end
-- Saved per character, not per options profile. Never persist a peer snapshot:
-- a restored follow waits for current, validated group navigation data.
local function FollowStore(a)
	local db = rawget(a, "db")
	local owner = rawget(a, "activeCharacterKey")
	if type(db) ~= "table" or type(db.global) ~= "table" or type(owner) ~= "string" then
		return nil
	end
	if type(db.global.partyQuestFollowByCharacter) ~= "table" then
		db.global.partyQuestFollowByCharacter = {}
	end
	return db.global.partyQuestFollowByCharacter, owner
end
function QT:SavePartyQuestFollow(name)
	local store, owner = FollowStore(self)
	if store then
		store[owner] = name and Name(self, name) or nil
	end
end
function QT:GetPartyNavigationState()
	local s = rawget(self, "partyNavigationState")
	if not s then
		s = {
			peers = {},
			seen = {},
			sequence = 0,
			hello = true,
			nextSend = Now(self) + 0.25,
		}
		local store, owner = FollowStore(self)
		local target = store and Name(self, store[owner])
		if target and not self:IsSelfSender(target) then
			s.following, s.resuming, s.followStatus = target, true, L("Waiting for quest focus")
			s.followToken = {}
		elseif store then
			store[owner] = nil
		end
		self.partyNavigationState = s
	end
	return s
end
function QT:QueuePartyNavigationUpdate()
	if not self:GetPartyNavigationRoute() then
		return
	end
	local s = self:GetPartyNavigationState()
	s.dirtyAt = s.dirtyAt or (Now(self) + 0.25)
end
function QT:StopPartyQuestFollow()
	return self:GetPartyFocusController():Stop()
end
-- Departures preserve follow intent; the controller resumes when a peer returns.
function QT:RetirePartyNavigationPeer(name)
	local state = rawget(self, "partyNavigationState")
	if not state or not state.peers[name] then
		return
	end
	state.peers[name] = nil
	if state.following == name then
		state.attempt = nil
		state.followStatus = L("Waiting for quest focus")
	end
	Changed(self)
	if self.RefreshPartyWaypointPins then
		self:RefreshPartyWaypointPins()
	end
end
function QT:GetPartyNavigationPeer(name)
	name = Name(self, name)
	local s = rawget(self, "partyNavigationState")
	if
		not name
		or not s
		or not self:GetPartyNavigationRoute()
		or not self:IsGroupedSender(name)
		or self:IsIgnoredPlayerName(name)
	then
		return nil
	end
	if self:IsSelfSender(name) then
		return s.localState
	end
	local p = s.peers[name]
	local now = Now(self)
	if p and now >= p.at and now - p.at < TTL then
		return p
	end
end
function QT:GetPartyFocusController()
	local controller = rawget(self, "partyFocusController")
	if controller then
		return controller
	end
	local a = self
	controller = self:CreatePartyFocusController({
		state = function()
			return a:GetPartyNavigationState()
		end,
		peek = function()
			return rawget(a, "partyNavigationState")
		end,
		ownName = function()
			return a:GetPlayerFullName()
		end,
		normalize = function(name)
			return Name(a, name)
		end,
		peer = function(name)
			return a:GetPartyNavigationPeer(name)
		end,
		member = function(name)
			return a:IsGroupedSender(name)
		end,
		ignored = function(name)
			return a:IsIgnoredPlayerName(name)
		end,
		raid = function()
			return a.API.IsInRaid and a.API.IsInRaid()
		end,
		groupInvalid = function()
			return (a.API.IsInRaid and a.API.IsInRaid()) or (a.API.IsInParty and not a.API.IsInParty())
		end,
		loggingOut = function()
			return a.isLoggingOut
		end,
		restricted = function()
			return a:IsRuntimeRestricted()
		end,
		blocked = function()
			return a:IsWorkBlocked("foreign_frame_mutation")
		end,
		active = function()
			return not rawget(a, "nativePartyFocusOwner") or a.nativePartyFocusOwner == controller
		end,
		currentQuest = function()
			return a.API.GetActiveTrackedQuestID()
		end,
		native = function()
			return a.API.GetPartyNavigationNativeState()
		end,
		readable = function(value)
			return a:CanAccessTable(value)
		end,
		owns = function(id)
			return a.API.IsOnQuest(id)
		end,
		setQuest = function(id)
			return a.API.SetPartyNavigationQuest(id)
		end,
		questID = function(id)
			return Number(a, id, 0, 1000000000)
		end,
		save = function(name)
			a:SavePartyQuestFollow(name)
		end,
		clearMissing = function()
			a:ClearPartyFocusMissingNotice()
		end,
		missing = function(name, id, title)
			a:QueuePartyFocusMissingNotice(name, id, title)
		end,
		confirm = function(name, callback)
			return a:ShowPartyFocusChangeDialog(name, callback)
		end,
		changed = function()
			Changed(a)
		end,
		publish = function()
			a:QueuePartyNavigationUpdate()
		end,
	})
	self.partyFocusController = controller
	return controller
end
function QT:WouldPartyQuestFollowCycle(name)
	return self:GetPartyFocusController():WouldCycle(name)
end
function QT:FollowPartyQuestFocus(name)
	return self:GetPartyFocusController():Follow(name)
end
function QT:ApplyPartyQuestFocus()
	return self:GetPartyFocusController():Apply()
end
function QT:OnPartyNavigationTrackingChanged()
	return self:GetPartyFocusController():OnTrackingChanged()
end
function QT:SamplePartyNavigation()
	local controller = self:GetPartyFocusController()
	local native = controller:ObserveNative()
	if not native then
		return nil
	end
	local state = self:GetPartyNavigationState()
	local qid = self:GetOption("sharePartyFocus") == true and native.questID or -1
	local map = self:GetOption("sharePartyWaypoint") == true and native.mapID or -1
	local title = ""
	if qid > 0 then
		title = self:GetLocalizedQuestTitle(qid) or self:GetQuestTitle(qid) or ""
		if self:IsPlaceholderQuestTitle(qid, title) then
			title = ""
		end
		title = self:SafeTrimString(title, ""):gsub("[%c|]", "")
	end
	return {
		questID = qid,
		title = title,
		mapID = map,
		x = map > 0 and native.x or 0,
		y = map > 0 and native.y or 0,
		following = controller:IsActive() and state.following or "",
		sampledAt = self.GetAnnouncementServerTime and self:GetAnnouncementServerTime() or nil,
	}
end
-- Navigation is one owned state record; the coordinator supplies the shared
-- session, sequence and source timestamp used by presence and departure fencing.
function QT:SendPartyNavigationSnapshot(p, hello, routes, direct, completion)
	local state = self:GetPartyNavigationState()
	state.sequence = state.sequence + 1
	local sequence, signature = state.sequence, state.signature
	local record = {
		questID = p.questID,
		title = p.title or "",
		mapID = p.mapID,
		x = p.x or 0,
		y = p.y or 0,
		following = p.following or "",
		hello = hello == true,
	}
	return self:Publish("QTN2", record, routes, {
		owner = state,
		key = "party-navigation",
		expires = Now(self) + 15,
		direct = direct,
		sampledAt = p.sampledAt,
		isCurrent = function()
			return rawget(self, "partyNavigationState") == state
				and state.sequence == sequence
				and state.signature == signature
				and not self:IsRuntimeRestricted()
				and (record.questID == -1 or self:GetOption("sharePartyFocus") == true)
				and (record.mapID == -1 or self:GetOption("sharePartyWaypoint") == true)
		end,
		onComplete = completion,
	})
end
function QT:HandlePartyNavigationMessage(data, sender, context)
	if type(context) ~= "table" or context.distribution ~= self:GetPartyNavigationRoute() then
		return false
	end
	local name = Name(self, sender)
	if
		not name
		or self:IsSelfSender(name)
		or not self:IsGroupedSender(name)
		or self:IsIgnoredPlayerName(name)
		or type(data) ~= "table"
	then
		return false
	end
	local stamp, serverNow = Number(self, context.stamp, 1000000000, 99999999999), self:GetAnnouncementServerTime()
	if not stamp or not serverNow or stamp > serverNow + 1 or serverNow - stamp >= TTL then
		return false
	end
	local session, sequence = context.session, Number(self, context.sequence, 1, 1e12)
	if type(session) ~= "string" or #session > 64 or not session:match("^[%w%-]+$") or not sequence then
		return false
	end
	local qid, map = Number(self, data.questID, -1, 1000000000), Number(self, data.mapID, -1, 1000000)
	local x, y = self:SafeToNumber(data.x), self:SafeToNumber(data.y)
	if
		not qid
		or not map
		or not x
		or not y
		or x < 0
		or x > 1
		or y < 0
		or y > 1
		or (map <= 0 and (x ~= 0 or y ~= 0))
	then
		return false
	end
	local following, title = data.following or "", data.title or ""
	if following ~= "" then
		following = Name(self, following)
		if not following or not self:IsGroupedSender(following) or following == name then
			return false
		end
	end
	if type(title) ~= "string" or #title > 1024 or title:find("[%c|]") then
		return false
	end
	local s, now = self:GetPartyNavigationState(), Now(self)
	local observation = self:CreatePeerObservation(name, "QTN2", {
		source = "navigation",
		age = math.max(0, serverNow - stamp),
		lifetime = TTL,
		session = session,
		sequence = sequence,
		stamp = stamp,
	})
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	local record = {
		stamp = stamp,
		session = session,
		sequence = sequence,
		at = observation.sampledAt,
		questID = qid,
		title = title,
		mapID = map,
		x = x,
		y = y,
		following = following,
	}
	if not self:CommitPeerObservation(observation, record, true) then
		return false
	end
	s.peers[name], s.seen[name] = record, record
	if data.hello == true and (not s.lastReply or now - s.lastReply >= 2) then
		s.lastReply = now
		self:QueuePartyNavigationUpdate()
	end
	self:ApplyPartyQuestFocus()
	Changed(self)
	return true
end
function QT:ReconcilePartyQuestFollow()
	return self:GetPartyFocusController():Reconcile()
end
function QT:UpdatePartyNavigation()
	local s = self:GetPartyNavigationState()
	local route, now = self:GetPartyNavigationRoute(), Now(self)
	local fingerprint = (route or "") .. ":" .. self:GetPartyRosterFingerprint()
	if fingerprint ~= s.roster then
		s.roster, s.hello, s.nextSend = fingerprint, true, now + 0.25
		for name in pairs(s.seen) do
			if not route or not self:IsGroupedSender(name) then
				s.peers[name], s.seen[name] = nil, nil
			end
		end
		Changed(self)
	end
	for name, p in pairs(s.peers) do
		if now < p.at or now - p.at >= TTL or self:IsIgnoredPlayerName(name) then
			s.peers[name] = nil
			Changed(self)
		end
	end
	self:ReconcilePartyQuestFollow()
	if not route then
		return
	end
	if self:IsRuntimeRestricted() then
		return
	end
	local p = self:SamplePartyNavigation()
	if not p then
		return
	end
	self:ApplyPartyQuestFocus()
	-- Applying follow can change both the native selection and published intent.
	p = self:SamplePartyNavigation() or p
	local signature = table.concat({ p.questID, p.mapID, p.x, p.y, p.following, p.title }, "|")
	if signature ~= s.signature then
		s.signature, s.localState = signature, p
		self:QueuePartyNavigationUpdate()
		Changed(self)
	end
	local due = s.dirtyAt and math.min(s.dirtyAt, s.nextSend) or s.nextSend
	if now < due then
		return
	end
	if s.pending and s.pending.signature == signature then
		return
	end
	local pending = { signature = signature }
	s.pending = pending
	local admitted = self:SendPartyNavigationSnapshot(
		p,
		s.hello,
		{ { distribution = route, requiresGroup = true } },
		false,
		function(sent)
			if rawget(self, "partyNavigationState") ~= s or s.pending ~= pending then
				return
			end
			s.pending = nil
			if sent and s.signature == signature then
				s.hello, s.dirtyAt, s.nextSend = false, nil, Now(self) + self.API.Random(28, 32)
			else
				if s.signature == signature then
					s.dirtyAt = nil
				end
				s.nextSend = Now(self) + 2
			end
		end
	)
	if not admitted and s.pending == pending then
		s.pending, s.dirtyAt, s.nextSend = nil, nil, now + 2
	end
end
function QT:ResetPartyNavigation()
	self:StopPartyQuestFollow()
	self:ClearPartyFocusMissingNotice()
	local state = rawget(self, "partyNavigationState")
	self.partyNavigationState = nil
	if state then
		self:CancelTransportOwner(state)
	end
	if self.HidePartyWaypointPins then
		self:HidePartyWaypointPins()
	end
end
function QT:WithdrawPartyNavigation()
	local route = self:GetPartyNavigationRoute()
	if not route or self:IsRuntimeRestricted() then
		return
	end
	self:SendPartyNavigationSnapshot(
		{ questID = -1, mapID = -1, x = 0, y = 0 },
		false,
		{ { distribution = route, requiresGroup = true } }
	)
end
function QT:GetPartyQuestFocusID(name)
	if self:IsSelfSender(name) then
		if self:IsRuntimeRestricted() then
			return nil
		end
		local ok, native = pcall(self.API.GetPartyNavigationNativeState)
		return ok and self:CanAccessTable(native) and Number(self, native.questID, -1, 1000000000) or nil
	end
	local peer = self:GetPartyNavigationPeer(name)
	return peer and peer.questID or nil
end
function QT:GetPartyQuestFollowTarget()
	return self:GetPartyFocusController():GetTarget()
end
function QT:RequestPartyQuestFocus(name, questID)
	return self:GetPartyFocusController():Request(name, questID)
end
function QT:SelectPartyQuestFocus(name, questID)
	return self:GetPartyFocusController():Select(name, questID)
end

function QT:GetPartyFocusLabel(name)
	local p
	if self:IsSelfSender(name) then
		-- Own navigation is local UI state, not a received/shared snapshot. In
		-- particular, being solo or disabling sharing must not hide our focus.
		if self:IsRuntimeRestricted() then
			return L("Waiting for restrictions")
		end
		local ok, native = pcall(self.API.GetPartyNavigationNativeState)
		local id = ok and self:CanAccessTable(native) and Number(self, native.questID, -1, 1000000000)
		if not id or id < 0 then
			return L("Focus unavailable")
		end
		p = { questID = id, title = id > 0 and self:GetQuestTitle(id) or "" }
	else
		p = self:GetPartyNavigationPeer(name)
	end
	if not p then
		local state = rawget(self, "partyNavigationState")
		if state and state.seen[name] then
			return L("Focus data expired")
		end
		local version = self:GetPlayerAddonVersion(name)
		if version and self:CompareAddonVersions(version, "6.3.0") == -1 then
			return L("Quest focus unsupported")
		end
		return L("Waiting for quest focus")
	end
	if p.questID < 0 then
		return L("Focus not shared or unavailable")
	end
	if p.questID == 0 then
		return L("No focused quest")
	end
	return self:GetLocalizedQuestTitle(p.questID) or (p.title ~= "" and p.title) or (L("Quest ") .. p.questID)
end
function QT:PopulatePartyFocusMenu(root, name)
	if
		not self:GetPartyNavigationRoute()
		or not self:IsGroupedSender(name)
		or self:IsSelfSender(name)
		or self:IsIgnoredPlayerName(name)
	then
		return
	end
	local s = rawget(self, "partyNavigationState")
	local following = s and s.following == self:NormalizeMemberName(name)
	local p = self:GetPartyNavigationPeer(name)
	local button = root:CreateButton(following and L("Stop following") or L("Follow quest focus"), function()
		if following then
			self:StopPartyQuestFollow()
		else
			self:FollowPartyQuestFocus(name)
		end
	end)
	if button and button.SetEnabled then
		button:SetEnabled(following or (p ~= nil and p.questID >= 0 and not self:WouldPartyQuestFollowCycle(name)))
	end
	root:CreateTitle(self:GetPartyFocusLabel(name))
	if not following and p and self:WouldPartyQuestFollowCycle(name) then
		root:CreateTitle(L("Following would create a loop"))
	end
	local session = self.partyQuestCompareSession
	local member = session and session.byName[name]
	local entry = p and member and member.entries and member.entries[p.questID]
	if entry and entry.isPushable and member.supportsShareRequests and self.API.IsOnQuest(p.questID) == false then
		root:CreateButton(L("Request Share"), function()
			self:RequestPartyQuestShare(p.questID, name)
		end)
	end
end
function QT:GetPartyWaypointRows()
	local rows = {}
	if self:GetOption("showPartyWaypoints") ~= true then
		return rows
	end
	for _, name in ipairs(self.partyMemberOrder or {}) do
		local p = not self:IsSelfSender(name) and self:GetPartyNavigationPeer(name)
		if p and p.mapID > 0 then
			rows[#rows + 1] =
				{ name = name, mapID = p.mapID, x = p.x, y = p.y, classFile = self:GetGroupedSenderClassFile(name) }
		end
	end
	return rows
end
function QT:NavigateToPartyWaypoint(name)
	local p = self:GetPartyNavigationPeer(name)
	if not p or p.mapID <= 0 or self:IsRuntimeRestricted() then
		return false
	end
	self:StopPartyQuestFollow()
	return self:OpenPingWaypoint(p.mapID, p.x * 100, p.y * 100)
end

function QT:GetPartyFollowingText()
	local s = rawget(self, "partyNavigationState")
	if not s or not s.following then
		return ""
	end
	return string.format(L("Following: %s"), s.following) .. (s.followStatus and ("\n" .. s.followStatus) or "")
end
