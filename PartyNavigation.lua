-- One small-party snapshot owns focus, native waypoint and follow intent.
-- No public-channel traffic, per-feature timers, or persistent follow state.
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
	local s = rawget(self, "partyNavigationState")
	if not s or not s.following then
		return false
	end
	s.following, s.expectedQuest, s.attempt, s.followStatus, s.checkExternal = nil, nil, nil, nil, nil
	self:QueuePartyNavigationUpdate()
	Changed(self)
	return true
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
function QT:WouldPartyQuestFollowCycle(name)
	local seen = {}
	for _ = 1, 5 do
		if self:IsSelfSender(name) or seen[name] then
			return true
		end
		seen[name] = true
		local p = self:GetPartyNavigationPeer(name)
		if not p or not p.following or p.following == "" then
			return false
		end
		name = p.following
	end
	return true
end
function QT:FollowPartyQuestFocus(name)
	name = Name(self, name)
	local p = name and self:GetPartyNavigationPeer(name)
	if
		self:IsRuntimeRestricted()
		or not p
		or p.questID < 0
		or self:IsSelfSender(name)
		or self:WouldPartyQuestFollowCycle(name)
	then
		return false
	end
	local s = self:GetPartyNavigationState()
	s.following, s.attempt, s.expectedQuest = name, nil, self.API.GetActiveTrackedQuestID() or 0
	s.checkExternal = nil
	self:QueuePartyNavigationUpdate()
	self:ApplyPartyQuestFocus()
	Changed(self)
	return true
end
function QT:ApplyPartyQuestFocus()
	local s = rawget(self, "partyNavigationState")
	if not s or not s.following then
		return
	end
	local p = self:GetPartyNavigationPeer(s.following)
	if not p or p.questID < 0 or self:WouldPartyQuestFollowCycle(s.following) then
		self:StopPartyQuestFollow()
		return
	end
	if self:IsRuntimeRestricted() then
		return
	end
	-- Manual navigation wins even if a peer packet arrives before the next tick.
	if s.checkExternal then
		self:SamplePartyNavigation()
		if not s.following or s.checkExternal then
			return
		end
	end
	local previousStatus = s.followStatus
	local status
	if p.questID == 0 then
		status, s.attempt = L("No focused quest"), nil
	else
		local owned = self.API.IsOnQuest(p.questID)
		if owned ~= true then
			status, s.attempt = L("You don't have this quest"), nil
		elseif self.API.GetActiveTrackedQuestID() == p.questID then
			s.attempt, s.expectedQuest = p.questID, p.questID
		else
			if s.attempt ~= p.questID then
				s.attempt, s.expectedQuest = p.questID, p.questID
				s.applying = true
				local ok, applied = pcall(self.API.SetPartyNavigationQuest, p.questID)
				s.applying = nil
				if not ok or applied ~= true then
					s.expectedQuest = nil
					s.followStatus = L("Unable to track this quest")
				else
					s.followStatus = nil
					self:QueuePartyNavigationUpdate()
				end
			end
			status = s.followStatus
		end
	end
	if previousStatus ~= status then
		s.followStatus = status
		Changed(self)
	end
end
function QT:OnPartyNavigationTrackingChanged()
	local s = rawget(self, "partyNavigationState")
	if s and s.following and not s.applying then
		-- Defer unreadable observations, never treat an inaccessible quest as a
		-- deliberate clear. The update loop revisits it after restrictions end.
		s.checkExternal = true
	end
	self:QueuePartyNavigationUpdate()
end
function QT:SamplePartyNavigation()
	if self:IsRuntimeRestricted() then
		return nil
	end
	local ok, native = pcall(self.API.GetPartyNavigationNativeState)
	if not ok or not self:CanAccessTable(native) then
		return nil
	end
	local s = self:GetPartyNavigationState()
	if s.checkExternal and native.questID >= 0 then
		s.checkExternal = nil
		if s.following and native.questID >= 0 then
			if native.questID ~= s.expectedQuest then
				self:StopPartyQuestFollow()
			end
		end
	end
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
		following = s.following or "",
	}
end
function QT:EncodePartyNavigation(p, hello)
	local s = self:GetPartyNavigationState()
	local prefix = string.format(
		"QTNAV|1,%s,%d,%d,%d,%d,%d,%d,%s,",
		s.session,
		s.sequence,
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
function QT:HandlePartyNavigationMessage(payload, sender, route)
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
		or #payload > 249
	then
		return false
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
	local retired = s.retired[name] or {}
	local prior = s.peers[name] or s.seen[name]
	if retired[session] or (prior and prior.session == session and seq <= prior.sequence) then
		return false
	end
	if prior and prior.session ~= session then
		retired[prior.session] = now
		s.retired[name] = retired
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
	s.peers[name] = {
		session = session,
		sequence = seq,
		at = now,
		questID = qid,
		title = title,
		mapID = map,
		x = x / 10000,
		y = y / 10000,
		following = following,
	}
	s.seen[name] = s.peers[name]
	if hello == "1" and (not s.lastReply or now - s.lastReply >= 2) then
		s.lastReply = now
		self:QueuePartyNavigationUpdate()
	end
	self:RecordQTPlayerPresence(name, true)
	self:ApplyPartyQuestFocus()
	Changed(self)
	return true
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
	if s.following and not self:GetPartyNavigationPeer(s.following) then
		self:StopPartyQuestFollow()
	end
	if not route then
		self:StopPartyQuestFollow()
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
	local wire = self:EncodePartyNavigation(p, s.hello)
	local sent = wire
		and self:SendWireMessageToAnnouncementRoutes(
			wire,
			"party navigation",
			{ { distribution = route, requiresGroup = true } }
		)
	if sent then
		s.hello, s.dirtyAt, s.nextSend = false, nil, now + self.API.Random(28, 32)
	else
		-- Retry the latest state through the common token bucket, never enqueue
		-- obsolete snapshots behind newer focus/waypoint edits.
		s.dirtyAt, s.nextSend = nil, now + 2
	end
end
function QT:ResetPartyNavigation()
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
	local wire = self:EncodePartyNavigation({ questID = -1, mapID = -1, x = 0, y = 0 }, false)
	if wire then
		self:SendWireMessageToAnnouncementRoutes(
			wire,
			"party navigation clear",
			{ { distribution = route, requiresGroup = true } }
		)
	end
end
function QT:GetPartyFocusLabel(name)
	local p = self:GetPartyNavigationPeer(name)
	if not p then
		local state = rawget(self, "partyNavigationState")
		if state and state.seen[name] then return L("Focus data expired") end
		local version = self:GetPlayerAddonVersion(name)
		if version and self:CompareAddonVersions(version, "6.3.0") == -1 then return L("Quest focus unsupported") end
		return L("Waiting for quest focus")
	end
	if p.questID < 0 then return L("Focus not shared or unavailable") end
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
