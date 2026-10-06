-- Addon-owned models and transports only; native contracts stay in offline profiles.
local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function Fixture(name)
	local a = setmetatable({
		name = name or "Me Realm",
		time = 100,
		isEnabled = true,
		options = { sharePartyFocus = true, sharePartyWaypoint = true, showPartyWaypoints = true },
		native = { questID = 1, mapID = 37, x = 0.4, y = 0.5 },
		owned = { [1] = 1, [2] = 2 },
		wire = {},
		writes = {},
		ignored = {},
		partyMembers = {},
		partyMemberOrder = {},
		token = true,
		geographicCommsState = {},
		commPrefix = "QuestTogether",
	}, { __index = QT })
	a.API = {
		GetTime = function()
			return a.time
		end,
		Random = function(low)
			return low
		end,
		IsInRaid = function()
			return a.raid == true
		end,
		IsInParty = function()
			return #a.partyMemberOrder > 1
		end,
		IsInInstanceGroup = function()
			return a.instance == true
		end,
		GetPartyNavigationNativeState = function()
			if a.unreadable then
				return nil
			end
			return { questID = a.native.questID, mapID = a.native.mapID, x = a.native.x, y = a.native.y }
		end,
		GetActiveTrackedQuestID = function()
			return a.native.questID > 0 and a.native.questID or nil
		end,
		IsOnQuest = function(id)
			return a.owned[id] ~= nil
		end,
		GetQuestLogIndexForSharing = function(id)
			return a.owned[id]
		end,
		SetPartyNavigationQuest = function(id)
			a.writes[#a.writes + 1] = id
			if a.reject then
				return false
			end
			a.native.questID = id
			a:OnPartyNavigationTrackingChanged()
			return true
		end,
		SendAddonMessage = function(_, wire, route, target)
			a.wire[#a.wire + 1] = { wire = wire, route = route, target = target }
			return a.sendResult or 0
		end,
	}
	function a:GetOption(key)
		return self.options[key]
	end
	function a:IsRuntimeRestricted()
		return self.blocked == true
	end
	function a:IsRuntimeRestrictionTypeActive()
		return self.blocked == true
	end
	function a:NormalizeMemberName(n)
		return n
	end
	function a:IsSelfSender(n)
		return self.name == n
	end
	function a:IsIgnoredPlayerName(n)
		return self.ignored[n] == true
	end
	function a:GetLocalizedQuestTitle(id)
		return self.localized and self.localized[id]
	end
	function a:GetQuestTitle(id)
		return "Quest title " .. id
	end
	function a:RecordQTPlayerPresence(n)
		self.discovered = n
	end
	function a:RecordCommsDiagnostic() end
	function a:RecordCommsTraffic() end
	function a:Debugf() end
	function a:TakeCommsSendToken()
		return self.token
	end
	function a:IsAnnouncementChannelEvent()
		return true
	end
	function a:Roster(...)
		self.partyMemberOrder, self.partyMembers = { ... }, {}
		for _, n in ipairs(self.partyMemberOrder) do
			self.partyMembers[n] = { classFile = "MAGE" }
		end
		self.partyRosterFingerprint = table.concat(self.partyMemberOrder, "|")
	end
	function a:Tick(dt)
		self.time = self.time + (dt or 0.3)
		self:UpdatePartyNavigation()
	end
	function a:Deliver(b, index, route)
		local message = self.wire[index or #self.wire]
		b:OnCommReceived(b.commPrefix, message.wire, route or message.route, self.name)
	end
	a:Roster(a.name, "Friend Realm")
	return a
end
local function Pair()
	local a, b = Fixture("Me Realm"), Fixture("Friend Realm")
	b:Roster(a.name, b.name)
	a:Tick(0)
	b:Tick(0)
	a:Tick()
	b:Tick()
	a:Deliver(b)
	b:Deliver(a)
	return a, b
end
QT:RegisterTest("party navigation combines changes and routes only to the current small party", function()
	local a, b = Pair()
	Equal(#a.wire, 1)
	Equal(a.wire[1].route, "PARTY")
	Equal(a:GetPartyNavigationPeer(b.name).mapID, 37)
	Equal(a.discovered, b.name)
	b.native.questID, b.native.x = 2, 0.7
	b:QueuePartyNavigationUpdate()
	b:Tick(0.1)
	Equal(#b.wire, 1)
	b:Tick(0.2)
	b:Deliver(a)
	Equal(a:GetPartyNavigationPeer(b.name).questID, 2)
	Equal(a:GetPartyNavigationPeer(b.name).x, 0.7)
	Equal(#a.writes, 0)
	a.instance = true
	a:Tick()
	a:Tick()
	Equal(a.wire[#a.wire].route, "INSTANCE_CHAT")
	a.raid = true
	local sent = #a.wire
	a:Tick(50)
	Equal(#a.wire, sent)
	Equal(a:GetPartyNavigationPeer(b.name), nil)
end)
QT:RegisterTest("party navigation rejects public nonmember malformed replayed and retired snapshots", function()
	local a, b = Pair()
	local peer = a:GetPartyNavigationPeer(b.name)
	b.native.questID = 2
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a, nil, "CHANNEL")
	Equal(a:GetPartyNavigationPeer(b.name), peer)
	b:Deliver(a, nil, "WHISPER")
	Equal(a:GetPartyNavigationPeer(b.name), peer)
	b:Deliver(a)
	Equal(a:GetPartyNavigationPeer(b.name).questID, 2)
	b:Deliver(a, 1)
	Equal(a:GetPartyNavigationPeer(b.name).questID, 2)
	Equal(a:HandlePartyNavigationMessage("1,100-1,99,0,1,37,10001,0,,", b.name, "PARTY"), false)
	Equal(a:HandlePartyNavigationMessage("1,100-1,99,0,1,37,1,0,,", "Stranger Realm", "PARTY"), false)
	b:ResetPartyNavigation()
	b:Tick()
	b:Tick()
	b:Deliver(a)
	local new = a:GetPartyNavigationPeer(b.name)
	b:Deliver(a, 1)
	Equal(a:GetPartyNavigationPeer(b.name), new)
	a.ignored[b.name] = true
	a:Tick()
	Equal(a:GetPartyNavigationPeer(b.name), nil)
end)
QT:RegisterTest("party quest following applies once and stops for external navigation", function()
	local a, b = Pair()
	b.native.questID = 2
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	assert(a:FollowPartyQuestFocus(b.name))
	Equal(a.native.questID, 2)
	Equal(#a.writes, 1)
	a:Tick()
	Equal(a.partyNavigationState.following, b.name)
	for _ = 1, 5 do
		a:Tick()
	end
	Equal(#a.writes, 1)
	a.native.questID = 1
	a:OnPartyNavigationTrackingChanged()
	a:Tick()
	Equal(a.partyNavigationState.following, nil)
	Equal(a.native.questID, 1)
end)
QT:RegisterTest("party focus pauses for missing quests restrictions and rejected native changes", function()
	local a, b = Pair()
	b.native.questID = 2
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	a.owned[2] = nil
	assert(a:FollowPartyQuestFocus(b.name))
	Equal(#a.writes, 0)
	Equal(a.partyNavigationState.followStatus, "You don't have this quest")
	a.owned[2], a.blocked = 2, true
	a:Tick()
	Equal(#a.writes, 0)
	a.blocked, a.reject = false, true
	a:Tick()
	Equal(#a.writes, 1)
	for _ = 1, 5 do
		a:Tick()
	end
	Equal(#a.writes, 1)
	Equal(a.partyNavigationState.followStatus, "Unable to track this quest")
	a:StopPartyQuestFollow()
	a.reject = false
	assert(a:FollowPartyQuestFocus(b.name))
	Equal(#a.writes, 2)
	b.native.questID = 0
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	Equal(a.native.questID, 2)
	Equal(a.partyNavigationState.followStatus, "No focused quest")
end)
QT:RegisterTest("party follow cycles departures expiry and disabling clear owned state", function()
	local a, b = Pair()
	assert(a:FollowPartyQuestFocus(b.name))
	a:Tick()
	a:Deliver(b)
	Equal(b:FollowPartyQuestFocus(a.name), false)
	a:Tick(91)
	b:Deliver(a, 1)
	Equal(a:GetPartyNavigationPeer(b.name), nil)
	Equal(a.partyNavigationState.following, nil)
	Equal(#a:GetPartyWaypointRows(), 0)
	b:Tick(1)
	b:Tick(30)
	b:Deliver(a)
	assert(a:FollowPartyQuestFocus(b.name))
	a:Roster(a.name)
	a:Tick()
	Equal(a.partyNavigationState.following, nil)
	a:ResetPartyNavigation()
	Equal(a.partyNavigationState, nil)
end)
QT:RegisterTest("party navigation options clear sharing without altering personal navigation", function()
	local a, b = Pair()
	b.options.sharePartyFocus, b.options.sharePartyWaypoint = false, false
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	Equal(a:GetPartyNavigationPeer(b.name).questID, -1)
	Equal(#a:GetPartyWaypointRows(), 0)
	Equal(b.native.questID, 1)
	Equal(b.native.mapID, 37)
	Equal(a:FollowPartyQuestFocus(b.name), false)
	b.options.sharePartyFocus, b.options.sharePartyWaypoint = true, true
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	a.options.showPartyWaypoints = false
	Equal(#a:GetPartyWaypointRows(), 0)
	a.options.showPartyWaypoints = true
	Equal(#a:GetPartyWaypointRows(), 1)
	b:WithdrawPartyNavigation()
	b:Deliver(a)
	Equal(#a:GetPartyWaypointRows(), 0)
end)
QT:RegisterTest("party snapshot pacing sends latest state and bounds idle heartbeats", function()
	local a = Fixture()
	a.token = false
	a:Tick(0)
	a:Tick()
	Equal(#a.wire, 0)
	a.native.questID, a.native.x = 2, 0.9
	a:QueuePartyNavigationUpdate()
	a:Tick()
	a.token = true
	a:Tick(2)
	Equal(#a.wire, 1)
	assert(#a.wire[1].wire <= 255)
	Equal(a.partyNavigationState.localState.questID, 2)
	for _ = 1, 100 do
		a:Tick(0.2)
	end
	Equal(#a.wire, 1)
	a:Tick(10)
	Equal(#a.wire, 2)
	a.unreadable = true
	a:Tick(40)
	Equal(#a.wire, 2)
end)
QT:RegisterTest("party waypoint navigation rechecks ownership and stops quest following", function()
	local a, b = Pair()
	assert(a:FollowPartyQuestFocus(b.name))
	function a:OpenPingWaypoint(map, x, y)
		self.destination = { map, x, y }
		return true
	end
	assert(a:NavigateToPartyWaypoint(b.name))
	Equal(a.destination[1], 37)
	Equal(a.destination[2], 40)
	Equal(a.partyNavigationState.following, nil)
	a.blocked = true
	Equal(a:NavigateToPartyWaypoint(b.name), false)
	a.blocked = false
	a:Roster(a.name)
	Equal(a:NavigateToPartyWaypoint(b.name), false)
end)
QT:RegisterTest("party focus manual navigation wins over incoming packets and unreadable observations", function()
	local a, b = Pair()
	assert(a:FollowPartyQuestFocus(b.name))
	a.native.questID = 0
	a:OnPartyNavigationTrackingChanged()
	a.unreadable = true
	b.native.questID = 2
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	Equal(#a.writes, 0)
	assert(a.partyNavigationState.checkExternal)
	a.unreadable = false
	a:Tick()
	Equal(a.partyNavigationState.following, nil)
	Equal(a.native.questID, 0)
	Equal(#a.writes, 0)
end)
QT:RegisterTest("party focus retains only latest intent during restrictions and rechecks on resume", function()
	local a, b = Pair()
	assert(a:FollowPartyQuestFocus(b.name))
	a.blocked = true
	b.native.questID = 2
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	Equal(a:GetPartyNavigationPeer(b.name).questID, 2)
	Equal(#a.writes, 0)
	b.native.questID = 1
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	a.blocked = false
	a:Tick()
	Equal(#a.writes, 0)
	Equal(a.partyNavigationState.following, b.name)
	a.blocked = true
	a:Roster(a.name)
	a:Tick()
	Equal(a.partyNavigationState.following, nil)
end)
QT:RegisterTest("party focus native failures refresh UI once without retrying", function()
	local a, b = Pair()
	assert(a:FollowPartyQuestFocus(b.name))
	a.partyQuestCompareSession = {}
	a.renders = 0
	function a:QueuePartyQuestCompareRender()
		self.renders = self.renders + 1
	end
	a.owned[2] = nil
	b.native.questID = 2
	b:QueuePartyNavigationUpdate()
	b:Tick()
	b:Deliver(a)
	a:Tick()
	local renders = a.renders
	a.owned[2], a.reject = 2, true
	a:Tick()
	assert(a.renders > renders)
	Equal(a.partyNavigationState.followStatus, "Unable to track this quest")
	Equal(#a.writes, 1)
	a:Tick()
	Equal(#a.writes, 1)
end)
QT:RegisterTest("explicit coordinate navigation stops following even with TomTom", function()
	local a, b = Pair()
	assert(a:FollowPartyQuestFocus(b.name))
	function a:CreateTomTomWaypoint()
		return true
	end
	assert(a:OpenPingWaypoint(37, 50, 50))
	Equal(a.partyNavigationState.following, nil)
end)

QT:RegisterTest("focus labels distinguish unsupported waiting expired and unavailable without guessing privacy", function()
 local a = Fixture()
 function a:GetPartyNavigationPeer() return self.peer end
 function a:GetPlayerAddonVersion() return self.peerVersion end
 Equal(a:GetPartyFocusLabel("Friend"), "Waiting for quest focus")
 a.peerVersion = "6.2.3"
 Equal(a:GetPartyFocusLabel("Friend"), "Quest focus unsupported")
 a.partyNavigationState = { seen = { Friend = {} } }
 Equal(a:GetPartyFocusLabel("Friend"), "Focus data expired")
 a.peer = { questID = -1 }
 Equal(a:GetPartyFocusLabel("Friend"), "Focus not shared or unavailable")
 a.peer.questID = 0
 Equal(a:GetPartyFocusLabel("Friend"), "No focused quest")
end)
