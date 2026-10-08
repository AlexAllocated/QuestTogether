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
			retired = {},
			sequence = 0,
			hello = true,
			session = string.format(
				"%d-%d",
				math.floor(Now(self) * 1000),
				self.API.Random and self.API.Random(1000, 999999) or 1000
			),
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
function QT:EncodePartyNavigation(p, hello, modern)
	local s = self:GetPartyNavigationState()
	local header = modern and ("QTN2|1," .. modern.sampledAt .. ",") or "QTNAV|1,"
	local prefix = header
		.. string.format(
			"%s,%d,%d,%d,%d,%d,%d,%s,",
			modern and modern.session or s.session,
			modern and modern.sequence or s.sequence,
			hello and 1 or 0,
			p.questID,
			p.mapID,
			math.floor(p.x * 10000 + 0.5),
			math.floor(p.y * 10000 + 0.5),
			p.following or ""
		)
	local title = self:EscapePayload(p.title or "")
	if #prefix + #title > 255 then
		title = ""
	end
	return #prefix <= 255 and prefix .. title or nil
end
-- Modern navigation shares the public envelope clock/counter. Its sequence is
-- therefore comparable with a QTB1 goodbye even when both occur in one second.
-- Keep the legacy companion until older party members upgrade.
function QT:SendPartyNavigationSnapshot(p, hello, routes, direct)
	local state, geographic = self:GetPartyNavigationState(), rawget(self, "geographicCommsState")
	local sampledAt = p.sampledAt or (self.GetAnnouncementServerTime and self:GetAnnouncementServerTime())
	local modernSent = false
	if geographic and geographic.session and sampledAt then
		geographic.sequence = geographic.sequence + 1
		state.modernSession, state.modernSequence = geographic.session, geographic.sequence
		local modern = self:EncodePartyNavigation(p, hello, {
			session = geographic.session,
			sequence = geographic.sequence,
			sampledAt = sampledAt,
		})
		if modern then
			modernSent = self:SendWireMessageToAnnouncementRoutes(modern, "party navigation snapshot", routes, direct)
		end
	end
	local wire = self:EncodePartyNavigation(p, hello)
	local legacySent = wire and self:SendWireMessageToAnnouncementRoutes(wire, "party navigation", routes, direct)
	return modernSent or legacySent or false
