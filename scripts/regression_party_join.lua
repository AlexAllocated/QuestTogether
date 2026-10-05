-- Private peers and adapters only; no live Blizzard globals are replaced.
local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function Peer(name)
	local a = setmetatable({
		name = name or "Me-Realm",
		now = 100,
		grouped = true,
		count = 2,
		isEnabled = true,
		options = {},
		messages = {},
		wire = {},
		invites = {},
		partyMembers = {},
		recentCommMessageSignatures = {},
		workState = { entries = {}, generations = {} },
		announcementChannelName = "QuestTogether",
		announcementChannelLocalID = 7,
		channelRequestSequence = 0,
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.now
		end,
		Random = function()
			return 1234
		end,
		GetRealmName = function()
			return "Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return a.regional == true
		end,
		GetPartyJoinInfo = function()
			if a.unknown then
				return nil
			end
			return a.grouped == true, a.canInvite ~= false, a.count or 0,
				a.grouped == true and (a.count or 0) >= 2 and (a.count or 0) < 5 and not a.unsupported
		end,
		GetPartyJoinLeaderUnit = function() return a.leaderUnit end,
		IsPartyJoinFriend = function(n)
			return a.friend == n
		end,
		InviteUnit = function(n)
			a.invites[#a.invites + 1] = n
			return not a.inviteFails
		end,
		IsOnIgnoredList = function(n)
			return n == a.ignored
		end,
		GetChannelName = function()
			return 7
		end,
	}
	function a:GetPlayerFullName()
		return self.name
	end
	function a:GetPlayerName()
		return self.name
	end
	function a:GetOption(key)
		return self.options[key]
	end
	function a:SetOption(key, value)
		self.options[key] = value
		return true
	end
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	function a:IsGroupedSender(n)
		return self.partyMembers[n] ~= nil
	end
	function a:RefreshQTPlayerPlatePresence() end
	function a:RefreshOptionsWindow() end
	function a:Print(m)
		self.messages[#self.messages + 1] = m
	end
	function a:Debug() end
	function a:Debugf() end
	function a:RecordCommsDiagnostic() end
	function a:ScheduleDeferredWork(_, _, callback)
		if not self.blocked then
			callback()
		end
	end
	function a:RenderPartyJoinPrompt()
		self.rendered = self:GetNextPartyJoinRequest()
	end
	function a:SendWireMessageToAnnouncementRoutes(wire)
		self.wire[#self.wire + 1] = wire
		if self.sendFails then
			return false
		end
		if self.other then
			self.other:OnCommReceived(self.commPrefix, wire, "CHANNEL", self.name, 7, "QuestTogether")
		end
		return true
	end
	return a
end
local function Request(a, sender, id)
	return a:HandlePartyJoinMessage(
		"1," .. (id or "req-1") .. "," .. a:EscapePayload(a.name) .. ",request",
		sender or "Friend-Realm"
	)
end

QT:RegisterTest("join control messages use only the route that can reach their recipient", function()
	local a = Peer()
	function a:GetGroupAnnouncementDistribution() return "PARTY" end
	function a:SendWireMessageToAnnouncementRoutes(_, _, routes) self.routes = routes; return true end
	assert(a:SendPartyJoinMessage("Outside-Realm", "req-1", "pending"))
	Equal(#a.routes, 1)
	Equal(a.routes[1].distribution, "CHANNEL")
	Equal(a.routes[1].channelName, "QuestTogether")
	a.partyMembers["Member-Realm"] = {}
	assert(a:SendPartyJoinMessage("Member-Realm", "req-2", "unavailable"))
	Equal(#a.routes, 1)
	Equal(a.routes[1].distribution, "PARTY")
end)
local function Pair()
	local a, b = Peer("Requestor-Realm"), Peer("Host-Realm")
	a.other, b.other, a.grouped, a.count = b, a, false, 0
	b:BroadcastPartyJoinMetadata()
	return a, b
end

QT:RegisterTest("party join metadata is bounded fresh ordered and independent of location sharing", function()
	local a = Peer()
	Equal(a:HandlePartyJoinMetadata("1,session,2,1,1", "Friend-Realm"), true)
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), true)
	Equal(a:IsKnownQTPlayer("Friend-Realm"), true)
	Equal(a:HandlePartyJoinMetadata("1,session,1,0,0", "Friend-Realm"), false)
	a.now = 225
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), false)
	a:PrunePartyJoin()
	Equal(next(a.partyJoinState.peers), nil)
	for _, payload in ipairs({ "1,s,0,1,1", "1,s,1,3,1", "1,s,1,1,2", "1,s,1,1,1,junk", "1,s,999999999999,1,1" }) do
		Equal(a:HandlePartyJoinMetadata(payload, "Friend-Realm"), false)
	end
	for i = 1, 520 do
		a:HandlePartyJoinMetadata("1,s,1,1,1", "Peer" .. i .. "-Realm")
	end
	local count = 0
	for _ in pairs(a.partyJoinState.peers) do
		count = count + 1
	end
	Equal(count, 512)
end)

QT:RegisterTest("party metadata advertises transitions with bounded cadence and failed-send retries", function()
	local a = Peer()
	a.grouped, a.count = false, 0
	Equal(a:BroadcastPartyJoinMetadata(), true)
	Equal(a.wire[1]:match(",0,1$") ~= nil, true)
	a.grouped, a.count, a.now = true, 2, 102
	Equal(a:BroadcastPartyJoinMetadata(), false)
	a.now = 105
	Equal(a:BroadcastPartyJoinMetadata(), true)
	a.now = 164
	Equal(a:BroadcastPartyJoinMetadata(), false)
	a.now = 165
	Equal(a:BroadcastPartyJoinMetadata(), true)
	a.now, a.canInvite, a.sendFails = 170, false, true
	Equal(a:BroadcastPartyJoinMetadata(), false)
	a.now = 171
	Equal(a:BroadcastPartyJoinMetadata(), false)
	a.now, a.sendFails = 175, false
	Equal(a:BroadcastPartyJoinMetadata(), true)
	a.blocked = true
	a.now = 250
	Equal(a:BroadcastPartyJoinMetadata(), false)
end)

QT:RegisterTest("join request uses authenticated two-peer transport and asks before inviting", function()
	local a, b = Pair()
	Equal(a:RequestPartyJoin(b.name), true)
	Equal(#b.invites, 0)
	local request = b:GetNextPartyJoinRequest()
	Equal(request.sender, a.name)
	Equal(a.partyJoinState.outgoing.pending, true)
	Equal(b:ConfirmPartyJoin(request, true, false, false), true)
	Equal(b.invites[1], a.name)
	Equal(b:GetOption("autoInviteFriends"), true)
	Equal(a.partyJoinState.outgoing, nil)
	Equal(b:GetNextPartyJoinRequest(), nil)
	Equal(b:ConfirmPartyJoin(request, false, true, false), false)
	Equal(#b.invites, 1)
end)

QT:RegisterTest("join requests default to consent and LFG alone never auto-invites", function()
	Equal(QT.DEFAULTS.profile.autoInviteFriends, false)
	Equal(QT.DEFAULTS.profile.autoInviteWhileLFG, false)
	local a = Peer()
	a.options.lookingForQuestPartners = true
	Equal(Request(a), true)
	Equal(#a.invites, 0)
end)

QT:RegisterTest("join auto-approval uses current local friendship or enabled LFG preference", function()
	for _, scenario in ipairs({ "friend", "stranger", "lfg", "lfgOff", "optionOff", "friendError" }) do
		local a = Peer()
		a.options.autoInviteFriends, a.options.autoInviteWhileLFG = true, true
		if scenario == "friend" then
			a.friend = "Friend-Realm"
		elseif scenario == "lfg" then
			a.options.lookingForQuestPartners = true
		elseif scenario == "optionOff" then
			a.friend = "Friend-Realm"
			a.options.autoInviteFriends = false
		elseif scenario == "friendError" then
			a.API.IsPartyJoinFriend = function()
				error("unavailable")
			end
		end
		Equal(Request(a), true)
		Equal(#a.invites, (scenario == "friend" or scenario == "lfg") and 1 or 0)
	end
end)

QT:RegisterTest("failed automatic invitation falls back to one manual prompt without retry", function()
	local a = Peer()
	a.friend, a.options.autoInviteFriends, a.inviteFails = "Friend-Realm", true, true
	Equal(Request(a), true)
	Equal(#a.invites, 1)
	assert(a:GetNextPartyJoinRequest())
	a:UpdatePartyJoin()
	Equal(#a.invites, 1)
	local request = a:GetNextPartyJoinRequest()
	a.inviteFails = false
	Equal(a:ConfirmPartyJoin(request, false, false, false), true)
	Equal(#a.invites, 2)
end)

QT:RegisterTest("stale join confirmations cannot invite or save consent", function()
	for _, scenario in ipairs({
		"expired",
		"disabled",
		"blocked",
		"full",
		"permission",
		"ignored",
		"joined",
		"reset",
		"clock",
		"left",
		"roster",
		"profile",
	}) do
		local a = Peer()
		Request(a)
		local request = a:GetNextPartyJoinRequest()
		if scenario == "expired" then
			a.now = 160
		elseif scenario == "disabled" then
			a.isEnabled = false
		elseif scenario == "blocked" then
			a.blocked = true
		elseif scenario == "full" then
			a.count = 5
		elseif scenario == "permission" then
			a.canInvite = false
		elseif scenario == "ignored" then
			a.ignored = "Friend-Realm"
		elseif scenario == "joined" then
			a.partyMembers["Friend-Realm"] = {}
		elseif scenario == "clock" then
			a.now = 99
		elseif scenario == "left" then
			a.grouped = false
		elseif scenario == "profile" then
			a.db = { profile = {} }
		elseif scenario == "roster" then
			a.partyRosterFingerprint = "new"
		else
			a:ResetPartyJoin()
		end
		Equal(a:ConfirmPartyJoin(request, true, true, false), false)
		Equal(#a.invites, 0)
		Equal(a:GetOption("autoInviteFriends"), nil)
	end
end)

QT:RegisterTest("join transport rejects wrong destinations senders routes and unsolicited replies", function()
	local a, b = Pair()
	a:RequestPartyJoin(b.name)
	local pending = a.partyJoinState.outgoing
	Equal(a:HandlePartyJoinMessage("1," .. pending.id .. "," .. a.name .. ",sent", "Impostor-Realm"), false)
	Equal(a:HandlePartyJoinMessage("1,wrong," .. a.name .. ",sent", b.name), false)
	Equal(a:HandlePartyJoinMessage("1," .. pending.id .. ",Other-Realm,sent", b.name), false)
	Equal(a.partyJoinState.outgoing, pending)
	local c = Peer()
	for _, route in ipairs({ "RAID_WARNING", "GUILD", "SAY" }) do
		c:OnCommReceived(c.commPrefix, "QJON|1,x," .. c.name .. ",request", route, "Friend-Realm")
	end
	Equal(c.partyJoinState, nil)
	c.ignored = "Friend-Realm"
	Equal(Request(c), false)
end)

QT:RegisterTest("join queues replay caches reservations and outgoing attempts are bounded", function()
	local a = Peer()
	Equal(Request(a), true)
	Equal(Request(a), false)
	local request = a:GetNextPartyJoinRequest()
	a:FinishPartyJoin(request, "declined")
	Equal(Request(a, "Friend-Realm", "other"), false)
	for i = 1, 20 do
		Request(a, "Player" .. i .. "-Realm", "req" .. i)
	end
	local count = 0
	for _ in pairs(a.partyJoinState.incoming) do
		count = count + 1
	end
	Equal(count, 9)
	a.now = 221
	a:PrunePartyJoin()
	Equal(next(a.partyJoinState.incoming), nil)
	Equal(next(a.partyJoinState.seen), nil)
	local requester, host = Pair()
	Equal(requester:RequestPartyJoin(host.name), true)
	Equal(requester:RequestPartyJoin(host.name), false)
	host:ConfirmPartyJoin(host:GetNextPartyJoinRequest(), false, false, false)
	host.count = 4
	Equal(host:CanAcceptPartyJoin("Another-Realm"), false)
	host.now = 161
	host:PrunePartyJoin()
	Equal(host:CanAcceptPartyJoin("Another-Realm"), true)
end)

QT:RegisterTest("join requests never leave existing groups and recheck stale menu metadata", function()
	for _, scenario in ipairs({ "grouped", "unknown", "stale", "failed" }) do
		local a, b = Pair()
		if scenario == "grouped" then
			a.grouped = true
		elseif scenario == "unknown" then
			a.unknown = true
		elseif scenario == "stale" then
			a.now = 230
		else
			a.sendFails = true
		end
		Equal(a:RequestPartyJoin(b.name), false)
		Equal(#b.invites, 0)
	end
end)

QT:RegisterTest("join declines expiry ignores and departures clear pending state", function()
	local a, b = Pair()
	a:RequestPartyJoin(b.name)
	b:FinishPartyJoin(b:GetNextPartyJoinRequest(), "declined")
	Equal(a.partyJoinState.outgoing, nil)
	a.now, b.now = 120, 120
	a:RequestPartyJoin(b.name)
	b.ignored = a.name
	b:PrunePartyJoin()
	Equal(b:GetNextPartyJoinRequest(), nil)
	a.now = 181
	a:PrunePartyJoin()
	Equal(a.partyJoinState.outgoing, nil)
	a:ForgetPartyJoinPeer(b.name)
	Equal(a:ShouldRequestPartyJoin(b.name), false)
end)

QT:RegisterTest("join flow preserves Forever full-name identities", function()
	local a, b = Peer("Anna Wildflower"), Peer("Joe Bucket")
	a.regional, b.regional, a.other, b.other, a.grouped, a.count = true, true, b, a, false, 0
	b:BroadcastPartyJoinMetadata()
	Equal(a:RequestPartyJoin(b.name), true)
	Equal(b:GetNextPartyJoinRequest().sender, "Anna Wildflower")
	b:ConfirmPartyJoin(b:GetNextPartyJoinRequest(), false, false, false)
	Equal(b.invites[1], "Anna Wildflower")
end)

local function Frame()
	local f = { scripts = {}, shown = false, width = 1200, height = 800, children = {} }
	for _, method in ipairs({
		"SetPoint",
		"ClearAllPoints",
		"SetAllPoints",
		"SetFrameStrata",
		"SetToplevel",
		"SetFlattensRenderLayers",
		"SetClampedToScreen",
		"SetMovable",
		"EnableMouse",
		"RegisterForDrag",
		"SetTexture",
		"SetHorizTile",
		"SetVertTile",
		"SetJustifyH",
		"SetScale",
		"StartMoving",
		"StopMovingOrSizing",
	}) do
		f[method] = function() end
	end
	function f:IsForbidden()
		return false
	end
	function f:IsProtected()
		return false
	end
	function f:SetScript(event, callback)
		self.scripts[event] = callback
	end
	function f:SetText(text)
		self.text = text
	end
	function f:SetWidth(width)
		self.width = width
	end
	function f:SetHeight(height)
		self.height = height
	end
	function f:SetSize(width, height)
		self.width, self.height = width, height
	end
	function f:GetWidth()
		return self.width
	end
	function f:GetHeight()
		return self.height
	end
	function f:SetChecked(checked)
		self.checked = checked
	end
	function f:GetChecked()
		return self.checked
	end
	function f:Show()
		self.shown = true
	end
	function f:Hide()
		self.shown = false
	end
	function f:CreateFontString()
		local child = Frame()
		self.children[#self.children + 1] = child
		return child
	end
	f.CreateTexture = f.CreateFontString
	return f
end

QT:RegisterTest("join consent popup callbacks invite decline and reset preferences between requests", function()
	local a = Peer()
	local parent = Frame()
	a.RenderPartyJoinPrompt = QT.RenderPartyJoinPrompt
	function a:GetPartyQuestUIParent()
		return parent
	end
	function a:CreatePartyQuestUIFrame()
		return Frame()
	end
	function a:CanAccessForeignFrame(f)
		return f ~= nil
	end
	Request(a)
	local frame = a.partyJoinPrompt
	assert(frame.shown and frame.message.text:find("Friend-Realm", 1, true))
	Equal(frame.friends:GetChecked(), false)
	Equal(frame.lfg:GetChecked(), false)
	frame.friends:SetChecked(true)
	frame.decline.scripts.OnClick()
	Equal(#a.invites, 0)
	Equal(a.options.autoInviteFriends, nil)
	Equal(frame.shown, false)
	a.now = 116
	Request(a, "Other-Realm", "req-2")
	Equal(frame.friends:GetChecked(), false)
	frame.lfg:SetChecked(true)
	frame.invite.scripts.OnClick()
	Equal(a.invites[1], "Other-Realm")
	Equal(a.options.autoInviteWhileLFG, true)
	Equal(frame.shown, false)
	a.now = 132
	Request(a, "Third-Realm", "req-3")
	Equal(frame.lfg:GetChecked(), true)
	a.now = 193
	a:PrunePartyJoin()
	Equal(frame.shown, false)
	frame.invite.scripts.OnClick()
	Equal(#a.invites, 1)
	a.now = 200
	Request(a, "Fourth-Realm", "req-4")
	assert(frame.shown)
	a.isEnabled = false
	a:ResetPartyJoin()
	Equal(frame.shown, false)
	frame.invite.scripts.OnClick()
	Equal(#a.invites, 1)
end)

QT:RegisterTest("speaker menus use current party metadata and stale join callbacks cannot invite", function()
	local a, b = Pair()
	local buttons = {}
	local root = {
		CreateTitle = function() end,
		CreateDivider = function() end,
		CreateButton = function(_, text, callback)
			buttons[#buttons + 1] = { text, callback }
		end,
	}
	a:PopulateChatLogSpeakerMenu(root, nil, b.name)
	Equal(buttons[1][1], "Request to Join")
	a.now = 230
	buttons[1][2]()
	Equal(b:GetNextPartyJoinRequest(), nil)
	buttons = {}
	a:PopulateChatLogSpeakerMenu(root, nil, "Legacy-Realm")
	Equal(buttons[1][1], "Invite")
end)

QT:RegisterTest("restricted incoming join requests never become deferred invitations", function()
	local a = Peer()
	a.blocked, a.options.autoInviteWhileLFG, a.options.lookingForQuestPartners = true, true, true
	Equal(Request(a), false)
	Equal(a:GetNextPartyJoinRequest(), nil)
	a.blocked = false
	a:UpdatePartyJoin()
	Equal(#a.invites, 0)
	Equal(Request(a), false) -- Replay still suppressed after restrictions lift.
end)

QT:RegisterTest("delayed party metadata cannot revive a departed or replaced peer session", function()
	local a = Peer()
	a:HandlePartyJoinMetadata("1,old,1,1,1", "Friend-Realm")
	a:RecordQTPlayerPresence("Friend-Realm", false)
	Equal(a:HandlePartyJoinMetadata("1,old,2,1,1", "Friend-Realm"), false)
	Equal(a:IsKnownQTPlayer("Friend-Realm"), false)
	Equal(a:HandlePartyJoinMetadata("1,new,1,1,1", "Friend-Realm"), true)
	Equal(a:HandlePartyJoinMetadata("1,old,3,0,0", "Friend-Realm"), false)
	Equal(a:ShouldRequestPartyJoin("Friend-Realm"), true)
	a:HandlePartyJoinMetadata("1,newest,1,0,1", "Friend-Realm")
	Equal(a:HandlePartyJoinMetadata("1,new,2,1,1", "Friend-Realm"), false)
end)

local function RelayParty(regional)
	local requester = Peer(regional and "Anna Wildflower" or "Requestor-Realm")
	local member = Peer(regional and "Joe Bucket" or "Member-Realm")
	local leader = Peer(regional and "Jane Meadow" or "Leader-Realm")
	local peers, queue = { requester, member, leader }, {}
	requester.grouped, requester.count = false, 0
	member.canInvite, member.leaderUnit = false, "party2"
	member.partyMembers[leader.name], leader.partyMembers[member.name] = {}, {}
	function member:GetUnitFullName(unit) return unit == self.leaderUnit and leader.name or nil end
	for _, peer in ipairs(peers) do
		peer.regional = regional == true
		function peer:SendWireMessageToAnnouncementRoutes(wire)
			self.wire[#self.wire + 1] = wire
			if self.sendFails then return false end
			queue[#queue + 1] = { sender = self.name, wire = wire }
			return true
		end
	end
	local function Flush()
		local sent = 0
		while #queue > 0 do
			sent = sent + 1
			assert(sent < 40, "join relay must not form a forwarding loop")
			local message = table.remove(queue, 1)
			for _, peer in ipairs(peers) do
				peer:OnCommReceived(peer.commPrefix, message.wire, "CHANNEL", message.sender, 7, "QuestTogether")
			end
		end
	end
	leader:BroadcastPartyJoinMetadata()
	member:BroadcastPartyJoinMetadata()
	Flush()
	return requester, member, leader, Flush, queue
end

QT:RegisterTest("party member redirects a real requester to its QT leader with leader-owned consent", function()
	for _, regional in ipairs({ false, true }) do
		local a, member, leader, flush = RelayParty(regional)
		member.options.autoInviteFriends, member.friend = true, a.name
		Equal(a.partyJoinState.peers[member.name].invite, false)
		Equal(a:RequestPartyJoin(member.name), true)
		flush()
		Equal(#member.invites, 0)
		Equal(member:GetNextPartyJoinRequest(), nil)
		Equal(a.partyJoinState.outgoing.target, leader.name)
		Equal(a.partyJoinState.outgoing.origin, member.name)
		Equal(a.partyJoinState.outgoing.pending, true)
		local request = leader:GetNextPartyJoinRequest()
		Equal(request.sender, a.name)
		Equal(#leader.invites, 0)
		Equal(leader:ConfirmPartyJoin(request, false, false, false), true)
		flush()
		Equal(#leader.invites, 1)
		Equal(leader.invites[1], a.name)
		Equal(a.partyJoinState.outgoing, nil)
	end
end)

QT:RegisterTest("join relay uses leader auto-approval and handles declines and failed invites", function()
	for _, mode in ipairs({ "friend", "lfg", "decline", "failed", "full" }) do
		local a, member, leader, flush = RelayParty()
		if mode == "friend" then leader.options.autoInviteFriends, leader.friend = true, a.name end
		if mode == "lfg" then leader.options.autoInviteWhileLFG, leader.options.lookingForQuestPartners = true, true end
		if mode == "failed" then leader.options.autoInviteWhileLFG, leader.options.lookingForQuestPartners, leader.inviteFails = true, true, true end
		if mode == "full" then leader.count = 5 end
		assert(a:RequestPartyJoin(member.name)); flush()
		if mode == "decline" then leader:FinishPartyJoin(leader:GetNextPartyJoinRequest(), "declined"); flush() end
		if mode == "failed" then
			Equal(#leader.invites, 1)
			assert(leader:GetNextPartyJoinRequest())
			leader:UpdatePartyJoin(); flush()
			Equal(#leader.invites, 1)
		else
			Equal(a.partyJoinState.outgoing, nil)
			Equal(#leader.invites, (mode == "friend" or mode == "lfg") and 1 or 0)
		end
	end
end)

QT:RegisterTest("join relay requires a current supported party and fresh invite-capable QT leader", function()
	for _, mode in ipairs({ "unknown", "stale", "notQT", "nonmember", "ignored", "unavailable", "full", "unsupported", "blocked", "solo", "invalidUnit" }) do
		local a, member, leader, flush = RelayParty()
		if mode == "unknown" then member.unknown = true
		elseif mode == "stale" then member.partyJoinState.peers[leader.name].at = -1000
		elseif mode == "notQT" then member.partyJoinState.peers[leader.name] = nil
		elseif mode == "nonmember" then member.partyMembers[leader.name] = nil
		elseif mode == "ignored" then member.ignored = leader.name
		elseif mode == "unavailable" then member.partyJoinState.peers[leader.name].invite = false
		elseif mode == "full" then member.count = 5
		elseif mode == "unsupported" then member.unsupported = true
		elseif mode == "blocked" then member.blocked = true
		elseif mode == "solo" then member.grouped = false
		else member.leaderUnit = "target" end
		assert(a:RequestPartyJoin(member.name)); flush()
		Equal(leader:GetNextPartyJoinRequest(), nil)
		Equal(#leader.invites, 0)
		Equal(member:GetPartyJoinRelayTarget(), nil)
	end
end)

QT:RegisterTest("join redirects reject spoofing replay chains stale requests and ignored destinations", function()
	for _, mode in ipairs({ "spoof", "id", "ignored", "self", "expired", "joined", "blocked", "reset", "pending", "loop", "sendFailure" }) do
		local a, member, leader, flush = RelayParty()
		assert(a:RequestPartyJoin(member.name))
		local request = a.partyJoinState.outgoing
		local id, sender, target = request.id, member.name, leader.name
		if mode == "spoof" then sender = "Fake-Realm"
		elseif mode == "id" then id = "wrong"
		elseif mode == "ignored" then a.ignored = leader.name
		elseif mode == "self" then target = a.name
		elseif mode == "expired" then a.now = request.expires
		elseif mode == "joined" then a.grouped = true
		elseif mode == "blocked" then a.blocked = true
		elseif mode == "reset" then a:ResetPartyJoin()
		elseif mode == "pending" then request.pending = true
		elseif mode == "loop" then request.redirected = true
		else a.sendFails = true end
		Equal(a:HandlePartyJoinMessage("1," .. id .. "," .. a.name .. ",redirect," .. target, sender), false)
		Equal(#a.wire, mode == "sendFailure" and 2 or 1)
		Equal(#leader.invites, 0)
	end
	local a, member, leader, flush = RelayParty()
	assert(a:RequestPartyJoin(member.name)); flush()
	local request = a.partyJoinState.outgoing
	local before = #a.wire
	Equal(a:HandlePartyJoinMessage("1," .. request.id .. "," .. a.name .. ",redirect," .. member.name, leader.name), false)
	Equal(a:HandlePartyJoinMessage("1," .. request.id .. "," .. a.name .. ",sent", member.name), false)
	Equal(#a.wire, before)
	a.ignored = member.name; a:PrunePartyJoin(); Equal(a.partyJoinState.outgoing, nil)
end)

QT:RegisterTest("join requests to full parties still return unavailable after a bounded attempt", function()
	local a, b = Pair()
	b.count, b.canInvite = 5, false
	a.partyJoinState.peers[b.name].invite = false
	Equal(a:RequestPartyJoin(b.name), true)
	Equal(a.partyJoinState.outgoing, nil)
	Equal(#b.invites, 0)
end)

QT:RegisterTest("non-QT leaders receive one enabled party chat request with manual-invite feedback", function()
	for _, regional in ipairs({ false, true }) do
		local a, member, leader, flush = RelayParty(regional)
		member:RecordQTPlayerPresence(leader.name, false)
		member:ForgetPartyJoinPeer(leader.name)
		member.options.announceToNonQTParty = true
		member.suppressLocalAnnouncementDisplayDuringTests = false
		function member:IsRuntimeRestrictionTypeActive() return false end
		local chats = {}
		member.API.SendPartyChatMessage = function(text, route)
			chats[#chats + 1] = { text, route }; return true
		end
		assert(a:RequestPartyJoin(member.name))
		local id = a.partyJoinState.outgoing.id
		flush()
		Equal(#chats, 1)
		Equal(chats[1][1], "[QT] " .. a.name .. " is requesting to join the party.")
		Equal(chats[1][2], "PARTY")
		Equal(a.partyJoinState.outgoing, nil)
		Equal(a.messages[#a.messages], "Join request sent to party chat. The leader must invite you manually.")
		Equal(#leader.invites, 0)
		Equal(leader:GetNextPartyJoinRequest(), nil)
		Equal(Request(member, a.name, id), false)
		Equal(Request(member, a.name, "another"), false)
		Equal(#chats, 1)
	end
end)

QT:RegisterTest("party join chat fallback respects settings membership QT discovery restrictions and failures", function()
	for _, mode in ipairs({ "off", "known", "staleQT", "leaderIgnored", "senderIgnored", "alreadyJoined", "full", "unsupported", "solo", "unknown", "blocked", "chatBlocked", "failed", "throws", "missingAPI" }) do
		local a, member, leader, flush = RelayParty()
		member.options.announceToNonQTParty = true
		member.suppressLocalAnnouncementDisplayDuringTests = false
		member:RecordQTPlayerPresence(leader.name, false)
		member:ForgetPartyJoinPeer(leader.name)
		local chats = 0
		function member:IsRuntimeRestrictionTypeActive() return mode == "chatBlocked" end
		member.API.SendPartyChatMessage = function()
			chats = chats + 1
			if mode == "throws" then error("unavailable") end
			return mode ~= "failed"
		end
		if mode == "off" then member.options.announceToNonQTParty = false
		elseif mode == "known" or mode == "staleQT" then
			member:RecordQTPlayerPresence(leader.name, true)
			if mode == "staleQT" then member:HandlePartyJoinMetadata("1,older,1,1,1", leader.name); member.partyJoinState.peers[leader.name].at = -1000 end
		elseif mode == "leaderIgnored" then member.ignored = leader.name
		elseif mode == "senderIgnored" then member.ignored = a.name
		elseif mode == "alreadyJoined" then member.partyMembers[a.name] = {}
		elseif mode == "full" then member.count = 5
		elseif mode == "unsupported" then member.unsupported = true
		elseif mode == "solo" then member.grouped = false
		elseif mode == "unknown" then member.unknown = true
		elseif mode == "blocked" then member.blocked = true
		elseif mode == "missingAPI" then member.API.SendPartyChatMessage = nil end
		assert(a:RequestPartyJoin(member.name)); flush()
		Equal(chats, (mode == "failed" or mode == "throws") and 1 or 0)
		Equal(#leader.invites, 0)
		for _, text in ipairs(a.messages) do assert(not text:find("sent to party chat", 1, true)) end
	end
end)

QT:RegisterTest("party chat join fallbacks share the bounded request budget and never retry", function()
	local a, member, leader = RelayParty()
	member:RecordQTPlayerPresence(leader.name, false)
	member.options.announceToNonQTParty = true
	member.suppressLocalAnnouncementDisplayDuringTests = false
	function member:IsRuntimeRestrictionTypeActive() return false end
	local sent = 0
	member.API.SendPartyChatMessage = function(text, route)
		assert(#text <= 255 and route == "PARTY")
		sent = sent + 1; return true
	end
	for i = 1, 20 do Request(member, "Visitor" .. i .. "-Realm", "request-" .. i) end
	Equal(sent, 10)
	Equal(next(member.partyJoinState.incoming), nil)
	member:UpdatePartyJoin()
	Equal(sent, 10)
end)

QT:RegisterTest("direct join requests acknowledge by whisper and still require invite consent", function()
	local a = Peer("Host-Realm")
	function a:SendWireMessageToAnnouncementRoutes(wire, _, routes)
		self.wire[#self.wire + 1] = wire
		self.lastRoutes = routes
		return true
	end
	a:OnCommReceived(a.commPrefix, "QJON|1,direct-join," .. a.name .. ",request", "WHISPER", "Friend-Realm")
	local request = a:GetNextPartyJoinRequest()
	assert(request)
	Equal(#a.invites, 0)
	Equal(a.lastRoutes[1].distribution, "WHISPER")
	Equal(a.lastRoutes[1].target, "Friend-Realm")
	a:FinishPartyJoin(request, "declined")
	Equal(#a.invites, 0)
	Equal(a.lastRoutes[1].distribution, "WHISPER")
end)
