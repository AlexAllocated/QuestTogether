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
			return a.grouped == true, a.canInvite ~= false, a.count or 0
		end,
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
	for _, route in ipairs({ "WHISPER", "GUILD", "SAY" }) do
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
	for _, scenario in ipairs({ "grouped", "unknown", "stale", "full", "failed" }) do
		local a, b = Pair()
		if scenario == "grouped" then
			a.grouped = true
		elseif scenario == "unknown" then
			a.unknown = true
		elseif scenario == "stale" then
			a.now = 230
		elseif scenario == "full" then
			a.partyJoinState.peers[b.name].invite = false
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
