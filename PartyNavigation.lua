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
	if type(db) ~= "table" or type(db.global) ~= "table" or type(owner) ~= "string" then return nil end
	if type(db.global.partyQuestFollowByCharacter) ~= "table" then db.global.partyQuestFollowByCharacter = {} end
	return db.global.partyQuestFollowByCharacter, owner
end
function QT:SavePartyQuestFollow(name)
	local store, owner = FollowStore(self)
	if store then store[owner] = name and Name(self, name) or nil end
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
		elseif store then store[owner] = nil end
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
	self:SavePartyQuestFollow(nil)
	local s = rawget(self, "partyNavigationState")
	if not s or not s.following then
		return false
	end
	s.following, s.expectedQuest, s.attempt, s.followStatus, s.checkExternal, s.resuming = nil, nil, nil, nil, nil, nil
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
	s.checkExternal, s.resuming = nil, nil
	s.followToken = {}
	self:SavePartyQuestFollow(name)
	self:ClearPartyFocusMissingNotice()
	self:QueuePartyNavigationUpdate()
	self:ApplyPartyQuestFocus()
	Changed(self)
	return true
end
function QT:ApplyPartyQuestFocus()
	if self.IsPartyQuestCompareNavigationPreviewActive and self:IsPartyQuestCompareNavigationPreviewActive() then return end
	local s = rawget(self, "partyNavigationState")
	if not s or not s.following then
		return
	end
	if not self:IsGroupedSender(s.following) or self:IsIgnoredPlayerName(s.following)
		or (self.API.IsInRaid and self.API.IsInRaid()) or self:WouldPartyQuestFollowCycle(s.following) then
		self:StopPartyQuestFollow()
		return
	end
	local p = self:GetPartyNavigationPeer(s.following)
	if not p or p.questID < 0 then
		local status = p and L("Focus not shared or unavailable") or L("Waiting for quest focus")
		if s.followStatus ~= status then s.followStatus = status; Changed(self) end
		return
	end
	if self:IsRuntimeRestricted() then
		return
	end
	if s.resuming then
		self:SamplePartyNavigation()
		if s.resuming then return end
	end
	-- Resolve a native navigation change before an arriving peer can overwrite it.
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
		if owned == false then
			local name = s.following
			self:StopPartyQuestFollow()
			self:QueuePartyFocusMissingNotice(name, p.questID, p.title)
			return
		elseif owned ~= true then
			return
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
	if self.IsPartyQuestCompareNavigationPreviewActive and self:IsPartyQuestCompareNavigationPreviewActive() then
		self:QueuePartyNavigationUpdate()
		Changed(self)
		return
	end
	local s = rawget(self, "partyNavigationState")
	if s and s.following and not s.applying and not s.resuming then
		-- Defer unreadable observations, never treat an inaccessible quest as a
		-- deliberate clear. The update loop revisits it after restrictions end.
		s.checkExternal = true
	end
	self:QueuePartyNavigationUpdate()
	-- Local PQL focus buttons update even without a party transport route.
	Changed(self)
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
	local previewActive = self.IsPartyQuestCompareNavigationPreviewActive and self:IsPartyQuestCompareNavigationPreviewActive()
	-- Establish a local baseline during reload, independently of peer arrival.
	-- Later manual changes still win while waiting for fresh remote state.
	if s.resuming and not previewActive and native.questID >= 0 then
		s.expectedQuest, s.resuming = native.questID, nil
	end
	if s.checkExternal and not previewActive and native.questID >= 0 then
		s.checkExternal = nil
		if s.following and native.questID >= 0 then
			if native.questID ~= s.expectedQuest then
				-- Native tracker events arrive after selection. Restore our last
				-- followed focus before asking; never replace Blizzard callbacks.
				local previous = Number(self, s.expectedQuest, 0, 1000000000)
				if previous and (native.questID > 0 or native.questCleared == true) then
					if self:IsWorkBlocked("foreign_frame_mutation") then
						s.checkExternal = true
						return nil
					end
					s.applying = true
					local restored, applied = pcall(self.API.SetPartyNavigationQuest, previous)
					s.applying = nil
					if restored and applied == true then
						self:RequestPartyQuestFocus(self:GetPlayerFullName(), native.questID)
						return self:SamplePartyNavigation()
					end
				end
				-- Other navigation (waypoints, etc.) or a failed restoration wins.
				-- Stop rather than repeatedly fighting a rejected native setter.
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
		following = not previewActive and s.following or "",
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
function QT:ReconcilePartyQuestFollow()
	local s = rawget(self, "partyNavigationState")
	if not s or not s.following or self.isLoggingOut then return end
	if (self.API.IsInRaid and self.API.IsInRaid()) or (self.API.IsInParty and not self.API.IsInParty())
		or not self:IsGroupedSender(s.following) or self:IsIgnoredPlayerName(s.following) then
		self:StopPartyQuestFollow()
	end
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
	local wire = self:EncodePartyNavigation({ questID = -1, mapID = -1, x = 0, y = 0 }, false)
	if wire then
		self:SendWireMessageToAnnouncementRoutes(
			wire,
			"party navigation clear",
			{ { distribution = route, requiresGroup = true } }
		)
	end