end
function QT:HandlePartyNavigationMessage(payload, sender, route, modern)
	if route ~= self:GetPartyNavigationRoute() then
		return false
	end
	local name = Name(self, sender)
	if
		not name
		or self:IsSelfSender(name)
		or not self:IsGroupedSender(name)
		or self:IsIgnoredPlayerName(name)
		or type(payload) ~= "string"
		or #payload > (modern and 250 or 249)
	then
		return false
	end
	local stamp, sampledAt
	if modern then
		local rawStamp, rest = payload:match("^1,(%d+),(.*)$")
		stamp = Number(self, rawStamp, 1000000000, 99999999999)
		local serverNow = self.GetAnnouncementServerTime and self:GetAnnouncementServerTime()
		if not stamp or not serverNow or stamp > serverNow + 5 or serverNow - stamp >= TTL then
			return false
		end
		sampledAt, payload = Now(self) - math.max(0, serverNow - stamp), "1," .. rest
	end
	local session, seq, hello, qid, map, x, y, following, title =
		payload:match("^1,(%d+%-%d+),(%d+),([01]),(-?%d+),(-?%d+),(%d+),(%d+),([^,]*),([^,]*)$")
	if not session or #session > 32 then
		return false
	end
	seq, qid, map = Number(self, seq, 1, 2147483647), Number(self, qid, -1, 1000000000), Number(self, map, -1, 1000000)
	x, y = Number(self, x, 0, 10000), Number(self, y, 0, 10000)
	if not seq or not qid or not map or not x or not y or (map <= 0 and (x ~= 0 or y ~= 0)) then
		return false
	end
	title = self:UnescapePayload(title)
	if following ~= "" then
		following = Name(self, following)
		if not following or not self:IsGroupedSender(following) or following == name then
			return false
		end
	end
	if #title > 200 or title:find("[%c|]") then
		return false
	end
	local s, now = self:GetPartyNavigationState(), Now(self)
	local retired = {}
	for old, at in pairs(s.retired[name] or {}) do
		if now >= at and now - at <= TTL then
			retired[old] = at
		end
	end
	local prior = s.peers[name] or s.seen[name]
	local observation = self:CreatePeerObservation(name, modern and "QTN2" or "QTNAV", {
		source = modern and "navigation" or "legacy",
		age = modern and now - sampledAt or 0,
		lifetime = TTL,
		session = modern and session or ("QTNAV:" .. session),
		sequence = seq,
		stamp = stamp,
	})
	if not self:CanAcceptPeerObservation(observation) then
		return false
	end
	if modern then
		if prior and prior.modern and stamp < prior.stamp then
			return false
		end
	else
		-- Once the peer supports stamped navigation, a delayed legacy companion
		-- must never become a fallback after its modern snapshot or a departure.
		if (prior and prior.modern) or not self:CanRecordPeerPresence(name) then
			return false
		end
	end
	if
		retired[session]
		or (prior and prior.modern == (modern == true) and prior.session == session and seq <= prior.sequence)
	then
		return false
	end
	if prior and prior.modern == (modern == true) and prior.session ~= session then
		retired[prior.session] = now
	end
	for key, at in pairs(retired) do
		if now - at > TTL then
			retired[key] = nil
		end
	end
	local count = 0
	for _ in pairs(retired) do
		count = count + 1
	end
	if count > 8 then
		return false
	end
	local record = {
		modern = modern == true,
		stamp = stamp,
		session = session,
		sequence = seq,
		at = modern and sampledAt or now,
		questID = qid,
		title = title,
		mapID = map,
		x = x / 10000,
		y = y / 10000,
		following = following,
	}
	if not self:CommitPeerObservation(observation, record, true) then
		return false
	end
	s.retired[name], s.peers[name] = retired, record
	s.seen[name] = record
	if hello == "1" and (not s.lastReply or now - s.lastReply >= 2) then
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
				s.peers[name], s.retired[name], s.seen[name] = nil, nil, nil
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
	s.sequence = s.sequence + 1
	local sent = self:SendPartyNavigationSnapshot(p, s.hello, { { distribution = route, requiresGroup = true } })
	if sent then
		s.hello, s.dirtyAt, s.nextSend = false, nil, now + self.API.Random(28, 32)
	else
		-- Retry the latest state through the common token bucket, never enqueue
		-- obsolete snapshots behind newer focus/waypoint edits.
		s.dirtyAt, s.nextSend = nil, now + 2
	end
end
function QT:ResetPartyNavigation()
	self:StopPartyQuestFollow()
	self:ClearPartyFocusMissingNotice()
	self.partyNavigationState = nil
	if self.HidePartyWaypointPins then
		self:HidePartyWaypointPins()
	end
end
function QT:WithdrawPartyNavigation()
	local route = self:GetPartyNavigationRoute()
	if not route or self:IsRuntimeRestricted() then
		return
	end
	local s = self:GetPartyNavigationState()
	s.sequence = s.sequence + 1
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

function QT:IsPartyNavigationQueuedWireCurrent(wire)
	local modern = wire:sub(1, 5) == "QTN2|"
	if not modern and wire:sub(1, 6) ~= "QTNAV|" then
		return true
	end
	local session, sequence, questID, mapID
	if modern then
		session, sequence, questID, mapID = wire:match("^QTN2|1,%d+,([^,]+),(%d+),%d+,(-?%d+),(-?%d+),")
	else
		session, sequence, questID, mapID = wire:match("^QTNAV|1,([^,]+),(%d+),%d+,(-?%d+),(-?%d+),")
	end
	local state = rawget(self, "partyNavigationState")
	return state
			and session == (modern and state.modernSession or state.session)
			and tonumber(sequence) == (modern and state.modernSequence or state.sequence)
			and (tonumber(questID) == -1 or self:GetOption("sharePartyFocus") == true)
			and (tonumber(mapID) == -1 or self:GetOption("sharePartyWaypoint") == true)
		or false
end

QT:RegisterCommSendPolicy("QTNAV", function(addon, wire, route, options)
	options.key = "party-navigation:QTNAV:" .. route.distribution .. ":" .. (route.target or "")
	options.isCurrent = function()
		return addon:IsPartyNavigationQueuedWireCurrent(wire)
	end
end)
QT:RegisterCommSendPolicy("QTN2", function(addon, wire, route, options)
	options.key = "party-navigation:QTN2:" .. route.distribution .. ":" .. (route.target or "")
	options.isCurrent = function()
		return addon:IsPartyNavigationQueuedWireCurrent(wire)
	end
end)