end
function QT:GetPartyQuestFocusID(name)
	if self:IsSelfSender(name) then
		if self:IsRuntimeRestricted() then return nil end
		local ok, native = pcall(self.API.GetPartyNavigationNativeState)
		return ok and self:CanAccessTable(native) and Number(self, native.questID, -1, 1000000000) or nil
	end
	local peer = self:GetPartyNavigationPeer(name)
	return peer and peer.questID or nil
end
function QT:GetPartyQuestFollowTarget()
	local state = rawget(self, "partyNavigationState")
	if state and state.following then return state.following, state.followToken end
end
-- Capture the choice, not a pooled row/button. Confirming an obsolete dialog
-- must never cancel a newer follow, even if it targets the same player again.
function QT:RequestPartyQuestFocus(name, questID)
	if self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local following, token = self:GetPartyQuestFollowTarget()
	local choice = {}
	self.partyFocusChangeToken = choice
	if following and following ~= name then
		return self:ShowPartyFocusChangeDialog(following, function()
			local current, currentToken = self:GetPartyQuestFollowTarget()
			if current ~= following or currentToken ~= token or self.partyFocusChangeToken ~= choice then return false end
			if rawget(self, "partyNavigationState") then self:ReconcilePartyQuestFollow() end
			if self:GetPartyQuestFollowTarget() ~= following then return false end
			return self:SelectPartyQuestFocus(name, questID)
		end)
	end
	return self:SelectPartyQuestFocus(name, questID)
end
function QT:SelectPartyQuestFocus(name, questID)
	if self:IsRuntimeRestricted() then return false end
	if self:IsSelfSender(name) then
		if questID ~= 0 and self.API.IsOnQuest(questID) ~= true then return false end
		local s = rawget(self, "partyNavigationState")
		if s then s.applying = true end
		local ok, applied = pcall(self.API.SetPartyNavigationQuest, questID)
		if s then s.applying = nil end
		if ok and applied == true then
			self:StopPartyQuestFollow()
			self:OnPartyNavigationTrackingChanged()
			return true
		end
		return false
	end
	if self:GetPartyQuestFocusID(name) ~= questID then return false end
	return self:FollowPartyQuestFocus(name)
end

function QT:GetPartyFocusLabel(name)
	local p
	if self:IsSelfSender(name) then
		-- Own navigation is local UI state, not a received/shared snapshot. In
		-- particular, being solo or disabling sharing must not hide our focus.
		if self:IsRuntimeRestricted() then return L("Waiting for restrictions") end
		local ok, native = pcall(self.API.GetPartyNavigationNativeState)
		local id = ok and self:CanAccessTable(native) and Number(self, native.questID, -1, 1000000000)
		if not id or id < 0 then return L("Focus unavailable") end
		p = { questID = id, title = id > 0 and self:GetQuestTitle(id) or "" }
	else
		p = self:GetPartyNavigationPeer(name)
	end
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
