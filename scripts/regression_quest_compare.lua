-- All fixtures are private addon objects. Never replace game globals in /qt test.
local QuestTogether = _G.QuestTogether
local function Equal(actual, expected)
	if actual ~= expected then
		error("expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end
local function FinishExpansion(frame)
	for _ = 1, 5 do
		local update = frame.expansionAnimator.scripts.OnUpdate
		if not update then
			return
		end
		update(frame.expansionAnimator, 0.1)
	end
	error("expansion animation did not finish")
end

local function Quest(id, title, pushable, complete)
	return { questId = id, questTitle = title or ("Quest " .. id), isPushable = pushable, isComplete = complete == true }
end

local function Fixture(name, entries)
	local addon = setmetatable({
		isEnabled = true,
		name = name or "Me-Realm",
		entries = entries or {},
		now = 100,
		partyMembers = {},
		partyMemberOrder = {},
		pendingQuestCompareRequests = {},
		recentCommMessageSignatures = {},
		partyQuestCompareSession = false,
		partyQuestCompareWindow = false,
		partyQuestComparePreview = false,
		partyQuestSharePrompt = false,
		partyQuestShareState = false,
		questCompareResponseQueue = false,
		channelRequestSequence = 0,
		options = {},
		delayed = {},
		wire = {},
		pushes = 0,
		renders = 0,
		prompts = 0,
		workState = { entries = {}, generations = {} },
	}, { __index = QuestTogether })
	addon.API = {
		GetTime = function()
			return addon.now
		end,
		IsWorldMapVisible = function()
			return addon.mapVisible == true
		end,
		Random = function()
			return 1000
		end,
		Delay = function(delay, callback)
			addon.delayed[#addon.delayed + 1] = { time = addon.now + delay, callback = callback }
		end,
		CanShareQuests = function()
			return true
		end,
		IsInGroup = function()
			return addon.grouped ~= false
		end,
		GetQuestLogIndexForSharing = function(id)
			for index, entry in ipairs(addon.entries) do
				if entry.questId == id then
					return index
				end
			end
		end,
		IsPushableQuest = function(id)
			for _, entry in ipairs(addon.entries) do
				if entry.questId == id then
					return entry.isPushable
				end
			end
		end,
		PushQuestToParty = function()
			addon.pushes = addon.pushes + 1
			return not addon.pushFails
		end,
	}
	function addon:GetPlayerFullName()
		return self.name
	end
	function addon:GetPlayerName()
		return self.name
	end
	function addon:GetPlayerClassFile()
		return "MAGE"
	end
	function addon:NormalizeMemberName(value)
		return value
	end
	function addon:IsSelfSender(value)
		return value == self.name
	end
	function addon:IsIgnoredPlayerName(value)
		return value == self.ignored
	end
	function addon:GetOption(key)
		return self.options[key]
	end
	function addon:SetOption(key, value)
		self.options[key] = value
		return true
	end
	function addon:IsRuntimeRestricted()
		return self.blocked == true
	end
	function addon:GetDeferredWorkStateStore()
		return self.workState
	end
	function addon:EnsureMapWorkWakeup()
		self.mapWakeups = (self.mapWakeups or 0) + 1
	end
	function addon:RunGuardedCallback(_, callback)
		-- Do not swallow scheduler failures in a fixture or log through live UI.
		callback()
		return true
	end
	function addon:GetGroupAnnouncementDistribution()
		return self.grouped ~= false and "PARTY" or nil
	end
	function addon:RefreshPartyRoster() end
	function addon:BuildQuestCompareEntries()
		if self:IsWorkBlocked("quest_snapshot_refresh") then
			return nil, "restricted"
		end
		self.snapshotReads = (self.snapshotReads or 0) + 1
		if not self.unreadable then
			return self.entries
		end
	end
	function addon:QueuePartyQuestCompareRender()
		self.renders = self.renders + 1
	end
	function addon:QueuePartyQuestSharePrompt()
		self.prompts = self.prompts + 1
	end
	function addon:RecordCommsDiagnostic() end
	function addon:Debug() end
	function addon:Debugf() end
	function addon:Print()
		error("comparison must not print to chat")
	end
	addon.PrintQuestCompareStart, addon.PrintQuestCompareMessage = addon.Print, addon.Print
	addon.PrintQuestCompareDone, addon.PrintConsoleAnnouncement = addon.Print, addon.Print
	function addon:SendWireMessageToAnnouncementRoutes(message, _, routes)
		Equal(#routes, 1)
		Equal(routes[1].distribution, "PARTY")
		self.wire[#self.wire + 1] = message
		return self.sendFails ~= true
	end
	function addon:Advance(seconds)
		self.now = self.now + seconds
		for _ = 1, 1000 do
			local nextIndex
			for i, job in ipairs(self.delayed) do
				if job.time <= self.now then
					nextIndex = i
					break
				end
			end
			if not nextIndex then
				return
			end
			table.remove(self.delayed, nextIndex).callback()
		end
		error("unbounded fixture timer loop")
	end
	function addon:Roster(...)
		self.partyMembers, self.partyMemberOrder = {}, { ... }
		for _, member in ipairs(self.partyMemberOrder) do
			self.partyMembers[member] = { fullName = member, classFile = "MAGE" }
		end
	end
	addon:Roster(addon.name, "Friend-Realm")
	return addon
end

local function Reply(addon, name, entries, complete, capable)
	local member = addon.partyQuestCompareSession.byName[name]
	local id = member.requestId
	for _, entry in ipairs(entries) do
		local data = {}
		for key, value in pairs(entry) do
			data[key] = value
		end
		data.senderName, data.requestId = name, id
		addon:HandleQuestCompareEntry(data)
	end
	if complete then
		addon:HandleQuestCompareDone({
			senderName = name,
			requestId = id,
			count = #entries,
			supportsShareRequests = capable,
		})
	end
end

local function SharePacket(addon, requestId, questId, status, target)
	return table.concat({
		"1",
		addon:EscapePayload(requestId or "share-1"),
		addon:EscapePayload(target or addon.name),
		tostring(questId or 1),
		status or "request",
	}, ",")
end

QuestTogether:RegisterTest(
	"party compare defaults to all quests with an opt-in own-quest filter and waits for complete snapshots",
	function()
		local a = Fixture(nil, { Quest(1, "Local", true) })
		Equal(QuestTogether.DEFAULTS.profile.compareHideOtherQuests, false)
		-- Earlier unreleased profiles must also receive the new show-all default.
		a.options = { compareShowOtherQuests = false }
		a:ApplyDefaults(a.options, QuestTogether.DEFAULTS.profile)
		a:RefreshPartyQuestCompare()
		Equal(#a:BuildPartyQuestDiffRows(), 1)
		Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Loading")
		Reply(a, "Friend-Realm", { Quest(2, "Other", true, true) }, false)
		Equal(#a:BuildPartyQuestDiffRows(), 2)
		a:SetOption("compareHideOtherQuests", true)
		Equal(#a:BuildPartyQuestDiffRows(), 1)
		Equal(a:BuildPartyQuestDiffRows()[1].title, "Local")
		a:SetOption("compareHideOtherQuests", false)
		Equal(#a:BuildPartyQuestDiffRows(), 2)
		Equal(a:BuildPartyQuestDiffRows()[1].cells[1], "Missing")
		local member = a.partyQuestCompareSession.byName["Friend-Realm"]
		a:HandleQuestCompareDone({
			senderName = member.name,
			requestId = member.requestId,
			count = 1,
			supportsShareRequests = true,
		})
		local rows = a:BuildPartyQuestDiffRows()
		Equal(rows[1].title, "Local")
		Equal(rows[1].cells[2], "Missing")
		Equal(rows[1].action, "share")
		Equal(rows[2].cells[2], "Ready")
		Equal(rows[2].action, "request")
	end
)

QuestTogether:RegisterTest("party diff done before entries cannot mark absent quests missing", function()
	local a = Fixture(nil, { Quest(1) })
	a:RefreshPartyQuestCompare()
	local member = a.partyQuestCompareSession.byName["Friend-Realm"]
	a:HandleQuestCompareDone({ senderName = member.name, requestId = member.requestId, count = 2 })
	Reply(a, member.name, { Quest(2) }, false)
	Equal(member.state, "loading")
	Reply(a, member.name, { Quest(2) }, false)
	Equal(member.state, "loading")
	Reply(a, member.name, { Quest(3) }, false)
	Equal(member.state, "ready")
	Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Missing")
end)

QuestTogether:RegisterTest("party diff keeps timeout and unreadable snapshots unknown", function()
	local a = Fixture(nil, { Quest(1) })
	a:RefreshPartyQuestCompare()
	a:Advance(181)
	Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Unknown")
	Equal(a:BuildPartyQuestDiffRows()[1].action, nil)
	a:RefreshPartyQuestCompare()
	Reply(a, "Friend-Realm", { Quest(2, nil, true) }, true, true)
	a.unreadable = true
	a:RefreshLocalPartyQuestCompare()
	a:SetOption("compareHideOtherQuests", false)
	Equal(a:BuildPartyQuestDiffRows()[1].cells[1], "Unknown")
	Equal(a:BuildPartyQuestDiffRows()[1].action, nil)
end)

QuestTogether:RegisterTest("party diff refresh isolates generations and same-tick requests", function()
	local a = Fixture()
	a:Roster(a.name, "Friend-Realm", "Third-Realm")
	a:RefreshPartyQuestCompare()
	local old = a.partyQuestCompareSession
	local oldId = old.byName["Friend-Realm"].requestId
	assert(oldId ~= old.byName["Third-Realm"].requestId)
	a:RefreshPartyQuestCompare()
	assert(oldId ~= a.partyQuestCompareSession.byName["Friend-Realm"].requestId)
	Equal(a:HandleQuestCompareDone({ senderName = "Friend-Realm", requestId = oldId, count = 0 }), false)
	Equal(a.partyQuestCompareSession.byName["Friend-Realm"].state, "loading")
	a:ResetCommsState()
	a:Advance(200)
	Equal(a.partyQuestCompareSession, nil)
end)

QuestTogether:RegisterTest("party diff rejects outsiders and clears departed member snapshots", function()
	local a = Fixture(nil, { Quest(1) })
	a:RefreshPartyQuestCompare()
	local id = a.partyQuestCompareSession.byName["Friend-Realm"].requestId
	Equal(a:HandleQuestCompareDone({ senderName = "Stranger-Realm", requestId = id, count = 0 }), false)
	a:Roster(a.name)
	a:OnPartyQuestRosterChanged()
	Equal(#a.partyQuestCompareSession.members, 1)
	Equal(a:HandleQuestCompareDone({ senderName = "Friend-Realm", requestId = id, count = 0 }), false)
end)

QuestTogether:RegisterTest("party diff reports send failures and older share capability", function()
	local a = Fixture()
	a.sendFails = true
	a:RefreshPartyQuestCompare()
	Equal(a.partyQuestCompareSession.byName["Friend-Realm"].state, "unavailable")
	a.sendFails = false
	a:RefreshPartyQuestCompare()
	Reply(a, "Friend-Realm", { Quest(1, nil, true) }, true, false)
	a:SetOption("compareHideOtherQuests", false)
	Equal(a:BuildPartyQuestDiffRows()[1].action, nil)
	Equal(a:BuildPartyQuestDiffRows()[1].hint, "Owner needs an update")
	Equal(a:DecodeQuestCompareDonePayload("1,r,Friend-Realm,0").supportsShareRequests, false)
	Equal(a:DecodeQuestCompareDonePayload("1,r,Friend-Realm,MAGE,0").supportsShareRequests, false)
	Equal(a:DecodeQuestCompareDonePayload("1,r,Friend-Realm,MAGE,0,share1").supportsShareRequests, true)
end)

QuestTogether:RegisterTest("party diff share rechecks live ownership shareability and restrictions", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	Equal(a:SharePartyDiffQuest(1), true)
	a.entries[1].isPushable = false
	Equal(a:SharePartyDiffQuest(1), false)
	a.entries[1].isPushable = true
	a.blocked = true
	Equal(a:SharePartyDiffQuest(1), false)
	a.blocked = false
	a.entries = {}
	Equal(a:SharePartyDiffQuest(1), false)
	Equal(a.pushes, 1)
end)

QuestTogether:RegisterTest("party share requests ask by default and remember explicit always allow consent", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY"), true)
	Equal(a.pushes, 0)
	local request = a:GetNextPartyQuestShareRequest()
	assert(request)
	Equal(a:ConfirmPartyQuestShare(request, true, false), true)
	Equal(a:GetOption("autoAcceptPartyShareRequests"), true)
	Equal(a.pushes, 1)
	a:Advance(6)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, "r2"), "Friend-Realm", "PARTY"), true)
	Equal(a.pushes, 2)
	Equal(a:GetNextPartyQuestShareRequest(), nil)
	a:SetOption("autoAcceptPartyShareRequests", false)
	a:Advance(6)
	a:HandlePartyQuestShareMessage(SharePacket(a, "r3"), "Friend-Realm", "PARTY")
	Equal(a.pushes, 2)
	assert(a:GetNextPartyQuestShareRequest())
end)

QuestTogether:RegisterTest("party share failed automatic call falls back to manual consent once", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	a:SetOption("autoAcceptPartyShareRequests", true)
	a.pushFails = true
	a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY")
	Equal(a.pushes, 1)
	local request = a:GetNextPartyQuestShareRequest()
	assert(request)
	a:Advance(1)
	Equal(a.pushes, 1)
	a.pushFails = false
	Equal(a:ConfirmPartyQuestShare(request, false, false), true)
	Equal(a.pushes, 2)
end)

QuestTogether:RegisterTest("party share request authenticates route sender target version and quest id", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	for _, route in ipairs({ "CHANNEL", "RAID_WARNING", "GUILD" }) do
		Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", route), false)
	end
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Stranger-Realm", "PARTY"), false)
	Equal(
		a:HandlePartyQuestShareMessage(SharePacket(a, nil, nil, nil, "Someone-Realm"), "Friend-Realm", "PARTY"),
		false
	)
	for _, payload in ipairs({
		"2,r," .. a.name .. ",1,request",
		"1,r," .. a.name .. ",1.5,request",
		"1,r," .. a.name .. ",-1,request",
		"1,r," .. a.name .. ",inf,request",
		"1,r," .. a.name .. ",1,unknown",
	}) do
		Equal(a:HandlePartyQuestShareMessage(payload, "Friend-Realm", "PARTY"), false)
	end
	a.ignored = "Friend-Realm"
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY"), false)
	Equal(a.pushes, 0)
	Equal(a:GetNextPartyQuestShareRequest(), nil)
end)

QuestTogether:RegisterTest("party share replay and bursts do not repeat automatic shares", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	a:SetOption("autoAcceptPartyShareRequests", true)
	local packet = SharePacket(a)
	a:HandlePartyQuestShareMessage(packet, "Friend-Realm", "PARTY")
	Equal(a:HandlePartyQuestShareMessage(packet, "Friend-Realm", "PARTY"), false)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, "r2"), "Friend-Realm", "PARTY"), false)
	a:Advance(6)
	Equal(a:HandlePartyQuestShareMessage(packet, "Friend-Realm", "PARTY"), false)
	Equal(a.pushes, 1)
end)

QuestTogether:RegisterTest("party share stale consent never shares or enables automatic sharing", function()
	for _, change in ipairs({ "departed", "expired", "removed", "unshareable", "restricted", "disabled", "ignored" }) do
		local a = Fixture(nil, { Quest(1, nil, true) })
		a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY")
		local request = a:GetNextPartyQuestShareRequest()
		if change == "departed" then
			a:Roster(a.name)
		elseif change == "expired" then
			a.now = a.now + 61
		elseif change == "removed" then
			a.entries = {}
		elseif change == "unshareable" then
			a.entries[1].isPushable = false
		elseif change == "restricted" then
			a.blocked = true
		elseif change == "disabled" then
			a.isEnabled = false
		elseif change == "ignored" then
			a.ignored = "Friend-Realm"
		end
		Equal(a:ConfirmPartyQuestShare(request, true, false), false)
		Equal(a.pushes, 0)
		Equal(a:GetOption("autoAcceptPartyShareRequests"), nil)
	end
end)

QuestTogether:RegisterTest("party share restricted incoming requests never queue a later share", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	a:SetOption("autoAcceptPartyShareRequests", true)
	a.blocked = true
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY"), false)
	a.blocked = false
	a:Advance(180)
	Equal(a.pushes, 0)
	Equal(a:GetNextPartyQuestShareRequest(), nil)
end)

QuestTogether:RegisterTest("party share expiry decline and disable clear pending prompts", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY")
	a:Advance(61)
	Equal(a:GetNextPartyQuestShareRequest(), nil)
	a:HandlePartyQuestShareMessage(SharePacket(a, "r2"), "Friend-Realm", "PARTY")
	Equal(a:FinishPartyQuestShare(a:GetNextPartyQuestShareRequest(), "declined"), true)
	Equal(a:GetNextPartyQuestShareRequest(), nil)
	a:Advance(6)
	a:HandlePartyQuestShareMessage(SharePacket(a, "r3"), "Friend-Realm", "PARTY")
	local stale = a:GetNextPartyQuestShareRequest()
	a:ResetCommsState()
	a:Advance(61)
	Equal(a:ConfirmPartyQuestShare(stale, true), false)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest("party share request and consent complete through two addon transports", function()
	local a, b = Fixture("Me-Realm"), Fixture("Friend-Realm", { Quest(1, "Together", true) })
	a:Roster(a.name, b.name)
	b:Roster(a.name, b.name)
	a:SetOption("compareHideOtherQuests", false)
	a:RefreshPartyQuestCompare()
	Reply(a, b.name, b.entries, true, true)
	local function Deliver(sender, receiver)
		receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire], "PARTY", sender.name)
	end
	Equal(a:RequestPartyQuestShare(1, b.name), true)
	Equal(a:RequestPartyQuestShare(1, b.name), false)
	Deliver(a, b)
	Equal(b.pushes, 0)
	Deliver(b, a)
	Equal(a:GetPartyQuestShareStatus(1), "Awaiting confirmation")
	Equal(b:ConfirmPartyQuestShare(b:GetNextPartyQuestShareRequest(), false), true)
	Deliver(b, a)
	Equal(a:GetPartyQuestShareStatus(1), "Share attempted")
	Equal(b.pushes, 1)
end)

QuestTogether:RegisterTest(
	"party diff snapshots cross actual codecs with Forever full names and reordered delivery",
	function()
		local a = Fixture("Anakin Ofthesea", { Quest(1, "Shared", true) })
		local b = Fixture("Anakin Othername", { Quest(1, "Shared", true), Quest(2, "Remote only", true) })
		a:Roster(a.name, b.name)
		b:Roster(a.name, b.name)
		a:RefreshPartyQuestCompare()
		b:OnCommReceived(b.commPrefix, a.wire[1], "PARTY", a.name)
		b:Advance(0.2)
		b:Advance(0.2)
		Equal(#b.wire, 3)
		for i = #b.wire, 1, -1 do
			a:OnCommReceived(a.commPrefix, b.wire[i], "PARTY", b.name)
		end
		Equal(a.partyQuestCompareSession.byName[b.name].state, "ready")
		Equal(a.partyQuestCompareSession.byName[b.name].supportsShareRequests, true)
		a:SetOption("compareHideOtherQuests", false)
		local rows = a:BuildPartyQuestDiffRows()
		Equal(#rows, 2)
		Equal(rows[1].title, "Remote only")
		Equal(rows[1].owner, "Anakin Othername")
		Equal(rows[1].action, "request")
	end
)

QuestTogether:RegisterTest("party share acknowledgement requires exact request sender and quest", function()
	local a = Fixture()
	a:Roster(a.name, "Friend-Realm", "Third-Realm")
	a:SetOption("compareHideOtherQuests", false)
	a:RefreshPartyQuestCompare()
	Reply(a, "Friend-Realm", { Quest(1, nil, true) }, true, true)
	a:RequestPartyQuestShare(1, "Friend-Realm")
	local id = next(a.partyQuestShareState.outgoing)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, id, 1, "sent"), "Third-Realm", "PARTY"), false)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, id, 2, "sent"), "Friend-Realm", "PARTY"), false)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, "wrong", 1, "sent"), "Friend-Realm", "PARTY"), false)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, id, 1, "declined"), "Friend-Realm", "PARTY"), true)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a, id, 1, "sent"), "Friend-Realm", "PARTY"), false)
	Equal(a:GetPartyQuestShareStatus(1), "Request declined")
end)

QuestTogether:RegisterTest(
	"party share requester expires missing replies and rechecks newly accepted quests",
	function()
		local a = Fixture()
		a:SetOption("compareHideOtherQuests", false)
		a:RefreshPartyQuestCompare()
		Reply(a, "Friend-Realm", { Quest(1, nil, true) }, true, true)
		a.entries = { Quest(1, nil, true) }
		Equal(a:RequestPartyQuestShare(1, "Friend-Realm"), false)
		a.entries = {}
		Equal(a:RequestPartyQuestShare(1, "Friend-Realm"), true)
		a:Advance(61)
		Equal(a:GetPartyQuestShareStatus(1), "Request expired")
		Equal(a:RequestPartyQuestShare(1, "Friend-Realm"), true)
	end
)

QuestTogether:RegisterTest("party share incoming queue has a hard bound", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	for i = 1, 11 do
		local name = "Member" .. i .. "-Realm"
		a.partyMembers[name] = { fullName = name }
		Equal(a:HandlePartyQuestShareMessage(SharePacket(a, "r" .. i), name, "PARTY"), i <= 10)
	end
	local count = 0
	for _ in pairs(a.partyQuestShareState.incoming) do
		count = count + 1
	end
	Equal(count, 10)
	a:Advance(61)
	Equal(next(a.partyQuestShareState.incoming), nil)
end)

-- Owned frame doubles model local vs inherited visibility and slider clamping.
-- Unknown members stay nil, so missing methods cannot silently pass as no-ops.
local function Frame(parent)
	local frame = {
		scripts = {},
		shown = true,
		enabled = true,
		value = 0,
		width = 1200,
		height = 800,
		parent = parent,
		children = {},
	}
	if parent then
		parent.children[#parent.children + 1] = frame
	end
	local methods = {}
	function methods:IsForbidden()
		return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
	end
	function methods:IsProtected()
		return self.protected == true or (self.parent and self.parent:IsProtected()) or false
	end
	function methods:SetScript(event, callback)
		self.scripts[event] = callback
	end
	function methods:CreateFontString()
		return Frame(self)
	end
	function methods:CreateTexture()
		return Frame(self)
	end
	function methods:GetFrameLevel()
		return self.frameLevel or (self.parent and self.parent:GetFrameLevel() + 1) or 1
	end
	function methods:SetFrameLevel(level) self.frameLevel = level end
	function methods:SetText(value)
		self.text = value
		if self.scripts.OnTextChanged then
			self.scripts.OnTextChanged(self)
		end
	end
	function methods:SetTextColor(...)
		self.textColor = { ... }
	end
	function methods:SetColorTexture(...)
		self.textureColor = { ... }
	end
	function methods:SetTexCoord(...)
		self.texCoords = { ... }
	end
	function methods:SetVertexColor(...)
		self.vertexColor = { ... }
	end
	function methods:GetText()
		return self.text or ""
	end
	function methods:SetPoint(...)
		self.points = self.points or {}
		self.points[#self.points + 1] = { ... }
	end
	function methods:ClearAllPoints()
		self.points = {}
	end
	function methods:SetWidth(value)
		self.width = value
	end
	function methods:SetHeight(value)
		self.height = value
	end
	function methods:SetSize(width, height)
		if self.resizeBounds then
			width = math.max(self.resizeBounds[1], math.min(self.resizeBounds[3], width))
			height = math.max(self.resizeBounds[2], math.min(self.resizeBounds[4], height))
		end
		self.width, self.height = width, height
		if self.scripts.OnSizeChanged then
			self.scripts.OnSizeChanged(self, width, height)
		end
	end
	function methods:SetResizeBounds(...)
		self.resizeBounds = { ... }
	end
	function methods:StartSizing(point, fromMouse)
		self.sizing = point
		self.sizingFromMouse = fromMouse
	end
	function methods:StopMovingOrSizing()
		self.sizing = nil
	end
	function methods:SetScale(value) self.scale = value end
	function methods:GetScale() return self.scale or 1 end

	function methods:GetWidth()
		return self.width
	end
	function methods:GetHeight()
		return self.height
	end
	function methods:GetStringHeight()
		return 180
	end
	function methods:SetChecked(value)
		self.checked = value
	end
	function methods:GetChecked()
		return self.checked
	end
	function methods:SetEnabled(value)
		self.enabled = value
	end
	function methods:SetValue(value)
		if self.minimum then
			value = math.max(self.minimum, math.min(self.maximum, value))
		end
		if self.value == value then
			return
		end
		self.value = value
		if self.scripts.OnValueChanged then
			self.scripts.OnValueChanged(self, value)
		end
	end
	function methods:SetMinMaxValues(minimum, maximum)
		self.minimum, self.maximum = minimum, maximum
		self:SetValue(self.value)
	end
	function methods:GetValue()
		return self.value
	end
	function methods:SetVerticalScroll(value)
		self.verticalScroll = value
	end
	function methods:SetHorizontalScroll(value)
		self.horizontalScroll = value
	end
	function methods:IsShown()
		return self.shown
	end
	function methods:IsVisible()
		return self.shown and (not self.parent or self.parent:IsVisible())
	end
	local function SetShown(self, shown)
		local previous = {}
		local function Gather(node)
			previous[#previous + 1] = { node = node, visible = node:IsVisible() }
			for _, child in ipairs(node.children) do
				Gather(child)
			end
		end
		Gather(self)
		self.shown = shown
		for _, old in ipairs(previous) do
			local visible = old.node:IsVisible()
			if visible ~= old.visible then
				local callback = old.node.scripts[visible and "OnShow" or "OnHide"]
				if callback then
					callback(old.node)
				end
			end
		end
	end
	function methods:Show()
		SetShown(self, true)
	end
	function methods:Hide()
		SetShown(self, false)
	end
	function methods:SetAtlas(atlas) self.atlas = atlas end
	function methods:GetAtlas() return self.atlas end
	function methods:SetTexture(texture) self.texture, self.atlas = texture, nil end
	function methods:SetDesaturated(value) self.desaturated = value end
	-- These presentation-only methods are intentionally stubbed; behavioral
	-- methods above are implemented and all other method names are rejected.
	for _, name in ipairs({
		"SetAutoFocus",
		"EnableKeyboard",
		"SetFontObject",
		"SetTextInsets",
		"HighlightText",
		"SetFocus",
		"Raise",
		"SetMaxLetters",
		"ClearFocus",
		"SetJustifyH",
		"SetJustifyV",
		"SetMaxLines",
		"SetFrameStrata",
		"SetWordWrap",
		"SetToplevel",
		"SetFlattensRenderLayers",
		"SetClampedToScreen",
		"SetMovable",
		"EnableMouse",
		"RegisterForDrag",
		"StartMoving",
		"SetResizable",
		"SetNormalTexture",
		"SetHighlightTexture",
		"SetPushedTexture",
		"SetBackdrop",
		"SetBackdropColor",
		"SetBackdropBorderColor",
		"SetAllPoints",
		"SetHorizTile",
		"SetVertTile",
		"SetOrientation",
		"SetThumbTexture",
		"SetScrollChild",
		"SetValueStep",
		"SetObeyStepOnDrag",
		"EnableMouseWheel",
	}) do
		methods[name] = function() end
	end
	return setmetatable(frame, { __index = methods })
end

local function AttachUI(addon)
	local parent = Frame()
	function addon:GetPartyQuestUIParent()
		return parent
	end
	function addon:CanAccessForeignFrame()
		return true
	end
	function addon:CreatePartyQuestUIFrame(_, _, owner)
		return Frame(owner)
	end
	return parent
end

QuestTogether:RegisterTest(
	"party chat reminder renders choices resets checkbox and safely dismisses during restrictions",
	function()
		local a = Fixture()
		AttachUI(a)
		a.db = { profile = {} }
		a.options.announceToNonQTParty = true
		a.suppressLocalAnnouncementDisplayDuringTests = false
		function a:GetNonQTPartyMembers()
			return { "Friend-Realm" }
		end
		function a:IsRuntimeRestrictionTypeActive()
			return false
		end
		function a:RefreshOptionsWindow() end
		a:UpdatePartyChatReminder()
		a.now = a.now + 10
		a:UpdatePartyChatReminder()
		local frame = a.partyChatReminderFrame
		assert(frame:IsShown())
		Equal(frame.remember:GetChecked(), false)
		assert(frame.members.text:find("Friend-Realm", 1, true))
		frame.remember:SetChecked(true)
		a.blocked = true
		frame.close.scripts.OnClick()
		Equal(frame:IsShown(), false)
		Equal(a.options.hidePartyChatReminder, nil)
		a.blocked = false
		a:UpdatePartyChatReminder()
		Equal(frame:IsShown(), true)
		frame.keep.scripts.OnClick()
		Equal(frame:IsShown(), false)
		Equal(a.options.hidePartyChatReminder, true)
		Equal(a.options.announceToNonQTParty, true)
		a.options.hidePartyChatReminder = false
		a:ResetPartyChatReminder()
		a:UpdatePartyChatReminder()
		a.now = a.now + 10
		a:UpdatePartyChatReminder()
		Equal(frame.remember:GetChecked(), false)
		frame.disable.scripts.OnClick()
		Equal(a.options.announceToNonQTParty, false)
		Equal(frame:IsShown(), false)
		a:RenderPartyChatReminder(nil)
	end
)

QuestTogether:RegisterTest(
	"party chat preview command is isolated from real acknowledgements settings and normal help",
	function()
		local a = Fixture()
		AttachUI(a)
		a.db = { profile = {} }
		a.printed = {}
		function a:Print(text)
			self.printed[#self.printed + 1] = text
		end
		function a:GetNonQTPartyMembers()
			error("preview must not inspect party")
		end
		local real = { request = {} }
		a.partyChatReminderState = real
		assert(a:HandleSlashCommand("partychatpreview"))
		local frame = a.partyChatReminderPreviewFrame
		assert(frame:IsShown())
		frame.remember:SetChecked(true)
		frame.disable.scripts.OnClick()
		Equal(frame:IsShown(), false)
		Equal(a.options.announceToNonQTParty, nil)
		Equal(a.options.hidePartyChatReminder, nil)
		Equal(a.partyChatReminderState, real)
		Equal(#a.wire, 0)
		assert(a:ShowPartyChatReminderPreview())
		Equal(frame.remember:GetChecked(), false)
		frame.keep.scripts.OnClick()
		Equal(a.partyChatReminderState, real)
		a:PrintHelp()
		assert(not table.concat(a.printed, "\n"):find("partychatpreview", 1, true))
		a:PrintDebugHelp()
		assert(table.concat(a.printed, "\n"):find("/qt preview share|join|partychat", 1, true))
		a.blocked = true
		Equal(a:ShowPartyChatReminderPreview(), false)
		Equal(frame:IsShown(), false)
	end
)

QuestTogether:RegisterTest("comparison titles refresh on load results and drain a bounded load queue", function()
	local a = Fixture()
	AttachUI(a)
	a.QueuePartyQuestCompareRender = QuestTogether.QueuePartyQuestCompareRender
	local loaded, requests = {}, {}
	function a:GetQuestSnapshot()
		return nil
	end
	a.API.GetLocalizedQuestTitle = function(id)
		return loaded[id]
	end
	a.API.RequestLocalizedQuestTitle = function(id)
		requests[#requests + 1] = id
	end
	a:OpenPartyQuestCompare()
	local remote = {}
	for id = 1, 12 do
		remote[id] = Quest(id, "Foreign title " .. id)
	end
	Reply(a, "Friend-Realm", remote, true, true)
	a:Advance(0.1)
	Equal(#requests, 10)
	local id = a.partyQuestCompareWindow.rows[1].data.questId
	loaded[id] = "A loaded local title"
	a:QUEST_DATA_LOAD_RESULT(nil, id, true)
	a:Advance(0.1)
	local displayed = false
	for _, row in ipairs(a.partyQuestCompareWindow.rows) do
		if row.data and row.data.questId == id then
			Equal(row.title.text, "A loaded local title")
			displayed = true
		end
	end
	assert(displayed, "native load completion must replace the displayed fallback immediately")
	local wires = #a.wire
	for _ = 1, 8 do
		a:Advance(30)
	end
	local counts = {}
	for _, questID in ipairs(requests) do
		counts[questID] = (counts[questID] or 0) + 1
	end
	for questID = 1, 12 do
		Equal(counts[questID], questID == id and 1 or 2)
	end
	Equal(#a.wire, wires, "title refresh must not request new remote snapshots")
	assert(not a.partyQuestCompareSession.titleRefreshPending)
	local total = #requests
	a:Advance(90)
	Equal(#requests, total)
end)

QuestTogether:RegisterTest("quest title load events guard restrictions and cannot revive closed comparisons", function()
	local a = Fixture()
	AttachUI(a)
	a.QueuePartyQuestCompareRender = QuestTogether.QueuePartyQuestCompareRender
	local title
	function a:GetQuestSnapshot()
		return nil
	end
	a.API.GetLocalizedQuestTitle = function()
		return title
	end
	a.API.RequestLocalizedQuestTitle = function() end
	a:OpenPartyQuestCompare()
	Reply(a, "Friend-Realm", { Quest(1, "Sent title") }, true, true)
	a:Advance(0.1)
	Equal(a.partyQuestCompareWindow.rows[1].title.text, "Sent title")
	title = "Local title"
	a:QUEST_DATA_LOAD_RESULT(nil, 1, false)
	a:Advance(0.1)
	Equal(a.partyQuestCompareWindow.rows[1].title.text, "Sent title")
	a.blocked = true
	a:QUEST_DATA_LOAD_RESULT(nil, 1, true)
	a:Advance(0.1)
	Equal(a.partyQuestCompareWindow.rows[1].title.text, "Sent title")
	a.blocked = false
	a:FlushDeferredWork("test resume")
	Equal(a.partyQuestCompareWindow.rows[1].title.text, "Local title")
	-- Queue another result, then close before its callback executes.
	a.localizedQuestTitles.entries[1].title = nil
	a:QUEST_DATA_LOAD_RESULT(nil, 1, true)
	a:CancelPartyQuestCompare()
	a.partyQuestCompareWindow:Hide()
	a:Advance(60)
	assert(not a.partyQuestCompareSession and not a.partyQuestCompareWindow:IsShown())
	-- Replacing a session before a queued render must not render its successor.
	a:OpenPartyQuestCompare()
	a:Advance(0.1)
	a:QueuePartyQuestCompareRender()
	a:CancelPartyQuestCompare()
	a.partyQuestCompareSession = { members = {} }
	function a:RenderPartyQuestCompare()
		error("stale render reached replacement session")
	end
	a:Advance(0.1)
end)

QuestTogether:RegisterTest(
	"party compare vertical scrollbar follows filtered rows and resets a collapsed range",
	function()
		local entries = {}
		for id = 1, 11 do
			entries[id] = Quest(id)
		end
		local a = Fixture(nil, entries)
		AttachUI(a)
		a:OpenPartyQuestCompare()
		local frame = a.partyQuestCompareWindow
		Equal(frame.vertical:IsShown(), false)
		Equal(frame.horizontal:IsShown(), false)
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), false) -- Exactly one full page fits.
		Reply(a, "Friend-Realm", { Quest(14), Quest(15) }, true, true)
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), true)
		Equal(frame.horizontal:IsShown(), false)
		frame.vertical:SetValue(1 * 42)
		Equal(a.partyQuestCompareSession.offset, 1)
		a:SetPartyQuestCompareFilter("ownership", "mine")
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), false)
		Equal(frame.vertical:GetValue(), 0)
		Equal(a.partyQuestCompareSession.offset, 0)
		a:SetPartyQuestCompareFilter("ownership", "all")
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), true)
		frame.refresh.scripts.OnClick()
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), true) -- Retain old rows while fresh data is pending.
	end
)

QuestTogether:RegisterTest(
	"party compare horizontal scrollbar follows column overflow independently of rows",
	function()
		local a = Fixture(nil, { Quest(1) })
		local parent = AttachUI(a)
		parent:SetSize(1920, 1200)
		a:OpenPartyQuestCompare()
		a:RenderPartyQuestCompare()
		local frame = a.partyQuestCompareWindow
		a:Roster(a.name, "Friend-Realm", "Third-Realm", "Fourth-Realm", "Fifth-Realm", "Sixth-Realm")
		a:OnPartyQuestRosterChanged()
		a:RenderPartyQuestCompare()
		local originalWidth = frame:GetWidth()
		-- Wide viewports stretch the action area; find the fixed column minimum.
		frame:SetSize(780, frame:GetHeight())
		a:RenderPartyQuestCompare()
		frame:SetSize(frame.content:GetWidth() + 62, frame:GetHeight())
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), false) -- Exactly fitting columns need no bar.
		frame:SetSize(frame.content:GetWidth() + 61, frame:GetHeight())
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), true)
		Equal(frame.vertical:IsShown(), false)
		frame.horizontal:SetValue(1)
		Equal(frame.viewport.horizontalScroll, 1)
		frame:SetSize(originalWidth, frame:GetHeight())
		a:Roster(a.name, "Friend-Realm")
		a:OnPartyQuestRosterChanged()
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), false)
		Equal(frame.horizontal:GetValue(), 0)
		Equal(frame.viewport.horizontalScroll, 0)
		a:Roster(a.name, "Friend-Realm", "Third-Realm", "Fourth-Realm", "Fifth-Realm", "Sixth-Realm")
		a:OnPartyQuestRosterChanged()
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), true)
		frame.horizontal:SetValue(20)
		Equal(frame.viewport.horizontalScroll, 20)
		a:Roster(a.name, "Friend-Realm")
		a:OnPartyQuestRosterChanged()
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), false)
		Equal(frame.vertical:IsShown(), false)
		Equal(frame.horizontal:GetValue(), 0)
		Equal(frame.viewport.horizontalScroll, 0)
	end
)

QuestTogether:RegisterTest("party diff UI renders a bounded row pool and filter and share callbacks", function()
	local a = Fixture(nil, { Quest(1, "Share me", true) })
	function a:GetPartyQuestUIParent()
		return Frame()
	end
	function a:CanAccessForeignFrame()
		return true
	end
	function a:CreatePartyQuestUIFrame()
		return Frame()
	end
	a:OpenPartyQuestCompare()
	Reply(a, "Friend-Realm", { Quest(2, "Request me", true) }, true, true)
	a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	Equal(#frame.rows, 26)
	Equal(frame.title.text, "Party Quest Log")
	Equal(frame.filter.text, "Filters")
	Equal(frame.filter.text, "Filters")
	Equal(#a:BuildPartyQuestDiffRows(), 2)
	a:SetPartyQuestCompareFilter("ownership", "mine")
	a:RenderPartyQuestCompare()
	Equal(a:GetOption("compareHideOtherQuests"), true)
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	Equal(frame.rows[1].action.text, "Share")
	frame.rows[1].action.scripts.OnClick()
	Equal(a.pushes, 1)
	a:SetPartyQuestCompareFilter("ownership", "all")
	a:RenderPartyQuestCompare()
	Equal(frame.rows[1].action.text, "Request Share")
	frame.rows[1].action.scripts.OnClick()
	Equal(a:GetPartyQuestShareStatus(2), "Request sent")
	a:RenderPartyQuestCompare()
	Equal(frame.rows[1].hint.text, "Request sent")
	frame:Hide()
	Equal(a.partyQuestCompareSession, nil)
end)

QuestTogether:RegisterTest("party compare empty-state guidance matches the hide filter", function()
	local a = Fixture()
	AttachUI(a)
	a:OpenPartyQuestCompare()
	a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	Equal(frame.filter.text, "Filters")
	Equal(frame.summary.text, "No quests to display.")
	Reply(a, "Friend-Realm", { Quest(2, "Their quest", true) }, true, true)
	a:RenderPartyQuestCompare()
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	a:SetPartyQuestCompareFilter("ownership", "mine")
	a:RenderPartyQuestCompare()
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	Equal(frame.summary.text, "No quests match. Try another search or reset the filters.")
	a:SetPartyQuestCompareFilter("ownership", "all")
	a:RenderPartyQuestCompare()
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	assert(not frame.summary.text:find("Uncheck", 1, true))
end)

QuestTogether:RegisterTest("party share consent UI resets checkbox between requests and hides on expiry", function()
	local a = Fixture(nil, { Quest(1, "Share me", true) })
	function a:GetPartyQuestUIParent()
		return Frame()
	end
	function a:CanAccessForeignFrame()
		return true
	end
	function a:CreatePartyQuestUIFrame()
		return Frame()
	end
	function a:GetQuestTitle()
		return "Share me"
	end
	a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY")
	a:RenderPartyQuestSharePrompt()
	local frame = a.partyQuestSharePrompt
	Equal(frame.always.checked, false)
	frame.always:SetChecked(true)
	a:FinishPartyQuestShare(frame.request, "declined")
	a:RenderPartyQuestSharePrompt()
	Equal(frame.shown, false)
	a:Advance(6)
	a:HandlePartyQuestShareMessage(SharePacket(a, "r2"), "Friend-Realm", "PARTY")
	a:RenderPartyQuestSharePrompt()
	Equal(frame.always.checked, false)
	a:Advance(61)
	a:RenderPartyQuestSharePrompt()
	Equal(frame.shown, false)
end)

local function PreviewFixture()
	local addon = Fixture()
	addon.createdFrames = 0
	function addon:GetPartyQuestUIParent()
		return Frame()
	end
	function addon:CanAccessForeignFrame()
		return true
	end
	function addon:CreatePartyQuestUIFrame()
		self.createdFrames = self.createdFrames + 1
		return Frame()
	end
	local function RejectLiveAccess()
		error("preview must not access live quest, sharing or saved-option paths")
	end
	for _, method in ipairs({
		"RefreshPartyRoster",
		"RequestQuestCompare",
		"GetQuestShareAvailability",
		"SharePartyDiffQuest",
		"RequestPartyQuestShare",
		"SendPartyQuestShareMessage",
		"GetPartyQuestShareStatus",
		"SendWireMessageToAnnouncementRoutes",
		"SetOption",
	}) do
		addon[method] = RejectLiveAccess
	end
	function addon:BuildQuestCompareEntries() return nil end -- Standalone fictional fixture.
	addon.API.PushQuestToParty = RejectLiveAccess
	return addon
end

QuestTogether:RegisterTest("compare debug command renders the full mock UI without live state or settings", function()
	local a = PreviewFixture()
	a.isEnabled = false -- A visual preview also works solo with runtime features off.
	a.options.compareHideOtherQuests = true
	local liveSession = { members = {}, marker = "live" }
	local liveShares = { outgoing = { untouched = true } }
	a.partyQuestCompareSession, a.partyQuestShareState = liveSession, liveShares
	a.pendingQuestCompareRequests.keep = { marker = "pending" }
	assert(a:HandleSlashCommand("  preview   COMPARE  "))
	local preview, livePending = a.partyQuestComparePreview, a.pendingQuestCompareRequests.keep
	local frame = preview.partyQuestCompareWindow
	Equal(frame.shown, true)
	Equal(frame.title.text, "Party Quest Log — Debug Preview")
	Equal(#frame.rows, 26)
	Equal(#preview.partyQuestCompareSession.members, 5)
	Equal(preview.partyQuestCompareSession.members[4].classFile, "HUNTER")
	Equal(preview.partyQuestCompareSession.members[5].classFile, "ROGUE")
	assert(frame.headerCrowns[1]:IsShown())
	for i = 2, 5 do assert(not frame.headerCrowns[i]:IsShown()) end
	Equal(#preview:BuildPartyQuestDiffRows(), 16)
	Equal(frame.filter.text, "Filters")
	Equal(a.options.compareHideOtherQuests, true)
	local statuses, actions = {}, {}
	for _, row in ipairs(preview:BuildPartyQuestDiffRows()) do
		for _, status in ipairs(row.cells) do
			statuses[status] = true
		end
		if row.action then
			actions[row.action] = true
		end
	end
	for _, status in ipairs({ "Have", "Ready", "Missing" }) do
		assert(statuses[status])
	end
	assert(actions.share and actions.request)
	assert(not statuses.Loading and not statuses.Unknown, "the sample is a synced questing party")
	local shared = 0
	for _, row in ipairs(preview:BuildPartyQuestDiffRows()) do
		if row.missing == 0 then
			shared = shared + 1
		end
	end
	assert(shared > #preview:BuildPartyQuestDiffRows() / 2, "most quests should overlap")
	assert(frame.content.width <= frame.viewport.width, "a typical party should fit without horizontal scrolling")
	frame.vertical:SetValue(3 * 42)
	Equal(preview.partyQuestCompareSession.offset, 3)
	assert(frame.summary.text:find("DEBUG PREVIEW", 1, true))
	Equal(a.partyQuestCompareSession, liveSession)
	Equal(a.partyQuestShareState, liveShares)
	Equal(a.pendingQuestCompareRequests.keep, livePending)
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
	Equal(#a.delayed, 0)
end)

QuestTogether:RegisterTest("compare preview uses client appropriate names for headers leader and following", function()
	for _, regional in ipairs({ false, true }) do
		local a = PreviewFixture()
		a.API.RegionalUniqueNamesEnabled = function() return regional end
		assert(a:OpenPartyQuestComparePreview())
		local p = a.partyQuestComparePreview
		local expected = regional
			and { "Rowan Lightward", "Aria Frostwind", "Borin Ironvale", "Celia Wildwood", "Dara Nightfall" }
			or { "Rowan-AeriePeak", "Aria-AeriePeak", "Borin-AeriePeak", "Celia-AeriePeak", "Dara-AeriePeak" }
		for i, name in ipairs(expected) do
			Equal(p.partyQuestCompareSession.members[i].name, name)
			Equal(p.partyQuestCompareSession.byName[name], p.partyQuestCompareSession.members[i])
		end
		Equal(p:GetPartyQuestLeaderName(), expected[1])
		assert(p.partyQuestCompareWindow.headerCrowns[1]:IsShown())
		local menu = {}
		function menu:CreateTitle() end
		function menu:CreateButton(_, click) self.click = click end
		p:PopulatePartyFocusMenu(menu, expected[2])
		menu.click()
		Equal(p.previewFollowing, expected[2])
		Equal(p.previewFocus, 2)
		assert(p:GetPartyFollowingText():find(expected[2], 1, true))
		p:RefreshPartyQuestCompare()
		Equal(p.partyQuestCompareSession.members[2].name, expected[2])
		Equal(p:GetPartyQuestLeaderName(), expected[1])
		Equal(#a.wire, 0)
		Equal(a.pushes, 0)
	end
end)

QuestTogether:RegisterTest("compare preview actions simulate feedback and Refresh and filter stay private", function()
	local a = PreviewFixture()
	assert(a:OpenPartyQuestComparePreview())
	local preview, share, request = a.partyQuestComparePreview
	local frame = preview.partyQuestCompareWindow
	for _, row in ipairs(frame.rows) do
		if row.data and row.data.action == "share" and not share then
			share = row
		end
		if row.data and row.data.action == "request" and not request then
			request = row
		end
	end
	assert(share and request)
	local sharedID, requestedID = share.data.questId, request.data.questId
	share.action.scripts.OnClick()
	Equal(share.hint.text, "Share attempted")
	request.action.scripts.OnClick()
	Equal(request.hint.text, "Awaiting confirmation")
	assert(frame.summary.text:find("Preview only", 1, true))
	preview:SetPartyQuestCompareFilter("ownership", "mine")
	for _, row in ipairs(preview:BuildPartyQuestDiffRows()) do
		assert(
			preview.partyQuestCompareSession.byName[preview.partyQuestCompareSession.playerName].entries[row.questId]
		)
	end
	Equal(a.options.compareHideOtherQuests, nil)
	frame.refresh.scripts.OnClick()
	Equal(preview.statuses[sharedID], nil)
	Equal(preview.statuses[requestedID], nil)
	Equal(preview.partyQuestCompareSession.offset, 0)
	Equal(frame.horizontal.value, 0)
	Equal(frame.filter.text, "Filters (1)")
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest("compare preview reuses its window and cancels closed and restricted actions", function()
	local a = PreviewFixture()
	assert(a:OpenPartyQuestComparePreview())
	local preview = a.partyQuestComparePreview
	local frame, created = preview.partyQuestCompareWindow, a.createdFrames
	local shareRow
	for _, row in ipairs(frame.rows) do
		if row.data and row.data.action == "share" then
			shareRow = row
			break
		end
	end
	assert(shareRow)
	local questID, callback = shareRow.data.questId, shareRow.action.scripts.OnClick
	frame:Hide()
	Equal(preview.partyQuestCompareSession, nil)
	callback()
	Equal(preview.statuses[questID], nil, "a stale row callback must not act after close")
	assert(a:OpenPartyQuestComparePreview())
	Equal(a.partyQuestComparePreview, preview)
	Equal(a.createdFrames, created)
	a.blocked = true
	callback()
	Equal(preview.statuses[questID], nil)
	a.blocked = false
	a:ResetPartyQuestCompare()
	Equal(frame.shown, false)
	Equal(preview.partyQuestCompareSession, nil)
	assert(a:OpenPartyQuestComparePreview())
	function a:OpenPartyQuestCompare()
		return "live"
	end
	Equal(a:HandleSlashCommand("compare"), "live")
	Equal(frame.shown, false)
	Equal(preview.partyQuestCompareSession, nil)
end)

QuestTogether:RegisterTest("compare preview refuses restricted creation without creating UI or work", function()
	local a = PreviewFixture()
	a.blocked = true
	local printed
	function a:Print(message)
		printed = message
	end
	Equal(a:OpenPartyQuestComparePreview(), false)
	assert(printed:find("restricted", 1, true))
	Equal(rawget(a, "partyQuestComparePreview"), false)
	Equal(a.createdFrames, 0)
	Equal(#a.wire, 0)
	Equal(#a.delayed, 0)
end)

QuestTogether:RegisterTest("party diff local snapshots recover through the real restriction work policy", function()
	for _, restriction in ipairs({ "map", "combat" }) do
		local a = Fixture(nil, { Quest(1, "Local", true) })
		AttachUI(a)
		a.QueuePartyQuestCompareRender = QuestTogether.QueuePartyQuestCompareRender
		if restriction == "map" then
			a.mapVisible = true
		end
		assert(a:OpenPartyQuestCompare())
		if restriction == "combat" then
			a.blocked = true
			a:Roster(a.name, "Friend-Realm", "Third-Realm")
			a:OnPartyQuestRosterChanged()
		end
		local session = a.partyQuestCompareSession
		Equal(session.byName[a.name].state, "loading")
		local reads = a.snapshotReads or 0
		a:Advance(1)
		Equal(a.snapshotReads or 0, reads, "restricted reads must remain deferred")
		if restriction == "map" then
			assert(a.mapWakeups > 0)
		end
		a.mapVisible, a.blocked = false, false
		a:FlushDeferredWork("restriction ended")
		a:Advance(0.1)
		Equal(a.snapshotReads, reads + 1)
		Equal(session.byName[a.name].state, "ready")
		Equal(a.partyQuestCompareWindow.rows[1].data.questId, 1)
		Equal(a.pushes, 0)
	end
end)

QuestTogether:RegisterTest("party diff deferred local reads belong to one comparison lifetime", function()
	local a = Fixture(nil, { Quest(1) })
	a.mapVisible = true
	a:RefreshPartyQuestCompare()
	local old = a.partyQuestCompareSession
	local oldWork
	for _, work in pairs(a.workState.entries) do
		if work.key == "party_compare_local" then
			oldWork = work
		end
	end
	assert(oldWork)
	a:RefreshPartyQuestCompare()
	a.mapVisible = false
	oldWork.callback()
	Equal(a.snapshotReads, nil)
	Equal(old.byName[a.name].state, "loading")
	a:FlushDeferredWork("map closed")
	Equal(a.snapshotReads, 1)
	Equal(a.partyQuestCompareSession.byName[a.name].state, "ready")
	a:OnPartyQuestLogChanged()
	a:CancelPartyQuestCompare()
	a:Advance(1)
	Equal(a.snapshotReads, 1)
	a:RefreshPartyQuestCompare()
	a:OnPartyQuestLogChanged()
	a:ResetPartyQuestCompare()
	a:Advance(1)
	Equal(a.snapshotReads, 2)
end)

QuestTogether:RegisterTest(
	"party share successive quests wait for their owner cooldown without delayed sends",
	function()
		local a = Fixture("Me-Realm")
		local b = Fixture("Friend-Realm", { Quest(1, "First", true), Quest(2, "Second", true) })
		a:Roster(a.name, b.name)
		b:Roster(a.name, b.name)
		a.options.compareHideOtherQuests = false
		a:RefreshPartyQuestCompare()
		Reply(a, b.name, b.entries, true, true)
		local function Deliver(sender, receiver)
			receiver:OnCommReceived(receiver.commPrefix, sender.wire[#sender.wire], "PARTY", sender.name)
		end
		assert(a:RequestPartyQuestShare(1, b.name))
		Deliver(a, b)
		Deliver(b, a)
		Equal(a:GetPartyQuestShareStatus(1), "Awaiting confirmation")
		local sent = #a.wire
		a:Advance(1)
		b:Advance(1)
		Equal(a:RequestPartyQuestShare(2, b.name), false)
		Equal(#a.wire, sent)
		Equal(a:GetPartyQuestShareStatus(2), nil)
		assert(a:GetPartyQuestShareRequestCooldown(b.name) > 0)
		local renders = a.renders
		a:Advance(5)
		b:Advance(5)
		assert(a.renders > renders, "cooldown expiry must refresh disabled buttons")
		Equal(#a.wire, sent, "expiry must never send or share for the user")
		Equal(b.pushes, 0)
		Equal(a:GetPartyQuestShareRequestCooldown(b.name), 0)
		assert(a:RequestPartyQuestShare(2, b.name))
		Deliver(a, b)
		Deliver(b, a)
		Equal(a:GetPartyQuestShareStatus(2), "Awaiting confirmation")
		local count = 0
		for _ in pairs(b.partyQuestShareState.incoming) do
			count = count + 1
		end
		Equal(count, 2)
	end
)

QuestTogether:RegisterTest(
	"party share admission failures reply and rejected requests never become later approvals",
	function()
		for _, reason in ipairs({ "cooldown", "queue", "replay capacity" }) do
			local a, b = Fixture("Me-Realm"), Fixture("Friend-Realm", { Quest(1, "Remote", true) })
			a:Roster(a.name, b.name)
			b:Roster(a.name, b.name)
			a.options.compareHideOtherQuests = false
			a:RefreshPartyQuestCompare()
			Reply(a, b.name, b.entries, true, true)
			local state = b:GetPartyQuestShareState()
			if reason == "cooldown" then
				state.peers[a.name] = b.now + 5
			end
			if reason == "queue" then
				for i = 1, 10 do
					state.incoming["occupied" .. i] = { expires = b.now + 60 }
				end
			end
			if reason == "replay capacity" then
				for i = 1, 128 do
					state.recent["old" .. i] = b.now + 120
				end
			end
			assert(a:RequestPartyQuestShare(1, b.name))
			local wire = a.wire[#a.wire]
			b:OnCommReceived(b.commPrefix, wire, "PARTY", a.name)
			Equal(#b.wire, 1)
			a:OnCommReceived(a.commPrefix, b.wire[1], "PARTY", b.name)
			local status, waiting = a:GetPartyQuestShareStatus(1)
			Equal(status, "Sharing unavailable")
			Equal(waiting, false)
			Equal(b.pushes, 0)
			-- Replay suppression remains bounded. An admitted replay-cache entry
			-- also rejects the same request after the cooldown/queue frees up.
			if reason ~= "replay capacity" then
				state.incoming = {}
				b:Advance(6)
				b.options.autoAcceptPartyShareRequests = true
				b:OnCommReceived(b.commPrefix, wire, "PARTY", a.name)
				Equal(b.pushes, 0)
				Equal(#b.wire, 1)
			end
		end
	end
)

QuestTogether:RegisterTest("party diff inherited visibility preserves sessions but explicit close cancels", function()
	for _, kind in ipairs({ "live", "preview" }) do
		local a = Fixture(nil, { Quest(1, "Local", true) })
		local parent = AttachUI(a)
		local controller = a
		if kind == "live" then
			assert(a:OpenPartyQuestCompare())
			a:RenderPartyQuestCompare()
		else
			assert(a:OpenPartyQuestComparePreview())
			controller = a.partyQuestComparePreview
		end
		local frame, session = controller.partyQuestCompareWindow, controller.partyQuestCompareSession
		parent:Hide()
		assert(frame:IsShown() and not frame:IsVisible())
		Equal(controller.partyQuestCompareSession, session)
		parent:Show()
		assert(frame:IsVisible())
		Equal(controller.partyQuestCompareSession, session)
		parent:Hide()
		frame.close.scripts.OnClick()
		Equal(controller.partyQuestCompareSession, nil)
		Equal(frame:IsShown(), false)
		parent:Show()
		Equal(frame:IsVisible(), false)
	end
end)

QuestTogether:RegisterTest("party diff renders cooldown and terminal feedback beside retry actions", function()
	local a = Fixture()
	AttachUI(a)
	a.options.compareHideOtherQuests = false
	a:OpenPartyQuestCompare()
	Reply(a, "Friend-Realm", { Quest(1, "First", true), Quest(2, "Second", true) }, true, true)
	assert(a:RequestPartyQuestShare(1, "Friend-Realm"))
	a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	Equal(frame.rows[2].action.enabled, false)
	Equal(frame.rows[2].action.text, "Please wait")
	a:Advance(6)
	a:RenderPartyQuestCompare()
	Equal(frame.rows[2].action.enabled, true)
	Equal(frame.rows[2].action.text, "Request Share")
	local id = next(a.partyQuestShareState.outgoing)
	a:HandlePartyQuestShareMessage(SharePacket(a, id, 1, "declined"), "Friend-Realm", "PARTY")
	a:RenderPartyQuestCompare()
	assert(frame.rows[1].action.shown and frame.rows[1].action.enabled)
	assert(frame.rows[1].hint.shown)
	Equal(frame.rows[1].hint.text, "Request declined")
	assert(a:RequestPartyQuestShare(1, "Friend-Realm"))
	a:Advance(61)
	a:RenderPartyQuestCompare()
	assert(frame.rows[1].action.shown and frame.rows[1].action.enabled)
	assert(frame.rows[1].hint.shown)
	Equal(frame.rows[1].hint.text, "Request expired")
	Equal(frame.rows[1].action.text, "Request Share")
	assert(a:RequestPartyQuestShare(1, "Friend-Realm"))
	a:RenderPartyQuestCompare()
	Equal(frame.rows[1].action.shown, false)
	Equal(frame.rows[1].hint.text, "Request sent")
end)

-- These transport fixtures use the production route sender and receive parser;
-- only the native send/join adapters are private, with no game globals replaced.
local function TargetFixture(name, entries)
	local addon = Fixture(name, entries)
	AttachUI(addon)
	addon.packets, addon.notices = {}, {}
	addon.announcementChannelName, addon.announcementChannelLocalID = "QuestTogether", 7
	addon.SendWireMessageToAnnouncementRoutes = QuestTogether.SendWireMessageToAnnouncementRoutes
	function addon:EnsureAnnouncementChannelJoined()
		return not self.channelUnavailable
	end
	function addon:GetAnnouncementChannelTarget()
		return self.announcementChannelLocalID
	end
	function addon:Print(message)
		self.notices[#self.notices + 1] = message
	end
	addon.API.SendAddonMessage = function(_, message, distribution, target)
		addon.wire[#addon.wire + 1] = message
		addon.packets[#addon.packets + 1] = { message = message, distribution = distribution, target = target }
		return addon.sendFails and 2 or 0
	end
	return addon
end

local function DeliverTargetPacket(sender, receiver, index, transportSender, channelName)
	local packet = sender.packets[index]
	receiver:OnCommReceived(
		receiver.commPrefix,
		packet.message,
		packet.distribution,
		transportSender or sender.name,
		7,
		channelName or "QuestTogether"
	)
end

QuestTogether:RegisterTest(
	"target compare authenticates nonparty channel snapshots and isolates selected full identity",
	function()
		local a = TargetFixture("Anakin Ofthesea", { Quest(1, "Local", true) })
		local b = TargetFixture("Anakin Othername", { Quest(2, "Remote", true) })
		a:Roster(a.name, "Third Person")
		b:Roster(b.name)
		b.grouped = false
		assert(a:OpenPlayerQuestCompare(b.name))
		local session = a.partyQuestCompareSession
		Equal(session.mode, "target")
		Equal(session.targetName, b.name)
		Equal(#session.members, 2)
		Equal(session.members[2].name, b.name)
		Equal(session.byName["Third Person"], nil)
		Equal(#a.packets, 1)
		Equal(a.packets[1].distribution, "CHANNEL")
		Equal(a.packets[1].target, 7)
		DeliverTargetPacket(a, b, 1, nil, "OtherChannel")
		Equal(#b.packets, 0)
		DeliverTargetPacket(a, b, 1)
		b:Advance(0.2)
		Equal(#b.packets, 2)
		Equal(b.packets[1].distribution, "CHANNEL")
		Equal(b.packets[2].distribution, "CHANNEL")
		DeliverTargetPacket(b, a, 1, "Anakin Impostor")
		Equal(next(session.members[2].entries), nil)
		-- Completion can arrive first; absence becomes evidence only after all rows.
		DeliverTargetPacket(b, a, 2)
		Equal(session.members[2].state, "loading")
		DeliverTargetPacket(b, a, 1)
		Equal(session.members[2].state, "ready")
		Equal(session.members[2].supportsShareRequests, true)
		local rows = a:BuildPartyQuestDiffRows()
		Equal(#rows, 2)
		for _, row in ipairs(rows) do
			Equal(row.action, nil)
			Equal(row.hint, "Join a party together to share quests.")
		end
		Equal(a:SharePartyDiffQuest(1), false)
		Equal(a:RequestPartyQuestShare(2, b.name), false)
		Equal(a.pushes, 0)
		Equal(#a.packets, 1)
		a:RenderPartyQuestCompare()
		Equal(a.partyQuestCompareWindow.title.text, "Compare Quests")
		assert(string.find(a.partyQuestCompareWindow.summary.text, "Join a party together", 1, true))
		Equal(a.partyQuestCompareWindow.rows[1].action.shown, false)
	end
)

QuestTogether:RegisterTest(
	"target compare roster refresh switches routes without expanding selected comparison",
	function()
		local a = TargetFixture(nil, { Quest(1, "Local", true) })
		a:Roster(a.name, "Friend-Realm", "Third-Realm")
		assert(a:OpenPlayerQuestCompare("Friend-Realm"))
		Equal(a.packets[1].distribution, "PARTY")
		Equal(#a.packets, 1)
		Reply(a, "Friend-Realm", {}, true, true)
		Equal(a:BuildPartyQuestDiffRows()[1].action, "share")
		a:RenderPartyQuestCompare()
		local staleAction = a.partyQuestCompareWindow.rows[1].action.scripts.OnClick
		local oldSession = a.partyQuestCompareSession
		a:Roster(a.name, "Third-Realm")
		-- Membership is rechecked even before the roster event refreshes the UI.
		Equal(a:SharePartyDiffQuest(1), false)
		a:OnPartyQuestRosterChanged()
		Equal(#a.partyQuestCompareSession.members, 2)
		Equal(a.partyQuestCompareSession.targetName, "Friend-Realm")
		Equal(a.packets[#a.packets].distribution, "CHANNEL")
		assert(a.partyQuestCompareSession ~= oldSession)
		staleAction()
		Equal(a.pushes, 0)
		a:Roster(a.name, "Friend-Realm", "Third-Realm")
		a:OnPartyQuestRosterChanged()
		Equal(#a.partyQuestCompareSession.members, 2)
		Equal(a.packets[#a.packets].distribution, "PARTY")
		Reply(a, "Friend-Realm", {}, true, true)
		a:RenderPartyQuestCompare()
		a.partyQuestCompareWindow.rows[1].action.scripts.OnClick()
		Equal(a.pushes, 1)
		assert(a:OpenPartyQuestCompare())
		Equal(a.partyQuestCompareSession.mode, "party")
		Equal(#a.partyQuestCompareSession.members, 3)
		a:RenderPartyQuestCompare()
		Equal(a.partyQuestCompareWindow.title.text, "Party Quest Log")
	end
)

QuestTogether:RegisterTest("target compare refresh replacement close and disable reject late callbacks", function()
	local a = TargetFixture()
	assert(a:OpenPlayerQuestCompare("Nearby-Realm"))
	local oldSession = a.partyQuestCompareSession
	local oldId = oldSession.members[2].requestId
	local oldReceiver = a.pendingQuestCompareRequests[oldId].receiver
	a.partyQuestCompareWindow.refresh.scripts.OnClick()
	Equal(a.partyQuestCompareSession.targetName, "Nearby-Realm")
	Equal(a.pendingQuestCompareRequests[oldId], nil)
	oldReceiver.onEntry(Quest(1, "Stale", true))
	oldReceiver.onDone(true)
	Equal(next(oldSession.members[2].entries), nil)
	Equal(oldSession.members[2].state, "loading")
	assert(a:OpenPlayerQuestCompare("Other-Realm"))
	local session = a.partyQuestCompareSession
	local receiver = a.pendingQuestCompareRequests[session.members[2].requestId].receiver
	a.partyQuestCompareWindow.close.scripts.OnClick()
	Equal(a.partyQuestCompareSession, nil)
	Equal(next(a.pendingQuestCompareRequests), nil)
	receiver.onEntry(Quest(2, "Late", true))
	receiver.onDone(true)
	Equal(next(session.members[2].entries), nil)
	assert(a:OpenPlayerQuestCompare("Nearby-Realm"))
	session = a.partyQuestCompareSession
	receiver = a.pendingQuestCompareRequests[session.members[2].requestId].receiver
	a.isEnabled = false
	a:ResetPartyQuestCompare()
	receiver.onEntry(Quest(3, "Disabled", true))
	receiver.onDone(true)
	a:Advance(181)
	Equal(a.partyQuestCompareSession, nil)
	Equal(next(session.members[2].entries), nil)
	Equal(next(a.pendingQuestCompareRequests), nil)
end)

QuestTogether:RegisterTest(
	"target compare validates ignored self empty inaccessible and restricted selections",
	function()
		local a = TargetFixture()
		a.ignored = "Ignored-Realm"
		local unreadable = {}
		local canAccessValue = a.CanAccessValue
		function a:CanAccessValue(value)
			return value ~= unreadable and canAccessValue(self, value)
		end
		for _, name in ipairs({ "", a.name, a.ignored, unreadable }) do
			Equal(a:OpenPlayerQuestCompare(name), false)
		end
		a.blocked = true
		Equal(a:OpenPlayerQuestCompare("Nearby-Realm"), false)
		a.blocked = false
		a.isEnabled = false
		Equal(a:OpenPlayerQuestCompare("Nearby-Realm"), false)
		Equal(#a.packets, 0)
		Equal(a.partyQuestCompareSession, false)
	end
)

QuestTogether:RegisterTest("target compare ignore cleanup cancels snapshots and stale sharing actions", function()
	local a = TargetFixture(nil, { Quest(1, "Local", true) })
	assert(a:OpenPlayerQuestCompare("Friend-Realm"))
	local session = a.partyQuestCompareSession
	local receiver = a.pendingQuestCompareRequests[session.members[2].requestId].receiver
	Reply(a, "Friend-Realm", { Quest(2, "Remote", true) }, true, true)
	a:RenderPartyQuestCompare()
	a.ignored = "Friend-Realm"
	Equal(a:SharePartyDiffQuest(1), false)
	Equal(a:RequestPartyQuestShare(2, "Friend-Realm"), false)
	a:CancelIgnoredPlayerQuestCompare()
	Equal(a.partyQuestCompareSession, nil)
	Equal(a.partyQuestCompareWindow:IsShown(), false)
	receiver.onEntry(Quest(3, "Ignored", true))
	Equal(session.members[2].entries[3], nil)
	Equal(a.pushes, 0)
	Equal(next(a.pendingQuestCompareRequests), nil)
end)

QuestTogether:RegisterTest("target compare unavailable transport and timeout never claim missing quests", function()
	for _, failure in ipairs({ "channel", "send", "timeout" }) do
		local a = TargetFixture(nil, { Quest(1, "Local", true) })
		a.channelUnavailable = failure == "channel"
		a.sendFails = failure == "send"
		assert(a:OpenPlayerQuestCompare("Nearby-Realm"))
		if failure == "timeout" then
			a:Advance(181)
		end
		Equal(a:BuildPartyQuestDiffRows()[1].cells[2], "Unknown")
		Equal(a:BuildPartyQuestDiffRows()[1].action, nil)
		Equal(next(a.pendingQuestCompareRequests), nil)
	end
end)

QuestTogether:RegisterTest(
	"target compare grouped requests preserve consent and keep other members out of the view",
	function()
		local a = TargetFixture("Me-Realm")
		local b = TargetFixture("Friend-Realm", { Quest(1, "Remote", true) })
		a:Roster(a.name, b.name, "Third-Realm")
		b:Roster(a.name, b.name, "Third-Realm")
		assert(a:OpenPlayerQuestCompare(b.name))
		DeliverTargetPacket(a, b, 1)
		b:Advance(0.2)
		for i = 1, #b.packets do
			DeliverTargetPacket(b, a, i)
		end
		Equal(#a.partyQuestCompareSession.members, 2)
		local row = a:BuildPartyQuestDiffRows()[1]
		Equal(row.owner, b.name)
		Equal(row.action, "request")
		assert(a:RequestPartyQuestShare(1, b.name))
		DeliverTargetPacket(a, b, #a.packets)
		Equal(b.pushes, 0)
		DeliverTargetPacket(b, a, #b.packets)
		Equal(a:GetPartyQuestShareStatus(1), "Awaiting confirmation")
		assert(b:ConfirmPartyQuestShare(b:GetNextPartyQuestShareRequest(), false))
		DeliverTargetPacket(b, a, #b.packets)
		Equal(a:GetPartyQuestShareStatus(1), "Share attempted")
		Equal(b.pushes, 1)
		for _, packet in ipairs(a.packets) do
			Equal(packet.distribution, "PARTY")
		end
		for _, packet in ipairs(b.packets) do
			Equal(packet.distribution, "PARTY")
		end
		-- A share result from the previous recipient is not feedback for a newly selected player.
		assert(a:OpenPlayerQuestCompare("Third-Realm"))
		Equal(a:GetPartyQuestShareStatus(1), nil)
	end
)

QuestTogether:RegisterTest(
	"target compare exposes another player's pending share and restores actions after completion or expiry",
	function()
		for _, acknowledged in ipairs({ false, true }) do
			for _, outcome in ipairs({ "declined", "expired" }) do
				local a = TargetFixture("Me-Realm")
				local b = TargetFixture("Friend-Realm", { Quest(1, "Same quest", true) })
				local c = TargetFixture("Third-Realm", { Quest(1, "Same quest", true) })
				for _, addon in ipairs({ a, b, c }) do
					addon:Roster(a.name, b.name, c.name)
				end
				local function Compare(peer)
					assert(a:OpenPlayerQuestCompare(peer.name))
					DeliverTargetPacket(a, peer, #a.packets)
					peer:Advance(0.2)
					for i = 1, #peer.packets do
						DeliverTargetPacket(peer, a, i)
					end
					a:RenderPartyQuestCompare()
					return a.partyQuestCompareWindow.rows[1]
				end
				local row = Compare(b)
				assert(row.action.shown and row.action.enabled)
				row.action.scripts.OnClick()
				DeliverTargetPacket(a, b, #a.packets)
				if acknowledged then
					DeliverTargetPacket(b, a, #b.packets)
				end
				Equal(a:GetPartyQuestShareStatus(1), acknowledged and "Awaiting confirmation" or "Request sent")
				row = Compare(c)
				local status, waiting = a:GetPartyQuestShareStatus(1)
				Equal(status, "Waiting for " .. b.name)
				Equal(waiting, true)
				Equal(row.action.shown, false)
				assert(row.hint.shown)
				Equal(row.hint.text, status)
				local sent, renders = #a.packets, a.renders
				-- Invoke the actual callback as if its previous enabled state was
				-- clicked before the pending-state render reached the window.
				row.action.scripts.OnClick()
				Equal(#a.packets, sent)
				assert(a.renders > renders, "a stale click must refresh the pending explanation")
				Equal(a.pushes + b.pushes + c.pushes, 0)
				if outcome == "expired" then
					a:Advance(61)
					b:Advance(61)
				else
					assert(b:FinishPartyQuestShare(b:GetNextPartyQuestShareRequest(), outcome))
					DeliverTargetPacket(b, a, #b.packets)
				end
				assert(
					a:GetPartyQuestShareStatus(1) == nil,
					"the previous player's terminal status is not the new player's result"
				)
				a:RenderPartyQuestCompare()
				assert(row.action.shown and row.action.enabled)
				Equal(row.action.text, "Request Share")
				Equal(row.hint.shown, false)
				assert(#a.packets == sent, "completion and expiry must not send another request")
				Equal(a.pushes + b.pushes + c.pushes, 0)
				row.action.scripts.OnClick()
				Equal(#a.packets, sent + 1)
				DeliverTargetPacket(a, c, #a.packets)
				DeliverTargetPacket(c, a, #c.packets)
				Equal(a:GetPartyQuestShareStatus(1), "Awaiting confirmation")
				Equal(c.pushes, 0)
				assert(c:ConfirmPartyQuestShare(c:GetNextPartyQuestShareRequest(), false))
				DeliverTargetPacket(c, a, #c.packets)
				Equal(a:GetPartyQuestShareStatus(1), "Share attempted")
				assert(c.pushes == 1, "only the newly requested player's explicit confirmation shares")
			end
		end
	end
)

QuestTogether:RegisterTest(
	"target compare defers restricted local snapshots and resumes the selected session",
	function()
		for _, restriction in ipairs({ "map", "combat" }) do
			local a = TargetFixture(nil, { Quest(1, "Local", true) })
			a.QueuePartyQuestCompareRender = QuestTogether.QueuePartyQuestCompareRender
			a.mapVisible = restriction == "map"
			assert(a:OpenPlayerQuestCompare("Nearby-Realm"))
			if restriction == "combat" then
				a.blocked = true
				a:OnPartyQuestRosterChanged()
			end
			local session = a.partyQuestCompareSession
			local reads = a.snapshotReads or 0
			a:Advance(1)
			Equal(a.snapshotReads or 0, reads)
			Equal(session.byName[a.name].state, "loading")
			if restriction == "map" then
				a:RenderPartyQuestCompare()
				Equal(a.partyQuestCompareWindow.summary.text, "Close the world map to finish loading quests.")
				session.message = "Existing feedback"
				a:RenderPartyQuestCompare()
				Equal(a.partyQuestCompareWindow.summary.text, "Existing feedback")
				session.message = nil
			end
			a.blocked, a.mapVisible = false, false
			a:FlushDeferredWork("restriction ended")
			a:Advance(0.1)
			Equal(a.snapshotReads, reads + 1)
			Equal(session.byName[a.name].state, "ready")
			Equal(session.targetName, "Nearby-Realm")
			Equal(#session.members, 2)
			Equal(a.partyQuestCompareWindow.title.text, "Compare Quests")
			assert(a.partyQuestCompareWindow.summary.text ~= "Close the world map to finish loading quests.")
			Equal(a.pushes, 0)
		end
	end
)

QuestTogether:RegisterTest("target compare response queue stops when requester becomes ignored", function()
	for _, unreadable in ipairs({ false, true }) do
		local a = TargetFixture("Me-Realm")
		local b = TargetFixture("Nearby-Realm", { Quest(1), Quest(2), Quest(3) })
		b:Roster(b.name)
		b.grouped, b.unreadable = false, unreadable
		assert(a:OpenPlayerQuestCompare(b.name))
		DeliverTargetPacket(a, b, 1)
		Equal(#b.questCompareResponseQueue.jobs, 1)
		Equal(#b.packets, unreadable and 0 or 1)
		local sent, reads = #b.packets, b.snapshotReads
		b.ignored = a.name
		b:Advance(2)
		Equal(#b.packets, sent)
		Equal(b.snapshotReads, reads)
		Equal(#b.questCompareResponseQueue.jobs, 0)
		Equal(b.questCompareResponseQueue.packets, 0)
		-- A direct handler call must apply the same ignore boundary as transport receipt.
		Equal(
			b:HandleQuestCompareRequest({
				requesterName = a.name,
				targetName = b.name,
				requestId = "ignored-request",
				replyDistribution = "CHANNEL",
			}),
			false
		)
		Equal(#b.packets, sent)
	end
end)

QuestTogether:RegisterTest(
	"party compare ignore cleanup clears cached ignored snapshots without closing the party view",
	function()
		local a = TargetFixture(nil, { Quest(1, "Local", true) })
		a:Roster(a.name, "Friend-Realm", "Third-Realm")
		assert(a:OpenPartyQuestCompare())
		Reply(a, "Friend-Realm", { Quest(2, "Ignored later", true) }, false, true)
		Reply(a, "Third-Realm", { Quest(3, "Visible", true) }, true, true)
		local session = a.partyQuestCompareSession
		local id = session.byName["Friend-Realm"].requestId
		local receiver = a.pendingQuestCompareRequests[id].receiver
		a.ignored = "Friend-Realm"
		a:CancelIgnoredPlayerQuestCompare()
		Equal(a.partyQuestCompareSession, session)
		Equal(a.partyQuestCompareWindow:IsShown(), true)
		Equal(a.pendingQuestCompareRequests[id], nil)
		Equal(next(session.byName["Friend-Realm"].entries), nil)
		Equal(session.byName["Friend-Realm"].state, "unavailable")
		assert(session.byName["Third-Realm"].entries[3])
		receiver.onEntry(Quest(4, "Late ignored", true))
		receiver.onDone(true)
		Equal(next(session.byName["Friend-Realm"].entries), nil)
		a:RefreshPartyQuestCompare()
		Equal(a.partyQuestCompareSession.byName["Friend-Realm"].requestId, nil)
		Equal(a.partyQuestCompareSession.byName["Friend-Realm"].state, "unavailable")
	end
)

QuestTogether:RegisterTest(
	"ignored players lose incoming and outgoing sharing state even without an open comparison",
	function()
		local a = TargetFixture(nil, { Quest(1, "Local", true) })
		a:Roster(a.name, "Friend-Realm", "Third-Realm")
		function a:GetQuestTitle()
			return "Local"
		end
		assert(a:HandlePartyQuestShareMessage(SharePacket(a, "friend-request", 1, "request"), "Friend-Realm", "PARTY"))
		assert(a:HandlePartyQuestShareMessage(SharePacket(a, "third-request", 1, "request"), "Third-Realm", "PARTY"))
		local state = a.partyQuestShareState
		state.outgoing.friend = { target = "Friend-Realm", questId = 2, status = "pending", expires = a.now + 60 }
		state.outgoing.third = { target = "Third-Realm", questId = 3, status = "pending", expires = a.now + 60 }
		a:RenderPartyQuestSharePrompt()
		local prompt, oldRequest = a.partyQuestSharePrompt, a:GetNextPartyQuestShareRequest()
		Equal(oldRequest.sender, "Friend-Realm")
		Equal(prompt:IsShown(), true)
		a.ignored = "Friend-Realm"
		Equal(a:GetNextPartyQuestShareRequest().sender, "Third-Realm")
		a.blocked = true
		a:CancelIgnoredPlayerQuestCompare()
		Equal(a.partyQuestCompareSession, false)
		Equal(prompt:IsShown(), false)
		Equal(prompt.request, nil)
		Equal(state.incoming[oldRequest.key], nil)
		Equal(state.outgoing.friend, nil)
		assert(state.outgoing.third)
		local sent = #a.packets
		Equal(a:ConfirmPartyQuestShare(oldRequest, true), false)
		Equal(a:FinishPartyQuestShare(oldRequest, "expired"), false)
		Equal(a:SendPartyQuestShareMessage("Friend-Realm", 1, "late", "expired"), false)
		Equal(#a.packets, sent)
		Equal(a.pushes, 0)
		a.blocked = false
		a:RenderPartyQuestSharePrompt()
		Equal(prompt:IsShown(), true)
		Equal(prompt.request.sender, "Third-Realm")
	end
)

QuestTogether:RegisterTest("party compare renders every locale while canonical actions still share", function()
	local previous = QuestTogether.localizationTestLocale
	for _, locale in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "itIT", "koKR", "zhCN", "zhTW" }) do
		QuestTogether.localizationTestLocale = locale
		local a = Fixture(nil, { Quest(1, "Untranslated quest title", true) })
		function a:GetPartyQuestUIParent()
			return Frame()
		end
		function a:CanAccessForeignFrame()
			return true
		end
		function a:CreatePartyQuestUIFrame()
			return Frame()
		end
		a:OpenPartyQuestCompare()
		Reply(a, "Friend-Realm", {}, true, true)
		a:RenderPartyQuestCompare()
		local frame = a.partyQuestCompareWindow
		Equal(frame.title.text, QuestTogether.TranslateForLocale("Party Quest Log", locale))
		Equal(frame.filter.text, QuestTogether.TranslateForLocale("Filters", locale))
		Equal(frame.rows[1].title.text, "Untranslated quest title")
		Equal(frame.rows[1].action.text, QuestTogether.TranslateForLocale("Share", locale))
		frame.rows[1].action.scripts.OnClick(frame.rows[1].action)
		Equal(a.pushes, 1)
	end
	QuestTogether.localizationTestLocale = previous
end)

QuestTogether:RegisterTest("client locale renders comparison and sharing consent controls", function()
	assert(QuestTogether.localizationTestLocale == nil)
	local locale = QuestTogether:GetEventLocale()
	local function T(key)
		return QuestTogether.TranslateForLocale(key, locale)
	end
	local a = Fixture(nil, { Quest(1, "Local quest", true) })
	AttachUI(a)
	a:OpenPartyQuestCompare()
	Reply(a, "Friend-Realm", {}, true, true)
	a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	Equal(frame.title.text, T("Party Quest Log"))
	Equal(frame.filter.text, T("Filters"))
	Equal(frame.rows[1].action.text, T("Share"))
	function a:GetQuestTitle()
		return "Local quest"
	end
	assert(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY"))
	a:RenderPartyQuestSharePrompt()
	local prompt = a.partyQuestSharePrompt
	Equal(prompt.title.text, T("QuestTogether · Share request"))
	Equal(prompt.always.children[1].text, T("Always allow party share requests"))
	Equal(
		prompt.message.text,
		string.format(T("%s would like you to share\n[%s]\nwith the party."), "Friend-Realm", "Local quest")
	)
	Equal(a.pushes, 0)
end, { locale = "client" })

QuestTogether:RegisterTest("direct share controls retain group authorization and manual consent", function()
	local a = Fixture(nil, { Quest(1, nil, true) })
	function a:SendWireMessageToAnnouncementRoutes(wire, _, routes)
		self.wire[#self.wire + 1] = wire
		self.lastRoutes = routes
		return true
	end
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Stranger-Realm", "WHISPER"), false)
	Equal(a.pushes, 0)
	Equal(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "WHISPER"), true)
	Equal(a.pushes, 0)
	Equal(a.lastRoutes[1].distribution, "WHISPER")
	Equal(a.lastRoutes[1].target, "Friend-Realm")
	a.partyMembers = {}
	Equal(a:SendPartyQuestShareMessage("Friend-Realm", 1, "stale", "sent"), false)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest(
	"retired share and join prompts dismiss safely during restrictions without showing their successors",
	function()
		for _, kind in ipairs({ "share", "join" }) do
			local a = Fixture(nil, { Quest(1, "Share me", true) })
			AttachUI(a)
			a.QueuePartyQuestSharePrompt = QuestTogether.QueuePartyQuestSharePrompt
			function a:GetQuestTitle()
				return "Share me"
			end
			function a:SendPartyQuestShareMessage()
				return true
			end
			function a:SendPartyJoinMessage()
				return true
			end
			local first = {
				sender = kind == "share" and "Friend-Realm" or "Visitor-Realm",
				key = "first",
				questId = 1,
				requestId = "r1",
				id = "j1",
				order = 1,
				created = 100,
				expires = 160,
			}
			local second = {
				sender = kind == "share" and "Friend-Realm" or "Other-Realm",
				key = "second",
				questId = 1,
				requestId = "r2",
				id = "j2",
				order = 2,
				created = 101,
				expires = 170,
			}
			local render, finish, queue, state, frameKey
			if kind == "share" then
				a.partyQuestShareState = { incoming = { first = first, second = second } }
				state = a.partyQuestShareState
				render, finish, queue =
					a.RenderPartyQuestSharePrompt, a.FinishPartyQuestShare, a.QueuePartyQuestSharePrompt
				frameKey = "partyQuestSharePrompt"
			else
				a.partyJoinState = { incoming = { [first.sender] = first, [second.sender] = second } }
				state = a.partyJoinState
				render, finish, queue = a.RenderPartyJoinPrompt, a.FinishPartyJoin, a.QueuePartyJoinPrompt
				frameKey = "partyJoinPrompt"
			end
			render(a)
			local frame = a[frameKey]
			Equal(frame.request, first)
			Equal(frame.shown, true)
			a.blocked = true
			Equal(finish(a, first, "declined"), true)
			Equal(frame.shown, false)
			Equal(frame.request, nil)
			a:Advance(0.1)
			Equal(frame.shown, false)
			assert(next(state.incoming), "the next consent request must remain pending")
			Equal(a.pushes, 0)
			a.blocked = false
			a:FlushDeferredWork("test restrictions ended")
			Equal(frame.shown, true)
			Equal(frame.request, second)
			-- Expiry does not require a successful layout/render callback either.
			a.blocked = true
			a.now = 171
			queue(a)
			Equal(frame.shown, false)
			Equal(frame.request, nil)
		end
	end
)

QuestTogether:RegisterTest(
	"retired consent prompts quarantine protected and forbidden frames until safe teardown",
	function()
		for _, boundary in ipairs({ "protected", "forbidden" }) do
			local a = Fixture()
			AttachUI(a)
			local frame = Frame()
			frame.request, frame[boundary] = {}, true
			a.partyQuestSharePrompt = frame
			a.partyQuestShareState = { incoming = {} }
			a.blocked = true
			local hides = 0
			local hide = frame.Hide
			function frame:Hide()
				assert(not self.protected and not self.forbidden, "quarantined prompt must not mutate")
				hides = hides + 1
				hide(self)
			end
			a:RenderPartyQuestSharePrompt()
			Equal(hides, 0)
			Equal(frame.request, nil)
			frame[boundary] = false
			a:RenderPartyQuestSharePrompt()
			Equal(hides, 1)
			Equal(frame.shown, false)
		end
	end
)

local function ObjectiveFixture(name)
	local a = Fixture(name, { Quest(1, "A shared quest", true), Quest(2, "Another quest", false) })
	a.objectiveRows = {
		[1] = {
			{ text = "Bandanas collected: 3/8", kind = "item", current = 3, required = 8, finished = false },
			{ text = "Speak to the watch", kind = "event", finished = true },
		},
		[2] = { { text = "Inspect the cave", kind = "event", finished = false } },
	}
	a.API.GetQuestLogIndexForQuestID = function(id)
		for i, entry in ipairs(a.entries) do
			if entry.questId == id then
				return i
			end
		end
	end
	a.API.GetNumQuestLeaderBoards = function(index)
		local entry = a.entries[index]
		local rows = entry and a.objectiveRows[entry.questId]
		return rows and #rows or 0
	end
	a.API.GetQuestObjectiveInfo = function(id, index)
		local row = a.objectiveRows[id] and a.objectiveRows[id][index]
		if row then
			return row.text, row.kind, row.finished, row.current, row.required
		end
	end
	a.API.GetQuestProgressBarPercent = function()
		return a.percent
	end
	a.wireRoutes = {}
	function a:SendWireMessageToAnnouncementRoutes(wire, _, routes)
		Equal(#routes, 1)
		self.wire[#self.wire + 1], self.wireRoutes[#self.wireRoutes + 1] = wire, routes[1]
		return not self.sendFails
	end
	return a
end

local function BeginObjectiveExchange()
	local a, b = ObjectiveFixture("Barbara Myers"), ObjectiveFixture("Sam Othername")
	a:Roster(a.name, b.name)
	b:Roster(a.name, b.name)
	a:RefreshPartyQuestCompare()
	a:Advance(0)
	b:OnCommReceived(b.commPrefix, a.wire[1], "PARTY", a.name)
	for _ = 1, 4 do
		b:Advance(0.2)
	end
	for _, wire in ipairs(b.wire) do
		a:OnCommReceived(a.commPrefix, wire, "PARTY", b.name)
	end
	Equal(a.partyQuestCompareSession.byName[b.name].supportsObjectives, true)
	a:TogglePartyQuestObjectives(1)
	a:Advance(0)
	Equal(a.wireRoutes[#a.wireRoutes].distribution, "WHISPER")
	Equal(a.wireRoutes[#a.wireRoutes].target, b.name)
	Equal(a.wireRoutes[#a.wireRoutes].requiresGroup, true)
	-- Re-routing an already private request must retain its party-only scope.
	function a:SupportsDirectComms()
		return true
	end
	Equal(
		a:GetTargetedCommRoutes(b.name, { { distribution = "WHISPER", target = b.name, requiresGroup = true } })[1].requiresGroup,
		true
	)
	b.wire, b.wireRoutes = {}, {}
	b:OnCommReceived(b.commPrefix, a.wire[#a.wire], "WHISPER", a.name)
	for _ = 1, 6 do
		b:Advance(0.2)
	end
	Equal(#b.wire, 4) -- one quest, two objectives, one completion marker
	for _, route in ipairs(b.wireRoutes) do
		Equal(route.distribution, "WHISPER")
		Equal(route.target, a.name)
	end
	return a, b
end

QuestTogether:RegisterTest(
	"expanded comparison objectives use scoped whispers and assemble reordered complete snapshots",
	function()
		local a, b = BeginObjectiveExchange()
		local member = a.partyQuestCompareSession.byName[b.name]
		local pendingId = member.objectiveDetails[1].requestId
		-- Neither a forged sender nor a different quest can fill this request.
		local row = a:DecodeQuestCompareObjectivePayload(b.wire[2]:sub(6))
		Equal(a:HandleQuestCompareObjective(row, "Other Player"), false)
		row.questId = 2
		Equal(a:HandleQuestCompareObjective(row, b.name), false)
		row.questId, row.objectiveIndex = 1, 20
		a:HandleQuestCompareObjective(row, b.name)
		for i = #b.wire, 2, -1 do
			a:OnCommReceived(a.commPrefix, b.wire[i], "WHISPER", b.name)
		end
		Equal(member.objectiveDetails[1].state, "loading")
		assert(a.pendingQuestCompareRequests[pendingId])
		a:OnCommReceived(a.commPrefix, b.wire[1], "WHISPER", b.name)
		Equal(member.objectiveDetails[1].state, "ready")
		Equal(#member.objectiveDetails[1].objectives, 2)
		Equal(member.objectiveDetails[1].objectives[1].current, 3)
		Equal(member.objectiveDetails[1].objectives[1].required, 8)
		Equal(member.objectiveDetails[1].objectives[2].finished, true)
		Equal(a.pendingQuestCompareRequests[pendingId], nil)
		Equal(member.entries[2].questTitle, "Another quest") -- scoped absence is not a whole-log snapshot
		a:OnCommReceived(a.commPrefix, b.wire[2], "WHISPER", b.name)
		Equal(#member.objectiveDetails[1].objectives, 2)
	end
)

QuestTogether:RegisterTest("partial objective snapshots time out as unknown without losing quest ownership", function()
	local a, b = BeginObjectiveExchange()
	local member = a.partyQuestCompareSession.byName[b.name]
	for _, i in ipairs({ 1, 2, 4 }) do
		a:OnCommReceived(a.commPrefix, b.wire[i], "WHISPER", b.name)
	end
	Equal(member.objectiveDetails[1].state, "loading")
	a:Advance(181)
	Equal(member.objectiveDetails[1].state, "unknown")
	Equal(member.state, "ready")
	Equal(member.entries[1].isComplete, false)
	local display = a:BuildPartyQuestCompareDisplayRows(a:BuildPartyQuestDiffRows())
	local found = false
	for _, row in ipairs(display) do
		if row.kind == "member" and row.title == b.name then
			Equal(row.hint, "Unknown")
			found = true
		end
	end
	assert(found)
end)

QuestTogether:RegisterTest("collapsed closed and ignored comparisons reject late objective replies", function()
	for _, change in ipairs({ "collapse", "close", "refresh", "ignore", "depart", "disable", "filter" }) do
		local a, b = BeginObjectiveExchange()
		local session = a.partyQuestCompareSession
		local member = session.byName[b.name]
		local id = member.objectiveDetails[1].requestId
		if change == "collapse" then
			a:TogglePartyQuestObjectives(1)
		elseif change == "filter" then
			a:SetPartyQuestCompareFilter("search", "Other quest")
		elseif change == "close" then
			a:CancelPartyQuestCompare()
		elseif change == "refresh" then
			a:RefreshPartyQuestCompare()
		elseif change == "ignore" then
			a.ignored = b.name
			a:CancelIgnoredPlayerQuestCompare()
		elseif change == "depart" then
			a:Roster(a.name)
			a:OnPartyQuestRosterChanged()
		else
			a.isEnabled = false
			a:ResetPartyQuestCompare()
		end
		Equal(a.pendingQuestCompareRequests[id], nil)
		for _, wire in ipairs(b.wire) do
			a:OnCommReceived(a.commPrefix, wire, "WHISPER", b.name)
		end
		assert(not member.objectiveDetails or not member.objectiveDetails[1])
	end
end)

QuestTogether:RegisterTest(
	"objective reads preserve text and distinguish percentages binary objectives and unavailable data",
	function()
		local a = ObjectiveFixture()
		local rows = a:ReadQuestCompareObjectives(1)
		Equal(rows[1].text, "Bandanas collected: 3/8")
		Equal(rows[2].finished, true)
		a.objectiveRows[1][1] =
			{ text = "Clear the area (36%)", kind = "progressbar", current = 7, required = 9, finished = false }
		a.percent = 36
		rows = a:ReadQuestCompareObjectives(1)
		Equal(rows[1].current, 36)
		Equal(rows[1].required, 100)
		a.percent = nil
		Equal(a:ReadQuestCompareObjectives(1)[1].current, nil)
		a.blocked = true
		Equal(a:ReadQuestCompareObjectives(1), nil)
		a.blocked = false
		a.objectiveRows[1] = {}
		Equal(a:ReadQuestCompareObjectives(1), nil)
		a.objectiveRows[1] = { { text = "", kind = "item" } }
		Equal(a:ReadQuestCompareObjectives(1), nil)
		a.objectiveRows[1] = { { text = "Feinde besiegt: 4/8", kind = "monster", current = 4, required = 8 } }
		Equal(a:ReadQuestCompareObjectives(1)[1].text, "Feinde besiegt: 4/8")
		local count = 0
		a.API.GetQuestLogIndexForQuestID = function()
			count = count + 1
			return count == 1 and 1 or 2
		end
		Equal(a:ReadQuestCompareObjectives(1), nil)
	end
)

QuestTogether:RegisterTest(
	"objective detail codecs bound payloads sanitize markup and reject malformed counters",
	function()
		local a = ObjectiveFixture()
		Equal(a:SendQuestCompareEntry("request", nil), false)
		local row = {
			questId = 1,
			objectiveIndex = 1,
			kind = "item",
			text = string.rep("任務,|", 150),
			current = 3,
			required = 8,
			finished = false,
		}
		local encoded = a:EncodeQuestCompareObjectivePayload("request", row)
		assert(#encoded + 5 <= 255)
		local decoded = assert(a:DecodeQuestCompareObjectivePayload(encoded))
		assert(not decoded.text:find("|", 1, true))
		Equal(decoded.current, 3)
		Equal(a:CleanQuestCompareObjectiveText("|cffffffffText|r |Hquest:1|hQuest|h |Tfoo:12|t"), "Text Quest")
		for _, packet in ipairs({
			"1,r,1,0,Text,item,0,1,2",
			"1,r,1,21,Text,item,0,1,2",
			"1,r,1.5,1,Text,item,0,1,2",
			"1,r,1,1,Text,item,0,-1,2",
			"1,r,1,1,Text,item,0,nan,2",
			"1,r,1,1,Text,item,2,1,2",
			"1,r,1,1,Text,item,0,1.5,2",
			"1,r,1,1,,item,0,1,2",
			"1,r,1,1,Text,item,0,1,2,extra",
		}) do
			Equal(a:DecodeQuestCompareObjectivePayload(packet), nil)
		end
		Equal(a:DecodeQuestCompareRequestPayload("1,r,A,B,1.5"), nil)
		Equal(a:DecodeQuestCompareRequestPayload("1,r,A,B").objectiveQuestId, nil)
		Equal(a:DecodeQuestCompareDonePayload("1,r,B,MAGE,1,share1").supportsObjectives, false)
	end
)

QuestTogether:RegisterTest(
	"older peers and unanswered members remain explicit in expanded comparisons without extra requests",
	function()
		local a = ObjectiveFixture()
		a:Roster(a.name, "Old Peer", "Quiet Peer")
		a:RefreshPartyQuestCompare()
		a:Advance(0)
		Reply(a, "Old Peer", { Quest(1, "Quest", true) }, true, true)
		local count = #a.wire
		a:TogglePartyQuestObjectives(1)
		a:Advance(0)
		Equal(#a.wire, count)
		local rows = a:BuildPartyQuestCompareDisplayRows(a:BuildPartyQuestDiffRows())
		for _, row in ipairs(rows) do
			if row.title == "Old Peer" then
				Equal(row.hint, "Update QuestTogether for objective details.")
			end
			if row.title == "Quiet Peer" then
				Equal(row.hint, "Loading")
			end
		end
		a:Advance(181)
		rows = a:BuildPartyQuestCompareDisplayRows(a:BuildPartyQuestDiffRows())
		for _, row in ipairs(rows) do
			if row.title == "Quiet Peer" then
				Equal(row.hint, "Unknown")
			end
		end
	end
)

QuestTogether:RegisterTest(
	"objective preview expands in the reused row pool without changing quest totals or sending messages",
	function()
		local a = ObjectiveFixture()
		AttachUI(a)
		a:OpenPartyQuestComparePreview()
		local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
		local count = #p:BuildPartyQuestDiffRows()
		local row = frame.rows[1]
		local id = row.data.questId
		row.scripts.OnMouseUp(row, "LeftButton")
		FinishExpansion(frame)
		Equal(p.partyQuestCompareSession.expandedQuestIds[id], true)
		Equal(#p:BuildPartyQuestDiffRows(), count)
		assert(#p:BuildPartyQuestCompareDisplayRows(p:BuildPartyQuestDiffRows()) > count)
		Equal(#frame.rows, 26)
		Equal(frame.rows[2].data.kind, "member")
		Equal(frame.rows[3].data.kind, "objective")
		Equal(frame.rows[3].action:IsShown(), false)
		Equal(frame.rows[3].hint.text, "2/8")
		frame.vertical:SetValue(5 * 42)
		Equal(#frame.rows, 26)
		Equal(#a.wire, 0)
		frame.vertical:SetValue(0)
		frame.rows[1].scripts.OnMouseUp(frame.rows[1], "LeftButton")
		FinishExpansion(frame)
		Equal(p.partyQuestCompareSession.expandedQuestIds[id], nil)
		Equal(frame.rows[2].data.kind, nil)
		Equal(frame.rows[2].title.width, 284) -- Owned quests reserve space for the quest-log button.
	end
)

QuestTogether:RegisterTest(
	"local expanded progress refreshes without polling remote players and Refresh replaces detail requests",
	function()
		local a, b = BeginObjectiveExchange()
		for _, wire in ipairs(b.wire) do
			a:OnCommReceived(a.commPrefix, wire, "WHISPER", b.name)
		end
		local session = a.partyQuestCompareSession
		local count = #a.wire
		a.objectiveRows[1][1].current = 7
		a:OnPartyQuestLogChanged()
		a:Advance(1)
		Equal(session.byName[a.name].objectiveDetails[1].objectives[1].current, 7)
		Equal(session.byName[b.name].objectiveDetails[1].objectives[1].current, 3)
		Equal(#a.wire, count)
		a:RefreshPartyQuestCompare()
		a:Advance(0)
		assert(a.partyQuestCompareSession ~= session)
		Equal(a.partyQuestCompareSession.expandedQuestIds[1], true)
		local member = a.partyQuestCompareSession.byName[b.name]
		assert(not member.objectiveDetails or not member.objectiveDetails[1])
		Reply(a, b.name, { Quest(1, "Updated title", true) }, true, true)
		-- An old peer's refresh has no obj1 capability; it never receives details requests.
		assert(not member.objectiveDetails or not member.objectiveDetails[1])
	end
)

QuestTogether:RegisterTest(
	"objective reply retries defer restricted reads and never fabricate zero objectives",
	function()
		local a, b = BeginObjectiveExchange()
		local request = a.wire[#a.wire]
		b.wire, b.wireRoutes = {}, {}
		b.blocked = true
		-- A different id supersedes the earlier request; dispatch through real codecs.
		local data = b:DecodeQuestCompareRequestPayload(request:sub(6))
		data.requestId = "restricted-objectives"
		b:OnCommReceived(b.commPrefix, "QCMP|" .. b:EncodeQuestCompareRequestPayload(data), "WHISPER", a.name)
		for _ = 1, 8 do
			b:Advance(1)
		end
		Equal(#b.wire, 0)
		b.blocked = false
		for _ = 1, 6 do
			b:Advance(1)
		end
		Equal(#b.wire, 4)
		local entry = b:DecodeQuestCompareEntryPayload(b.wire[1]:sub(6))
		Equal(entry.objectiveCount, 2)
		b.objectiveRows[1] = {}
		local entries = b:BuildQuestCompareResponseEntries(1)
		Equal(#entries, 1)
		Equal(entries[1].objectiveCount, nil)
		local all = b:BuildQuestCompareResponseEntries()
		Equal(#all, 2)
		Equal(all[1].objectiveCount, nil)
	end
)

QuestTogether:RegisterTest("compact objectives fit all five members with two objectives inside the default viewport", function()
	for _, lightMode in ipairs({ false, true }) do
		local a = PreviewFixture()
		a.options.lightMode = lightMode
		a:OpenPartyQuestComparePreview()
		local p = a.partyQuestComparePreview
		local frame = p.partyQuestCompareWindow
		p:SetPartyQuestCompareFilter("search", "Supplies for the Watch")
		p:TogglePartyQuestObjectives(3)
		local members, objectives, height = 0, 0, 0
		for _, row in ipairs(frame.rows) do
			if row.data then
				height = height + row:GetHeight()
				if row.data.kind == "member" then members = members + 1 end
				if row.data.kind == "objective" then
					objectives = objectives + 1
					if row.progressTrack:IsShown() then
						local barBottom = -row.progressTrack.points[1][3] + row.progressTrack:GetHeight()
						assert(barBottom < row:GetHeight(), "progress bars retain bottom padding")
					end
				end
			end
		end
		Equal(members, 5)
		Equal(objectives, 10)
		assert(height <= frame.rowsViewport:GetHeight(), "the complete five-player section fits without scrolling")
		assert(not frame.vertical:IsShown())
		Equal(#a.wire, 0)
	end
end)

QuestTogether:RegisterTest("party readiness counts missing and unknown members without inferring completion", function()
	local a = ObjectiveFixture()
	a.partyQuestCompareSession = { members = { { state = "ready" }, { state = "ready" }, { state = "ready" } } }
	local row = { cells = { "Ready", "Ready", "Ready" } }
	local text, state = a:GetPartyQuestReadiness(row)
	Equal(text, "Everyone ready")
	Equal(state, "Ready")
	row.cells[2], row.cells[3] = "Have", "Missing"
	text, state = a:GetPartyQuestReadiness(row)
	Equal(text, "1/3 ready · 1 missing")
	Equal(state, "Missing")
	-- Even a received ready entry cannot certify an incomplete snapshot.
	a.partyQuestCompareSession.members[1].state = "loading"
	text, state = a:GetPartyQuestReadiness(row)
	Equal(text, "0/3 ready · 1 missing · 1 unknown")
	Equal(state, "Unknown")
	a.partyQuestCompareSession.members[1].state = "timeout"
	Equal(a:GetPartyQuestReadiness(row), text)
end)

QuestTogether:RegisterTest(
	"compare preview class accents and objective progress clear when pooled rows are reused",
	function()
		local a = ObjectiveFixture()
		a.options.lightMode = true
		AttachUI(a)
		function a:GetClassColorCode(classFile)
			return ({ PALADIN = "|cfff58cba", MAGE = "|cff3fc7eb", WARRIOR = "|cffc79c6e" })[classFile] or "|cffffffff"
		end
		a:OpenPartyQuestComparePreview()
		local preview, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
		Equal(frame.headers[1].textColor[1], 245 / 255 * 0.48)
		Equal(frame.headers[2].textColor[1], 63 / 255 * 0.48)
		Equal(frame.headers[3].textColor[1], 199 / 255 * 0.48)
		for i = 1, 3 do
			local shade = frame.rows[1].cellShades[i]
			Equal(frame.focusButtons[i].points[1][2], shade.points[1][2])
			Equal(frame.focusButtons[i].width, shade.width)
			Equal(frame.headerAccents[i].points[1][2], shade.points[1][2])
			Equal(frame.headerAccents[i].width, shade.width)
		end
		assert(frame.rows[1].partySummary.text:find("missing", 1, true))
		frame.rows[1].scripts.OnMouseUp(frame.rows[1], "LeftButton")
		FinishExpansion(frame)
		local objective = frame.rows[3]
		assert(objective.progressTrack:IsShown() and objective.progressFill:IsShown())
		Equal(objective.progressFill.width / objective.progressTrack.width, 0.25)
		assert(not objective.cellShades[1]:IsShown())
		assert(not objective.accent:IsShown() and not frame.rows[2].accent:IsShown())
		Equal(frame.rows[2].title.textColor[1], 245 / 255 * 0.32)
		assert(frame.rows[1].accent:IsShown()) -- Selected parent remains identifiable.
		assert(frame.rows[2].panelEdges[3]:IsShown()) -- Inset begins below the parent.
		assert(frame.rows[2].panelCorners[1]:IsShown() and frame.rows[2].panelCorners[2]:IsShown())
		assert(not frame.rows[2].panelCorners[3]:IsShown())
		assert(frame.rows[2].background.panelParts[3]:IsShown())
		assert(not frame.rows[2].hover.panelParts[3]:IsShown())
		assert(objective.paper:IsShown() and objective.panelEdges[1]:IsShown() and objective.panelEdges[2]:IsShown())
		assert(not objective.panelEdges[3]:IsShown() and not objective.panelEdges[4]:IsShown())
		-- Scrolling into a section must clip its continuing panel, then clear all
		-- decoration when these same row frames become ordinary quests again.
		frame.vertical:SetValue(2 * 42)
		assert(frame.rows[1].data.kind == "objective" and not frame.rows[1].panelEdges[3]:IsShown())
		frame.vertical:SetValue(0)
		frame.rows[1].scripts.OnMouseUp(frame.rows[1], "LeftButton")
		FinishExpansion(frame)
		assert(not objective.progressTrack:IsShown() and not objective.progressFill:IsShown())
		assert(objective.cellShades[1]:IsShown())
		assert(not objective.accent:IsShown())
		assert(not objective.paper:IsShown())
		for _, edge in ipairs(objective.panelEdges) do
			assert(not edge:IsShown())
		end
		for _, corner in ipairs(frame.rows[2].panelCorners or {}) do assert(not corner:IsShown()) end
		for _, part in ipairs(frame.rows[2].background.panelParts or {}) do assert(not part:IsShown()) end
		Equal(objective.title.textColor[1], 0.18)
		Equal(#a.wire, 0)
	end
)

QuestTogether:RegisterTest(
	"quest log pixel scrolling animates without rebuilding snapshots and cancels on lifecycle changes",
	function()
		local a = ObjectiveFixture()
		AttachUI(a)
		a:OpenPartyQuestComparePreview()
		local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
		local build = p.BuildPartyQuestDiffRows
		function p:BuildPartyQuestDiffRows()
			error("scrolling must not rebuild the quest model")
		end
		local header = frame.headers[1].text
		frame.vertical:SetValue(10)
		Equal(p.partyQuestCompareSession.scrollPixels, 10)
		Equal(p.partyQuestCompareSession.offset, 0)
		Equal(frame.rowsViewport.verticalScroll, 10)
		frame.vertical:SetValue(49)
		Equal(p.partyQuestCompareSession.offset, 1)
		Equal(frame.rowsViewport.verticalScroll, 7)
		Equal(frame.rows[1].data.questId, frame.displayRows[2].questId)
		frame.rowsViewport.scripts.OnMouseWheel(frame.rowsViewport, -1)
		local target = frame.wheelTarget
		frame.scripts.OnUpdate(frame, 1 / 60)
		local moved = p.partyQuestCompareSession.scrollPixels
		assert(moved > 49 and moved < target)
		a.blocked = true
		frame.scripts.OnUpdate(frame, 1 / 60)
		Equal(p.partyQuestCompareSession.scrollPixels, moved)
		a.blocked = false
		for _ = 1, 90 do
			if frame.scripts.OnUpdate then
				frame.scripts.OnUpdate(frame, 1 / 60)
			end
		end
		Equal(p.partyQuestCompareSession.scrollPixels, target)
		Equal(frame.scripts.OnUpdate, nil)
		Equal(frame.headers[1].text, header)
		Equal(#frame.rows, 26)
		p.BuildPartyQuestDiffRows = build
		frame.viewport.scripts.OnMouseWheel(frame.viewport, -1)
		p:SetPartyQuestCompareFilter("search", "Herbalist")
		Equal(frame.scripts.OnUpdate, nil)
		Equal(frame.rowsViewport.verticalScroll, 0)
		Equal(frame.vertical:GetValue(), 0)
		p:ResetPartyQuestCompareFilters()
		frame.viewport.scripts.OnMouseWheel(frame.viewport, -1)
		frame.refresh.scripts.OnClick()
		Equal(frame.scripts.OnUpdate, nil)
		Equal(frame.rowsViewport.verticalScroll, 0)
		frame.viewport.scripts.OnMouseWheel(frame.viewport, -1)
		frame.close.scripts.OnClick()
		Equal(frame.scripts.OnUpdate, nil)
		Equal(#a.wire, 0)
	end
)

QuestTogether:RegisterTest(
	"objective expansion reveals clipped rows reverses smoothly and retires stale animation callbacks",
	function()
		local a = ObjectiveFixture()
		AttachUI(a)
		a:OpenPartyQuestComparePreview()
		local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
		local id = frame.rows[1].data.questId
		local function Click()
			frame.rows[1].scripts.OnMouseUp(frame.rows[1], "LeftButton")
		end
		local function Tick(elapsed)
			frame.expansionAnimator.scripts.OnUpdate(frame.expansionAnimator, elapsed)
		end
		Click()
		assert(frame.expansions and frame.expansions[id].target > 0)
		Equal(frame.expansions[id].reveal, 0)
		local build = p.BuildPartyQuestDiffRows
		function p:BuildPartyQuestDiffRows()
			error("animation must not rebuild quest snapshots")
		end
		Tick(0.05)
		assert(frame.expansions[id].reveal > 0 and frame.expansions[id].reveal < frame.expansions[id].target)
		local clipped = false
		for _, row in ipairs(frame.rows) do
			if row.data and row.data.kind and row.clip.height < 42 then
				clipped = true
			end
		end
		assert(clipped, "the revealed last row must be clipped instead of scaling its text")
		a.blocked = true
		local paused = frame.expansions[id].reveal
		Tick(0.05)
		Equal(frame.expansions[id].reveal, paused)
		a.blocked = false
		FinishExpansion(frame)
		p.BuildPartyQuestDiffRows = build
		Equal(frame.expansions, nil)
		Click()
		Equal(frame.expansions[id].target, 0)
		Tick(0.05)
		local reversingFrom = frame.expansions[id].reveal
		local retired = frame.expansionAnimator.scripts.OnUpdate
		Click()
		Equal(frame.expansions[id].from, reversingFrom)
		local current = frame.expansions[id]
		retired(frame.expansionAnimator, 0.1)
		Equal(frame.expansions[id], current)
		Equal(current.reveal, reversingFrom)
		FinishExpansion(frame)
		Click()
		frame.viewport.scripts.OnMouseWheel(frame.viewport, -1)
		for _ = 1, 60 do
			if frame.expansionAnimator.scripts.OnUpdate then
				Tick(1 / 60)
			end
			if frame.scripts.OnUpdate then
				frame.scripts.OnUpdate(frame, 1 / 60)
			end
		end
		Equal(frame.expansions, nil)
		Equal(frame.scripts.OnUpdate, nil)
		frame.vertical:SetValue(0)
		Click()
		retired = frame.expansionAnimator.scripts.OnUpdate
		p:SetPartyQuestCompareFilter("search", "Herbalist")
		Equal(frame.expansions, nil)
		retired(frame.expansionAnimator, 0.1)
		Equal(frame.expansions, nil)
		p:ResetPartyQuestCompareFilters()
		Click()
		frame.close.scripts.OnClick()
		Equal(frame.expansionAnimator.scripts.OnUpdate, nil)
		Equal(#a.wire, 0)
	end
)

QuestTogether:RegisterTest(
	"quest log filters combine ownership progress action and literal localized search",
	function()
		local a = Fixture(nil, { Quest(1, "ÄPFEL [1]", true, true), Quest(2, "Local supplies", true) })
		a:RefreshPartyQuestCompare()
		a:Advance(0)
		Reply(
			a,
			"Friend-Realm",
			{ Quest(1, "Apples", true, true), Quest(3, "Remote supplies", true), Quest(4, "Letters", true, true) },
			true,
			true
		)
		local sent = #a.wire
		local function Count(key, value, expected)
			a:SetPartyQuestCompareFilter(key, value)
			Equal(#a:BuildPartyQuestDiffRows(), expected)
		end
		Count("ownership", "mine", 2)
		Count("progress", "active", 1)
		Count("action", "share", 1)
		Count("search", "Local", 1)
		Count("search", "Remote", 0)
		a:ResetPartyQuestCompareFilters()
		Count("ownership", "missing", 2)
		Count("action", "request", 2)
		a:ResetPartyQuestCompareFilters()
		Count("ownership", "shared", 1)
		Count("progress", "ready", 1)
		Count("search", "äpfel [1]", 1)
		Count("search", "APPLES", 1) -- The peer's wording is searchable too.
		Count("search", "[", 1) -- No Lua pattern interpretation.
		Count("search", "1", 1)
		a:ResetPartyQuestCompareFilters()
		Count("progress", "someReady", 2)
		a:ResetPartyQuestCompareFilters()
		Count("ownership", "someoneMissing", 3)
		a:ResetPartyQuestCompareFilters()
		a.partyQuestCompareSession.byName["Friend-Realm"].state = "timeout"
		Count("progress", "ready", 0)
		Count("progress", "unknown", 4)
		Count("ownership", "shared", 0)
		a:ResetPartyQuestCompareFilters()
		Equal(#a:BuildPartyQuestDiffRows(), 4)
		Equal(#a.wire, sent)
	end
)

QuestTogether:RegisterTest("quest log filter menu search reset and preview incomplete data stay isolated", function()
	local a = ObjectiveFixture()
	AttachUI(a)
	local function Menu()
		local node = { items = {} }
		function node:CreateButton(label, click)
			local child = Menu()
			child.label, child.click = label, click
			self.items[#self.items + 1] = child
			return child
		end
		function node:CreateCheckbox(label, checked, click)
			local child = self:CreateButton(label, click)
			child.checked = checked
			return child
		end
		function node:CreateDivider() end
		return node
	end
	local menu
	function a:CreatePartyQuestFilterMenu(owner, generator)
		menu = Menu()
		generator(owner, menu)
		return true
	end
	a:OpenPartyQuestComparePreview()
	local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
	frame.filter.scripts.OnClick(frame.filter)
	menu.items[1].items[2].click()
	assert(menu.items[1].items[2].checked())
	Equal(frame.filter.text, "Filters (1)")
	p.partyQuestCompareSession.restoreAnchor = { questId = 1, offset = 30 }
	frame.search:SetText("  HERBALIST  ")
	Equal(p.partyQuestCompareSession.restoreAnchor, nil)
	Equal(#p:BuildPartyQuestDiffRows(), 1)
	Equal(frame.reset.enabled, true)
	frame.reset.scripts.OnClick()
	Equal(frame.search:GetText(), "")
	Equal(#p:BuildPartyQuestDiffRows(), 16)
	Equal(frame.reset.enabled, false)
	menu.items[6].click() -- Preview-only missing snapshot toggle.
	menu.items[2].items[5].click()
	Equal(#p:BuildPartyQuestDiffRows(), 16)
	Equal(p:GetPartyQuestCompareFilters().progress, "unknown")
	local oldClick = menu.items[1].items[2].click
	frame.refresh.scripts.OnClick()
	oldClick()
	Equal(p:GetPartyQuestCompareFilters().ownership, "all")
	Equal(p.incompleteData, false)
	Equal(a.options.compareQuestOwnership, nil)
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest(
	"multiple expanded quests retain separate snapshots and serialize requests to each peer",
	function()
		local a, b = BeginObjectiveExchange()
		local session, sent = a.partyQuestCompareSession, #a.wire
		local member = session.byName[b.name]
		a:TogglePartyQuestObjectives(2)
		a:Advance(0)
		Equal(#a.wire, sent)
		assert(session.expandedQuestIds[1] and session.expandedQuestIds[2])
		Equal(member.objectiveRequestQuestId, 1)
		for _, wire in ipairs(b.wire) do
			a:OnCommReceived(a.commPrefix, wire, "WHISPER", b.name)
		end
		Equal(member.objectiveDetails[1].state, "ready")
		Equal(member.objectiveRequestQuestId, 2)
		Equal(#a.wire, sent + 1)
		Equal(a:DecodeQuestCompareRequestPayload(a.wire[#a.wire]:sub(6)).objectiveQuestId, 2)
		-- Closing a completed section must not cancel another quest's active request.
		local secondRequest = member.objectiveDetails[2].requestId
		a:TogglePartyQuestObjectives(1)
		assert(a.pendingQuestCompareRequests[secondRequest])
		b.wire = {}
		b:OnCommReceived(b.commPrefix, a.wire[#a.wire], "WHISPER", a.name)
		for _ = 1, 6 do
			b:Advance(0.2)
		end
		for _, wire in ipairs(b.wire) do
			a:OnCommReceived(a.commPrefix, wire, "WHISPER", b.name)
		end
		Equal(member.objectiveDetails[2].state, "ready")
		Equal(member.objectiveDetails[2].objectives[1].text, "Inspect the cave")
		Equal(member.objectiveRequestQuestId, nil)
		Equal(member.objectiveDetails[1], nil)
		Equal(session.expandedQuestIds[2], true)
	end
)

QuestTogether:RegisterTest(
	"objective request pipeline advances on timeout or collapse without accepting cancelled replies",
	function()
		for _, action in ipairs({ "timeout", "collapse" }) do
			local a, b = BeginObjectiveExchange()
			local session = a.partyQuestCompareSession
			local member = session.byName[b.name]
			a:TogglePartyQuestObjectives(2)
			local first = member.objectiveDetails[1].requestId
			if action == "timeout" then
				a:Advance(181)
			else
				a:TogglePartyQuestObjectives(1)
			end
			Equal(a.pendingQuestCompareRequests[first], nil)
			Equal(member.objectiveRequestQuestId, 2)
			for _, wire in ipairs(b.wire) do
				a:OnCommReceived(a.commPrefix, wire, "WHISPER", b.name)
			end
			Equal(member.objectiveDetails[2].state, "loading")
			if action == "timeout" then
				Equal(member.objectiveDetails[1].state, "unknown")
			else
				Equal(member.objectiveDetails[1], nil)
			end
			a:CancelPartyQuestCompare()
			Equal(member.objectiveRequestQuestId, nil)
			Equal(next(member.objectiveDetails), nil)
		end
	end
)

QuestTogether:RegisterTest("quest log preview independently animates multiple open sections", function()
	local a = ObjectiveFixture()
	AttachUI(a)
	a:OpenPartyQuestComparePreview()
	local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
	local quests = p:BuildPartyQuestDiffRows()
	local first, second = quests[1].questId, quests[2].questId
	local function Toggle(id)
		frame.animateExpansion = { session = p.partyQuestCompareSession, questId = id }
		p:TogglePartyQuestObjectives(id)
	end
	Toggle(first)
	frame.expansionAnimator.scripts.OnUpdate(frame.expansionAnimator, 0.05)
	Toggle(second)
	assert(frame.expansions[first] and frame.expansions[second])
	FinishExpansion(frame)
	local function Details(id)
		local n = 0
		for _, row in ipairs(frame.displayRows) do
			if row.kind and row.questId == id then
				n = n + 1
			end
		end
		return n
	end
	assert(Details(first) > 0 and Details(second) > 0)
	Toggle(first)
	FinishExpansion(frame)
	Equal(Details(first), 0)
	assert(Details(second) > 0)
	Equal(p.partyQuestCompareSession.expandedQuestIds[second], true)
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest(
	"quest log resizing updates cached layout bounds and row capacity without traffic",
	function()
		local a = ObjectiveFixture()
		local parent = AttachUI(a)
		parent:SetSize(1920, 1200)
		a:OpenPartyQuestComparePreview()
		local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
		local session = p.partyQuestCompareSession
		frame.rows[1].scripts.OnMouseUp(frame.rows[1], "LeftButton")
		FinishExpansion(frame)
		local expanded = frame.rows[1].data.questId
		function p:BuildPartyQuestDiffRows()
			error("resizing must reuse the cached quest model")
		end
		frame.resizeGrip.scripts.OnMouseDown(nil, "RightButton")
		Equal(frame.sizing, nil)
		a.blocked = true
		frame.resizeGrip.scripts.OnMouseDown(nil, "LeftButton")
		Equal(frame.sizing, nil)
		a.blocked = false
		local originalWidth, originalHeight = frame:GetWidth(), frame:GetHeight()
		frame.resizeGrip.scripts.OnMouseDown(nil, "LeftButton")
		Equal(frame.sizing, "BOTTOMRIGHT")
		Equal(frame.sizingFromMouse, true)
		Equal(frame:GetWidth(), originalWidth)
		Equal(frame:GetHeight(), originalHeight)
		frame:SetSize(1600, 1100)
		Equal(frame.rowsViewport:GetHeight(), 866)
		Equal(frame.viewport:GetWidth(), 1538)
		Equal(#frame.rows, 44)
		Equal(frame.horizontal:IsShown(), false)
		assert(session.expandedQuestIds[expanded])
		frame.vertical:SetValue(99999)
		frame:SetSize(100, 100) -- Native resize bounds, modeled by the private fixture.
		Equal(frame:GetWidth(), 1222)
		Equal(frame:GetHeight(), 500)
		Equal(frame.rowsViewport:GetHeight(), 266)
		Equal(frame.footer, nil)
		Equal(frame.detail, nil)
		Equal(frame.horizontal:IsShown(), false)
		Equal(#frame.rows, 44) -- Existing rows are reused rather than destroyed/recreated.
		for i = #frame.visibleRows + 1, #frame.rows do
			assert(not frame.rows[i]:IsShown())
		end
		frame.resizeGrip.scripts.OnMouseUp()
		Equal(frame.sizing, nil)
		frame:SetSize(1600, 1100)
		assert(session.scrollPixels <= frame.vertical.maximum)
		frame.resizeGrip.scripts.OnMouseDown(nil, "LeftButton")
		frame.close.scripts.OnClick()
		Equal(frame.sizing, nil)
		Equal(#a.wire, 0)
	end
)

QuestTogether:RegisterTest(
	"quest log dark mode changes contrast preserves state and restores the light theme",
	function()
		local a = ObjectiveFixture()
		a.options.lightMode = true
		AttachUI(a)
		a:OpenPartyQuestComparePreview()
		local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
		Equal(QuestTogether.DEFAULTS.profile.lightMode, false)
		local id = frame.rows[1].data.questId
		frame.rows[1].scripts.OnMouseUp(frame.rows[1], "LeftButton")
		FinishExpansion(frame)
		local lightInk, lightHeader = frame.rows[1].title.textColor[1], frame.headers[1].textColor[1]
		a.options.lightMode = false
		a:RefreshWindowThemes()
		a:Advance(0)
		assert(frame.parchment.vertexColor[1] < 0.2)
		assert(frame.rows[1].title.textColor[1] > lightInk)
		assert(frame.headers[1].textColor[1] > lightHeader)
		Equal(frame.rows[2].background.textureColor[4], frame.rows[3].background.textureColor[4])
		assert(not frame.rows[2].accent:IsShown() and frame.rows[2].panelEdges[1]:IsShown())
		assert(p.partyQuestCompareSession.expandedQuestIds[id])
		a.options.lightMode = true
		a:RefreshWindowThemes()
		a:Advance(0)
		Equal(frame.parchment.vertexColor[1], 1)
		Equal(frame.rows[1].title.textColor[1], lightInk)
		Equal(frame.headers[1].textColor[1], lightHeader)
		Equal(frame.rows[2].background.textureColor[4], frame.rows[3].background.textureColor[4])
		Equal(#a.wire, 0)
	end
)

QuestTogether:RegisterTest("light mode option persists only booleans and schedules a theme refresh", function()
	local a = Fixture()
	a.db = { profile = { lightMode = false } }
	local refreshes = 0
	function a:RefreshWindowThemes()
		refreshes = refreshes + 1
	end
	Equal(QuestTogether.SetOption(a, "lightMode", "true"), false)
	Equal(a.db.profile.lightMode, false)
	Equal(refreshes, 0)
	Equal(QuestTogether.SetOption(a, "lightMode", true), true)
	Equal(a.db.profile.lightMode, true)
	Equal(refreshes, 1)
	Equal(QuestTogether.SetOption(a, "lightMode", false), true)
	Equal(a.db.profile.lightMode, false)
	Equal(refreshes, 2)
end)

QuestTogether:RegisterTest(
	"quest log minimum width follows the visible party and closes the gap before share actions",
	function()
		local a = Fixture(nil, { Quest(1, "Local quest", true) })
		local parent = AttachUI(a)
		parent:SetSize(1920, 1200)
		a:Roster(a.name, "Friend-Realm", "Third-Realm")
		a:OpenPartyQuestCompare()
		a:Advance(0)
		Reply(a, "Friend-Realm", {}, true, true)
		a:RenderPartyQuestCompare()
		local frame = a.partyQuestCompareWindow
		frame:SetSize(1, 500)
		Equal(frame:GetWidth(), 962)
		Equal(frame.horizontal:IsShown(), false)
		local row = frame.rows[1]
		assert(row.action:IsShown())
		Equal(row.action:GetWidth(), 148)
		local actionX = row.action.points[1][2]
		Equal(actionX, 740) -- Immediately after the quest and three member columns.
		assert(actionX + row.action:GetWidth() <= frame.viewport:GetWidth())
		assert(frame.search:GetWidth() + 88 < frame.filter.points[1][2])
		local firstSession = a.partyQuestCompareSession
		a:Roster(a.name, "Friend-Realm", "Third-Realm", "Fourth-Realm", "Fifth-Realm")
		a:OnPartyQuestRosterChanged()
		a:Advance(0)
		a:RenderPartyQuestCompare()
		assert(a.partyQuestCompareSession ~= firstSession)
		Equal(frame:GetWidth(), 1222) -- Grow enough to avoid hiding newly added columns.
		Equal(frame.horizontal:IsShown(), false)
		a:Roster(a.name, "Friend-Realm")
		a:OnPartyQuestRosterChanged()
		a:Advance(0)
		a:RenderPartyQuestCompare()
		Equal(frame:GetWidth(), 1222) -- Departure unlocks resizing, without moving the window.
		frame:SetSize(1, 500)
		Equal(frame:GetWidth(), 832)
		Equal(frame.horizontal:IsShown(), false)
		a:Roster(a.name)
		a:OnPartyQuestRosterChanged()
		a:Advance(0)
		a:RenderPartyQuestCompare()
		frame:SetSize(1, 500)
		Equal(frame:GetWidth(), 780)
		assert(frame.search:GetWidth() + 88 < frame.filter.points[1][2])
		Equal(frame.horizontal:IsShown(), false)
	end
)

QuestTogether:RegisterTest("quest log leader crown updates without requesting new snapshots", function()
	local a = Fixture(nil, { Quest(1, "Local quest", true) })
	AttachUI(a)
	a.leaderUnit = "player"
	a.API.GetPartyVisualLeaderUnit = function() return a.leaderUnit end
	function a:GetUnitFullName(unit)
		return unit == "player" and self.name or "Friend-Realm"
	end
	function a:QueuePartyNavigationUpdate() end
	a:OpenPartyQuestCompare()
	a:Advance(0)
	a:RenderPartyQuestCompare()
	local frame, session = a.partyQuestCompareWindow, a.partyQuestCompareSession
	assert(frame.headerCrowns[1]:IsShown())
	assert(not frame.headerCrowns[2]:IsShown())
	local sent, renders = #a.wire, a.renders
	a.leaderUnit = "party1"
	a:HandleGroupRosterChanged("GROUP_ROSTER_UPDATE")
	Equal(a.partyQuestCompareSession, session)
	Equal(a.renders, renders + 1)
	Equal(#a.wire, sent)
	a:RenderPartyQuestCompare()
	assert(not frame.headerCrowns[1]:IsShown())
	assert(frame.headerCrowns[2]:IsShown())
	-- Unavailable/invalid native data clears the crown instead of retaining it.
	a.leaderUnit = "target"
	a:RenderPartyQuestCompare()
	assert(not frame.headerCrowns[1]:IsShown() and not frame.headerCrowns[2]:IsShown())
	a.leaderUnit = "player"
	a.blocked = true
	Equal(a:GetPartyQuestLeaderName(), nil)
	a.blocked = false
	session.mode = "target"
	a:RenderPartyQuestCompare()
	assert(not frame.headerCrowns[1]:IsShown() and not frame.headerCrowns[2]:IsShown())
	session.mode = "party"
	a.leaderUnit = "party1"
	a:RenderPartyQuestCompare()
	assert(frame.headerCrowns[2]:IsShown())
	table.remove(session.members, 2)
	a:RenderPartyQuestCompare()
	assert(not frame.headerCrowns[2]:IsShown())
end)

QuestTogether:RegisterTest("quest log journal buttons open only owned current quests and leave expansion alone", function()
	local a = ObjectiveFixture()
	AttachUI(a)
	a.openedQuests = {}
	a.API.CanOpenQuestJournal = function() return true end
	a.API.OpenQuestJournal = function(id) a.openedQuests[#a.openedQuests + 1] = id; return true end
	function a:Print(text) self.lastMessage = text end
	a:OpenPartyQuestCompare()
	a:Advance(0)
	Reply(a, "Friend-Realm", { Quest(3, "Remote quest", true) }, true, true)
	a:RenderPartyQuestCompare()
	local frame, ownRow, missingRow = a.partyQuestCompareWindow
	for _, row in ipairs(frame.rows) do
		if row.data and row.data.questId == 1 then ownRow = row end
		if row.data and row.data.questId == 3 then missingRow = row end
	end
	assert(ownRow.journal:IsShown())
	assert(not missingRow.journal:IsShown())
	assert(ownRow.title:GetWidth() < missingRow.title:GetWidth())
	ownRow.journal.scripts.OnClick()
	Equal(a.openedQuests[1], 1)
	assert(not a.partyQuestCompareSession.expandedQuestIds[1])
	missingRow.journal.scripts.OnClick()
	Equal(#a.openedQuests, 1)
	a.blocked = true
	ownRow.journal.scripts.OnClick()
	Equal(#a.openedQuests, 1)
	a.blocked = false
	-- Native ownership can disappear before the visible snapshot refreshes.
	a.entries = {}
	ownRow.journal.scripts.OnClick()
	Equal(#a.openedQuests, 1)
	Equal(a.lastMessage, "This quest is not in your quest log.")
	a.partyQuestCompareSession = nil
	ownRow.journal.scripts.OnClick()
	Equal(#a.openedQuests, 1)
end)

QuestTogether:RegisterTest("quest log preview journal buttons simulate opening and clear on pooled detail rows", function()
	local a = PreviewFixture()
	function a:OpenQuestJournalFromChatLog() error("preview opened a native quest") end
	a:OpenPartyQuestComparePreview()
	local preview, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
	local row
	for _, candidate in ipairs(frame.rows) do
		if candidate.data and candidate.journal:IsShown() then row = candidate; break end
	end
	assert(row)
	row.journal.scripts.OnClick()
	assert(frame.summary.text:find("Preview only: Open in Quest Log", 1, true))
	preview:TogglePartyQuestObjectives(row.data.questId)
	for _, candidate in ipairs(frame.rows) do
		if candidate.data and candidate.data.kind then assert(not candidate.journal:IsShown()) end
	end
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest("quest log focus preview follows stops and preserves selection for missing quests", function()
	local a = ObjectiveFixture()
	AttachUI(a)
	a:OpenPartyQuestComparePreview()
	local p, frame = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
	local menu = {}
	function menu:CreateTitle() end
	function menu:CreateButton(_, click) self.click = click end
	p:PopulatePartyFocusMenu(menu, "Aria-AeriePeak")
	menu.click()
	Equal(p.previewFocus, 2)
	assert(frame.followStatus.text:find("Aria", 1, true))
	p:PopulatePartyFocusMenu(menu, "Borin-AeriePeak")
	menu.click()
	Equal(p.previewFocus, 2)
	Equal(p.previewFollowing, nil)
	assert(a.partyFocusMissingPreview:IsShown())
	p:PopulatePartyFocusMenu(menu, "Celia-AeriePeak")
	menu.click()
	Equal(p.previewFocus, 5)
	Equal(p.previewFollowStatus, nil)
	p:PopulatePartyFocusMenu(menu, "Dara-AeriePeak")
	menu.click()
	Equal(p.previewFocus, 5)
	Equal(p.previewFollowing, nil)
	assert(a.partyFocusMissingPreview:IsShown())
	p:StopPartyQuestFollow()
	Equal(p:GetPartyFollowingText(), "")
	p:RefreshPartyQuestCompare()
	Equal(p.previewFocus, nil)
	Equal(p.previewFollowing, nil)
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("themed request previews cannot consume live requests or change preferences", function()
	local a = Fixture()
	AttachUI(a)
	function a:Print(text) self.previewWarning = text end
	local liveShare, liveJoin = {}, {}
	a.partyQuestSharePrompt, a.partyJoinPrompt = liveShare, liveJoin
	function a:ConfirmPartyQuestShare() error("preview shared a real quest") end
	function a:ConfirmPartyJoin() error("preview invited a real player") end
	function a:FinishPartyQuestShare() error("preview consumed a real share") end
	function a:FinishPartyJoin() error("preview consumed a real join") end
	assert(a:HandleSlashCommand("preview share"))
	local share = a.partyQuestSharePreviewPrompt
	Equal(#share.scrollPieces, 9)
	assert(share.previewNote and share:IsShown())
	share.always:SetChecked(true)
	share.share.scripts.OnClick()
	assert(not share:IsShown())
	assert(a:HandleSlashCommand("preview join"))
	local join = a.partyJoinPreviewPrompt
	join.friends:SetChecked(true)
	join.lfg:SetChecked(true)
	join.invite.scripts.OnClick()
	assert(not join:IsShown())
	Equal(a.partyQuestSharePrompt, liveShare)
	Equal(a.partyJoinPrompt, liveJoin)
	Equal(a.options.autoInviteFriends, nil)
	Equal(a.options.autoInviteWhileLFG, nil)
	Equal(#a.wire, 0)
	assert(a:ShowDialogPreview("share"))
	Equal(share.always:GetChecked(), false)
	share.close.scripts.OnClick()
	assert(not share:IsShown())
	a.blocked = true
	Equal(a:ShowDialogPreview("join"), false)
	assert(a.previewWarning:find("unavailable", 1, true))
	assert(not join:IsShown())
end)

QuestTogether:RegisterTest("scroll dialog themes refresh existing controls without resetting consent", function()
	local a = Fixture()
	AttachUI(a)
	assert(a:ShowDialogPreview("join"))
	local frame = a.partyJoinPreviewPrompt
	frame.friends:SetChecked(true)
	assert(frame.scrollPieces[1].vertexColor[1] < 0.2)
	a.options.lightMode = true
	a:QueueScrollDialogThemeRefresh()
	a:Advance(0)
	Equal(frame.scrollPieces[1].vertexColor[1], 1)
	assert(frame.message.textColor[1] < 0.3)
	assert(frame.friends:GetChecked())
	a.blocked = true
	a.options.lightMode = false
	Equal(a:ApplyScrollDialogTheme(frame), false)
	Equal(frame.scrollPieces[1].vertexColor[1], 1)
	a.blocked = false
	assert(a:ApplyScrollDialogTheme(frame))
	assert(frame.message.textColor[1] > 0.9)
	frame.forbidden = true
	Equal(a:ApplyScrollDialogTheme(frame), false)
end)

QuestTogether:RegisterTest("bubble dialog preview uses private controls without touching live edit state", function()
	local a = Fixture()
	AttachUI(a)
	local liveDialog, liveSession = {}, {}
	a.personalBubbleEditModeDialog, a.personalBubbleEditSession = liveDialog, liveSession
	function a:ConfigurePersonalBubbleDialogSlider(frame, data, callback)
		frame.settingData, frame.change = data, callback
		frame.Label = frame.Label or Frame(frame)
		frame.Slider = frame.Slider or Frame(frame)
		frame.Slider.RightText = frame.Slider.RightText or Frame(frame.Slider)
		function frame.Label:GetStringHeight() return 32 end
	end
	function a:SetOption() error("preview changed a saved option") end
	function a:DeselectPersonalBubbleAnchor() error("preview deselected the live bubble") end
	assert(a:HandleSlashCommand("preview bubble"))
	local frame = a.personalBubbleEditModePreviewDialog
	assert(frame:IsShown())
	Equal(#frame.scrollPieces, 9)
	Equal(frame.SizeSlider:GetWidth(), frame.contentWidth)
	local slider = frame.SizeSlider.Slider
	Equal(slider:GetWidth() + 120 + 16 + 12 + slider.RightText:GetWidth(), frame.contentWidth)
	Equal(slider.RightText.points[1][1], "RIGHT")
	Equal(slider.RightText.points[1][2], frame.SizeSlider)
	frame.SizeSlider.change(160)
	frame.DurationSlider.change(8)
	frame.SaveButton.scripts.OnClick()
	frame.RevertButton.scripts.OnClick()
	frame.ResetButton.scripts.OnClick()
	Equal(a.personalBubbleEditModeDialog, liveDialog)
	Equal(a.personalBubbleEditSession, liveSession)
	assert(not frame.SaveButton.enabled)
	frame.CloseButton.scripts.OnClick()
	assert(not frame:IsShown())
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("window dragging preserves pickup position and scaled cursor offset", function()
	local a = Fixture()
	local root = AttachUI(a)
	function root:GetEffectiveScale() return 0.8 end
	function root:GetLeft() return 10 end
	function root:GetBottom() return 20 end
	a.cursorX, a.cursorY = 600, 500
	function a:GetWindowDragCursor() return self.cursorX, self.cursorY end
	local frame = a:CreateScrollDialog(500, 400, "Drag fixture")
	frame:Show()
	frame.effectiveScale = 0.6
	function frame:GetEffectiveScale() return self.effectiveScale end
	function frame:GetLeft() return 200 end
	function frame:GetTop() return 700 end
	local initialPoint = frame.points[1]
	frame.scripts.OnDragStart(frame)
	assert(frame.dragging)
	Equal(frame.points[1], initialPoint)
	local driver = frame.windowDragDriver
	driver.scripts.OnUpdate()
	Equal(frame.points[1], initialPoint)
	a.cursorX, a.cursorY = 660, 470
	driver.scripts.OnUpdate()
	local point = frame.points[1]
	Equal(point[1], "TOPLEFT")
	Equal(point[2], root)
	assert(math.abs(point[4] * 0.6 + 10 * 0.8 - (200 * 0.6 + 60)) < 0.001)
	assert(math.abs(point[5] * 0.6 + 20 * 0.8 - (700 * 0.6 - 30)) < 0.001)
	-- Returning to the exact pickup position must also update the anchor.
	a.cursorX, a.cursorY = 600, 500
	driver.scripts.OnUpdate()
	assert(math.abs(frame.points[1][4] * 0.6 + 8 - 120) < 0.001)
	frame.scripts.OnDragStop(frame)
	Equal(frame.dragging, nil)
	Equal(driver.scripts.OnUpdate, nil)
	assert(not driver:IsShown())
	-- Repeated pickup after a scale/reanchor still starts without changing points.
	frame.effectiveScale = 1
	initialPoint = frame.points[1]
	assert(a:StartWindowDrag(frame))
	Equal(frame.windowDragDriver, driver)
	Equal(frame.points[1], initialPoint)
	a.blocked = true
	driver.scripts.OnUpdate()
	Equal(frame.dragging, nil)
	Equal(a:StartWindowDrag(frame), false)
	a.blocked = false
	assert(a:StartWindowDrag(frame))
	frame:Hide()
	Equal(frame.dragging, nil)
	Equal(driver.scripts.OnUpdate, nil)
	frame:Show()
	assert(a:StartWindowDrag(frame))
	frame.effectiveScale = 0.5
	driver.scripts.OnUpdate()
	Equal(frame.dragging, nil)
end)

QuestTogether:RegisterTest("isolated compare preview delegates drag callbacks without live session changes", function()
	local a = Fixture()
	local root = AttachUI(a)
	function root:GetEffectiveScale() return 1 end
	function root:GetLeft() return 0 end
	function root:GetBottom() return 0 end
	a.cursorX, a.cursorY = 600, 500
	function a:GetWindowDragCursor() return self.cursorX, self.cursorY end
	local liveSession = {}
	a.partyQuestCompareSession = liveSession
	assert(a:OpenPartyQuestComparePreview())
	local preview = a.partyQuestComparePreview
	local frame = preview.partyQuestCompareWindow
	function frame:GetEffectiveScale() return 0.8 end
	function frame:GetLeft() return 200 end
	function frame:GetTop() return 700 end
	-- Releasing without a successful pickup must be harmless too.
	frame.scripts.OnDragStop(frame)
	frame.scripts.OnDragStart(frame)
	assert(frame.dragging)
	a.cursorX, a.cursorY = 640, 480
	frame.windowDragDriver.scripts.OnUpdate()
	Equal(frame.points[1][4], 250)
	Equal(frame.points[1][5], 675)
	frame.scripts.OnDragStop(frame)
	Equal(frame.dragging, nil)
	Equal(frame.windowDragDriver.scripts.OnUpdate, nil)
	frame.scripts.OnDragStart(frame)
	frame:Hide()
	Equal(frame.dragging, nil)
	Equal(a.partyQuestCompareSession, liveSession)
	Equal(preview.API.SendAddonMessage, nil)
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest("Discord link dialog uses QT themes and supports safe dismissal", function()
	local a = Fixture()
	AttachUI(a)
	assert(a:HandleSlashCommand("preview discord"))
	local frame = a.discordLinkDialog
	assert(frame:IsShown())
	Equal(#frame.scrollPieces, 9)
	assert(frame.box.text:find("https://discord.gg/", 1, true))
	local original = frame.box.text
	frame.box.text = "changed"
	frame.box.scripts.OnTextChanged(frame.box, true)
	Equal(frame.box.text, original)
	a.options.lightMode = true
	a:QueueScrollDialogThemeRefresh()
	a:Advance(0)
	Equal(frame.scrollPieces[1].vertexColor[1], 1)
	assert(frame.box.textColor[1] < 0.3)
	a.blocked = true
	frame.box.scripts.OnEscapePressed()
	assert(not frame:IsShown())
	Equal(a:ShowDiscordLinkDialog(original), false)
	Equal(#a.wire, 0)
end)


QuestTogether:RegisterTest("preview namespace lists choices without triggering previews or sending chat", function()
	local a = Fixture()
	a.printed, a.opened = {}, {}
	function a:Print(text) self.printed[#self.printed + 1] = text end
	function a:SendQTChannelChat() error("preview input must not become chat") end
	function a:GetDebugController() error("preview help must not execute diagnostics") end
	function a:OpenPartyQuestComparePreview() self.opened[#self.opened + 1] = "compare"; return true end
	function a:OpenReleaseNotes() self.opened[#self.opened + 1] = "notes"; return true end
	function a:ShowDialogPreview(kind) self.opened[#self.opened + 1] = kind; return true end
	for _, command in ipairs({ "preview", "preview help", "preview typo", "preview join extra" }) do
		a:HandleSlashCommand(command)
	end
	Equal(#a.opened, 0)
	local help = table.concat(a.printed, "\n")
	assert(help:find("/qt preview compare", 1, true))
	assert(help:find("/qt preview announcement", 1, true))
	assert(not help:find("/qt bubbletest", 1, true))
	for _, command in ipairs({ "preview compare", "compare debug", "preview notes", "preview welcome", "preview partychat", "partychatpreview" }) do
		assert(a:HandleSlashCommand(command))
	end
	Equal(table.concat(a.opened, ","), "compare,compare,notes,notes,partychat,partychat")
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("snapshot freshness per-member refresh and closed-window polling stay bounded", function()
 local a = Fixture(nil, { Quest(1) }); AttachUI(a)
 a:OpenPartyQuestCompare(); a:Advance(0)
 Reply(a, "Friend-Realm", { Quest(2) }, true, true)
 local member = a.partyQuestCompareSession.byName["Friend-Realm"]
 Equal(a:GetPartyQuestSnapshotLabel(member), "Updated 0s ago")
 a.now = a.now + 20
 Equal(a:GetPartyQuestSnapshotLabel(member), "Updated 20s ago")
 local localMember = a.partyQuestCompareSession.byName[a.name]
 a:RefreshPartyQuestCompareMember(member.name)
 Equal(a.partyQuestCompareSession.byName[a.name], localMember)
 Equal(member.state, "loading")
 Reply(a, "Friend-Realm", { Quest(3) }, true, true)
 Equal(member.entries[2], nil); assert(member.entries[3])
 a.options.compareAutoRefresh = true
 a.now = a.now + 31
 a:UpdatePartyQuestCompareFreshness()
 local session = a.partyQuestCompareSession
 assert(session.byName[member.name] ~= member)
 a.partyQuestCompareWindow:Hide()
 local sent = #a.wire
 a.now = a.now + 120; a:UpdatePartyQuestCompareFreshness()
 Equal(#a.wire, sent)
end)
QuestTogether:RegisterTest("refresh retains scroll anchor and full text is accessible on hovered rows", function()
 local entries = {}; for id = 1, 30 do entries[id] = Quest(id, string.format("Quest %02d long complete title", id)) end
 local a = Fixture(nil, entries); AttachUI(a)
 function a:ShowSettingsTooltip(_, title) self.tooltipTitle = title end
 function a:HideSettingsTooltip() self.tooltipTitle = nil end
 a:OpenPartyQuestCompare(); a:Advance(0)
 Reply(a, "Friend-Realm", entries, true, true); a:RenderPartyQuestCompare()
 local frame = a.partyQuestCompareWindow
 frame.vertical:SetValue(300)
 local before = a.partyQuestCompareSession.scrollPixels
 a:RefreshPartyQuestCompare(); a:Advance(0)
 Reply(a, "Friend-Realm", entries, true, true); a:RenderPartyQuestCompare()
 Equal(a.partyQuestCompareSession.scrollPixels, before)
 local row = frame.rows[1]; row.scripts.OnEnter()
 Equal(a.tooltipTitle, row.data.title)
 row.scripts.OnLeave(); Equal(a.tooltipTitle, nil)
end)
QuestTogether:RegisterTest("reduced motion preview changes expansion and scrolling without animation", function()
 local a = Fixture(); AttachUI(a); a.options.reduceMotion = true
 a:OpenPartyQuestComparePreview()
 local p, f = a.partyQuestComparePreview, a.partyQuestComparePreview.partyQuestCompareWindow
 local row = f.rows[1]; row.scripts.OnMouseUp(row, "LeftButton")
 assert(not f.expansions and not f.expansionAnimator.scripts.OnUpdate)
 f.rowsViewport.scripts.OnMouseWheel(f.rowsViewport, -1)
 assert(p.partyQuestCompareSession.scrollPixels > 0 and not f.scripts.OnUpdate)
end)

QuestTogether:RegisterTest("PQL focus buttons gray by active follow and switch only after confirmation", function()
	local a = PreviewFixture()
	a:GetPartyQuestUIParent():SetSize(1920, 2000)
	a:OpenPartyQuestComparePreview()
	local p = a.partyQuestComparePreview
	local frame = p.partyQuestCompareWindow
	frame:SetSize(frame:GetWidth(), 1500)
	p:RenderPartyQuestCompare()
	local function Find(id, column)
		for _, row in ipairs(frame.rows) do
			if row.data and not row.data.kind and row.data.questId == id then return row.focusCells[column] end
		end
		error("quest not visible")
	end
	local own, remote = Find(2, 1), Find(2, 2)
	assert(not own.selected and remote.selected)
	assert(own.enabled and remote.enabled)
	assert(not own.icon.desaturated and not remote.icon.desaturated)
	assert(Find(13, 2).icon.desaturated and not Find(13, 2).enabled)
	Equal(remote.normal.atlas, "UI-QuestPoi-QuestNumber-SuperTracked")
	Equal(remote.icon.atlas, "Quest-In-Progress-Icon-Brown")
	Equal(Find(6, 1).icon.atlas, "UI-QuestIcon-TurnIn-Normal")
	own.scripts.OnClick()
	Equal(p.previewFocus, 2)
	remote.scripts.OnClick()
	Equal(p.previewFollowing, p.partyQuestCompareSession.members[2].name)
	assert(own.icon.desaturated)
	assert(not remote.icon.desaturated)
	assert(Find(13, 2).icon.desaturated)
	assert(Find(13, 3).icon.desaturated)
	-- Celia's active quest is gray but remains clickable to change follow target.
	local otherActive = Find(5, 4)
	assert(otherActive.selected and otherActive.enabled and otherActive.icon.desaturated)
	otherActive.scripts.OnClick()
	local warning = a.partyFocusChangePreview
	assert(warning:IsShown())
	Equal(p.previewFollowing, p.partyQuestCompareSession.members[2].name)
	warning.cancel.scripts.OnClick()
	Equal(p.previewFollowing, p.partyQuestCompareSession.members[2].name)
	otherActive.scripts.OnClick()
	warning.confirm.scripts.OnClick()
	Equal(p.previewFollowing, p.partyQuestCompareSession.members[4].name)
	assert(not otherActive.icon.desaturated)
	assert(remote.icon.desaturated)
	-- Peer focus changes transfer the only colored button within that column.
	p:AdvancePartyQuestFocus(p.previewFollowing)
	Equal(p.previewFocus, 6)
	assert(otherActive.icon.desaturated)
	assert(not Find(6, 4).icon.desaturated)
	Find(13, 1).scripts.OnClick()
	Equal(p.previewFocus, 6)
	warning.confirm.scripts.OnClick()
	Equal(p.previewFocus, 13)
	Equal(p.previewFollowing, nil)
	assert(not Find(13, 1).icon.desaturated)
	assert(not remote.icon.desaturated and not Find(6, 4).icon.desaturated)
	assert(Find(13, 2).icon.desaturated)
	for _, row in ipairs(frame.rows) do
		if row.data and not row.data.kind then
			for _, button in ipairs(row.focusCells) do
				Equal(button.icon.vertexColor[4], 1)
				Equal(button.normal.vertexColor[4], 1)
			end
		end
	end
	Equal(#a.wire, 0)
	p:CancelPartyQuestCompare()
	own.scripts.OnClick()
	Equal(p.previewFocus, 13)
end)
QuestTogether:RegisterTest("missing focus dialog preview is isolated and opens only mock PQL", function()
	local a = PreviewFixture()
	local live = { name = "Live", questID = 999 }
	a.partyFocusMissingNotice = live
	assert(a:HandleSlashCommand("preview focus"))
	local frame = a.partyFocusMissingPreview
	assert(frame:IsShown())
	assert(frame.message.text:find("Following has stopped", 1, true))
	assert(frame.message.points[1][2] >= 40)
	a.blocked = true
	frame.open.scripts.OnClick()
	assert(not a.partyQuestComparePreview)
	a.blocked = false
	frame.open.scripts.OnClick()
	assert(a.partyQuestComparePreview.partyQuestCompareWindow:IsShown())
	assert(not frame:IsShown())
	Equal(a.partyFocusMissingNotice, live)
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("missing focus notices defer during restrictions and discard superseded callbacks", function()
	local a = Fixture()
	AttachUI(a)
	function a:GetLocalizedQuestTitle() return "Local quest title" end
	function a:OpenPartyQuestCompare() self.openedForMissing = true; return true end
	a.blocked = true
	a:QueuePartyFocusMissingNotice("Friend-Realm", 1, "Remote title")
	a:Advance(0.1)
	assert(not rawget(a, "partyFocusMissingDialog"))
	a:ClearPartyFocusMissingNotice()
	a.blocked = false
	a:FlushDeferredWork("test resume")
	assert(not rawget(a, "partyFocusMissingDialog"))
	a:QueuePartyFocusMissingNotice("Friend-Realm", 2, "Remote title")
	a:Advance(0.1)
	local frame = a.partyFocusMissingDialog
	assert(frame:IsShown())
	assert(frame.message.text:find("Local quest title", 1, true))
	frame.open.scripts.OnClick()
	assert(a.openedForMissing)
	Equal(a.partyFocusMissingNotice, nil)
	assert(not frame:IsShown())
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("focus-change preview rejects stale confirmations and restrictions", function()
	local a = PreviewFixture()
	a:OpenPartyQuestComparePreview()
	local p = a.partyQuestComparePreview
	local session = p.partyQuestCompareSession
	local first, second = session.members[2].name, session.members[4].name
	assert(p:SelectPartyQuestFocus(first, 2))
	assert(p:RequestPartyQuestFocus(second, 5))
	local dialog = a.partyFocusChangePreview
	Equal(p.previewFollowing, first)
	a.blocked = true
	dialog.confirm.scripts.OnClick()
	Equal(p.previewFollowing, first)
	assert(dialog:IsShown())
	a.blocked = false
	dialog.confirm.scripts.OnClick()
	Equal(p.previewFollowing, second)
	assert(p:RequestPartyQuestFocus(session.playerName, 13))
	p:StopPartyQuestFollow()
	p:SelectPartyQuestFocus(first, 2)
	p:SelectPartyQuestFocus(second, 5)
	dialog.confirm.scripts.OnClick()
	Equal(p.previewFollowing, second)
	Equal(p.previewFocus, 5)
	assert(p:RequestPartyQuestFocus(session.playerName, 13))
	dialog.escapeAction()
	Equal(p.previewFollowing, second)
	Equal(#a.wire, 0)
	assert(a:HandleSlashCommand("preview unfollow"))
	dialog.confirm.scripts.OnClick()
	Equal(p.previewFollowing, second)
end)

local function NativePreviewFixture()
	local a = PreviewFixture()
	a.nativeFocus, a.nativeWrites = 101, {}
	a.actualEntries = { Quest(101, "Real quest one", true), Quest(102, "Real quest two", false), Quest(103, "Real quest three", true, true) }
	function a:BuildQuestCompareEntries() return self.actualEntries end
	function a:ReadQuestCompareObjectives(id)
		return { { text = "Real objective " .. id, kind = "item", current = 3, required = 7, finished = false } }
	end
	a.API.GetActiveTrackedQuestID = function() return a.nativeFocus > 0 and a.nativeFocus or nil end
	a.API.GetPartyNavigationNativeState = function()
		return { questID = a.nativeFocus, questCleared = a.nativeFocus == 0, mapID = 0, x = 0, y = 0 }
	end
	a.API.IsOnQuest = function(id)
		for _, entry in ipairs(a.actualEntries) do if entry.questId == id then return true end end
		return false
	end
	a.API.SetPartyNavigationQuest = function(id)
		assert(id == 0 or a.API.IsOnQuest(id), "synthetic quest reached native setter")
		a.nativeWrites[#a.nativeWrites + 1] = id
		if a.reject then return false end
		a.nativeFocus = id
		local p = a.partyQuestComparePreview
		if p and p.navigationObserver then p.navigationObserver.scripts.OnEvent() end
		return true
	end
	function a:ExternalFocus(id)
		self.nativeFocus = id
		local p = self.partyQuestComparePreview
		p.navigationObserver.scripts.OnEvent()
		p.navigationObserver.scripts.OnUpdate(p.navigationObserver, 0.3)
	end
	return a
end

QuestTogether:RegisterTest("native compare preview copies real quests and isolates simulated party progress", function()
	local a = NativePreviewFixture()
	assert(a:OpenPartyQuestComparePreview())
	local p = a.partyQuestComparePreview
	assert(p.liveQuestData)
	local session = p.partyQuestCompareSession
	Equal(session.playerName, a.name)
	Equal(session.members[1].classFile, "MAGE")
	Equal(#p:BuildPartyQuestDiffRows(), 5)
	Equal(session.members[1].entries[101].questTitle, "Real quest one")
	Equal(session.members[1].entries[102].isPushable, false)
	Equal(session.members[1].entries[103].isComplete, true)
	Equal(session.members[1].entries[900000000], nil)
	assert(session.members[2].entries[900000000])
	p:TogglePartyQuestObjectives(101)
	Equal(session.members[1].objectiveDetails[101].objectives[1].current, 3)
	Equal(session.members[2].objectiveDetails[101].objectives[1].text, "Real objective 101")
	session.members[2].entries[101].questTitle = "Edited simulation"
	Equal(a.actualEntries[1].questTitle, "Real quest one")
	Equal(#a.nativeWrites, 0)
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest("native compare preview follows mock changes and warns for Blizzard changes", function()
	local a = NativePreviewFixture()
	assert(a:OpenPartyQuestComparePreview())
	local p = a.partyQuestComparePreview
	local name = p.partyQuestCompareSession.members[2].name
	assert(p:SelectPartyQuestFocus(name, 101))
	Equal(p:GetPartyQuestFollowTarget(), name)
	p:AdvancePartyQuestFocus(name)
	Equal(a.nativeFocus, 102)
	Equal(p:GetPartyQuestFocusID(name), 102)
	a:ExternalFocus(103)
	Equal(a.nativeFocus, 102)
	Equal(p:GetPartyQuestFollowTarget(), name)
	local dialog = a.partyFocusChangePreview
	assert(dialog:IsShown())
	assert(dialog.message.text:find("affect your navigation", 1, true))
	dialog.cancel.scripts.OnClick()
	Equal(p:GetPartyQuestFollowTarget(), name)
	a:ExternalFocus(103)
	dialog.confirm.scripts.OnClick()
	Equal(a.nativeFocus, 103)
	Equal(p:GetPartyQuestFollowTarget(), nil)
	assert(p:SelectPartyQuestFocus(name, 102))
	p.partyQuestCompareSession.members[2].focusQuestId = 900000000
	p:ApplyPartyQuestFocus()
	Equal(p:GetPartyQuestFollowTarget(), nil)
	Equal(a.nativeFocus, 102)
	assert(a.partyFocusMissingPreview:IsShown())
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("native preview closes pending choices and never overwrites live follow intent", function()
	local a = NativePreviewFixture()
	a.partyNavigationState = { following = "Real Friend", followToken = {}, expectedQuest = 101 }
	a.db = { global = { partyQuestFollowByCharacter = { Me = "Real Friend" } } }
	a.activeCharacterKey = "Me"
	assert(a:OpenPartyQuestComparePreview())
	local p = a.partyQuestComparePreview
	local name = p.partyQuestCompareSession.members[2].name
	assert(p:SelectPartyQuestFocus(name, 101))
	a:ExternalFocus(102)
	local stale = a.partyFocusChangePreview.confirmAction
	a:ApplyPartyQuestFocus()
	Equal(a.partyNavigationState.following, "Real Friend")
	Equal(a.db.global.partyQuestFollowByCharacter.Me, "Real Friend")
	a:ClosePartyQuestComparePreview()
	Equal(p.partyQuestCompareSession, nil)
	Equal(p.partyNavigationState, nil)
	Equal(a:IsPartyQuestCompareNavigationPreviewActive(), false)
	Equal(stale(), false)
	Equal(p.API.SetPartyNavigationQuest(102), false)
	Equal(a.nativeFocus, 101)
	Equal(#a.wire, 0)
end)

QuestTogether:RegisterTest("party diff explains nonshareable and unknown quests without implying recipient eligibility", function()
	local a = Fixture("Me", { Quest(1, "Not shareable", false), Quest(2, "Unknown", nil), Quest(3, "Shared", true) })
	a.partyQuestCompareSession = { playerName = "Me", members = {
		{ name = "Me", state = "ready", isLocal = true, entries = { [1] = a.entries[1], [2] = a.entries[2], [3] = a.entries[3] } },
		{ name = "Other", state = "ready", supportsShareRequests = true, entries = { [4] = Quest(4, "Remote nonshareable", false), [5] = Quest(5, "Remote unknown", nil) } },
	}, byName = {} }
	for _, member in ipairs(a.partyQuestCompareSession.members) do a.partyQuestCompareSession.byName[member.name] = member end
	local rows = {}
	for _, row in ipairs(a:BuildPartyQuestDiffRows()) do rows[row.questId] = row end
	Equal(rows[1].hint, "Not shareable")
	Equal(rows[2].hint, "Shareability unknown")
	Equal(rows[3].action, "share")
	Equal(rows[3].hint, nil)
	Equal(rows[4].hint, "Not shareable")
	Equal(rows[5].hint, "Shareability unknown")
end)

QuestTogether:RegisterTest("native preview defers unreadable ownership and restrictions then refreshes real data", function()
	local a = NativePreviewFixture()
	assert(a:OpenPartyQuestComparePreview())
	local p = a.partyQuestComparePreview
	local name = p.partyQuestCompareSession.members[2].name
	assert(p:SelectPartyQuestFocus(name, 101))
	a.blocked = true
	p:AdvancePartyQuestFocus(name)
	Equal(a.nativeFocus, 101)
	a.blocked = false
	local getter = a.API.IsOnQuest
	a.API.IsOnQuest = function() return nil end
	p:ApplyPartyQuestFocus()
	Equal(p:GetPartyQuestFollowTarget(), name)
	Equal(a.nativeFocus, 101)
	a.API.IsOnQuest = getter
	p.navigationObserver.scripts.OnUpdate(p.navigationObserver, 0.3)
	Equal(a.nativeFocus, 102)
	-- Refresh reads a new owned snapshot, with no fabricated ownership.
	a.actualEntries = { Quest(201, "New real quest", true) }
	p:RefreshPartyQuestCompare()
	Equal(p:GetPartyQuestFollowTarget(), nil)
	Equal(p.partyQuestCompareSession.members[1].entries[101], nil)
	Equal(p.partyQuestCompareSession.members[1].entries[201].questTitle, "New real quest")
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
end)

QuestTogether:RegisterTest("closing native preview resumes an already applied real party focus", function()
	local a = NativePreviewFixture()
	a:Roster(a.name, "Real Friend")
	a.API.IsInRaid = function() return false end
	function a:GetPartyNavigationPeer(name)
		if name == "Real Friend" then return { questID = 101, title = "Real quest one" } end
	end
	a.partyNavigationState = { following = "Real Friend", followToken = {}, expectedQuest = 101, attempt = 101 }
	assert(a:OpenPartyQuestComparePreview())
	local p = a.partyQuestComparePreview
	assert(p:SelectPartyQuestFocus(a.name, 102))
	Equal(a.nativeFocus, 102)
	a:ApplyPartyQuestFocus()
	Equal(a.nativeFocus, 102)
	a:ClosePartyQuestComparePreview()
	assert(a.partyNavigationState.resuming)
	Equal(a.partyNavigationState.attempt, nil)
	a:ApplyPartyQuestFocus()
	Equal(a.nativeFocus, 101)
	Equal(a.partyNavigationState.following, "Real Friend")
	Equal(a.partyNavigationState.resuming, nil)
end)

QuestTogether:RegisterTest("reused focus textures reset atlas crops across readiness and selection changes", function()
	local a = Fixture(nil, { Quest(1, "Recycled quest", false, false) })
	AttachUI(a)
	function a:GetPartyQuestFocusID() return self.focusID or 0 end
	function a:GetPartyQuestFollowTarget() return self.followTarget end
	a:OpenPartyQuestCompare(); a:Advance(0); a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	local button = frame.rows[1].focusCells[1]
	local appliedWithFullCrop = {}
	assert(button.icon.parent ~= button.normal.parent, "fresh focus symbols must not share the button-state texture plane")
	Equal(button.icon.parent.parent, button)
	assert(button.icon.parent:GetFrameLevel() > button.normal.parent:GetFrameLevel(), "focus symbol must render above the circle")
	for _, texture in ipairs({ button.normal, button.pushed, button.icon }) do
		function texture:SetAtlas(atlas)
			appliedWithFullCrop[self] = table.concat(self.texCoords or {}, ",") == "0,1,0,1"
			self.atlas = atlas
			-- Model a previously cropped atlas on this same recycled texture.
			self.texCoords = { 0.7, 0.8, 0.2, 0.3 }
		end
		texture.texCoords = { 0.7, 0.8, 0.2, 0.3 }
	end
	local entry = a.partyQuestCompareSession.members[1].entries[1]
	for _, state in ipairs({ { true, 1 }, { true, 0 }, { false, 0 }, { false, 1 }, { true, 1, "Friend-Realm" } }) do
		entry.isComplete, a.focusID, a.followTarget = state[1], state[2], state[3]
		a:RenderPartyQuestCompare()
		Equal(frame.rows[1].focusCells[1], button)
		for _, texture in ipairs({ button.normal, button.pushed, button.icon }) do
			assert(appliedWithFullCrop[texture], "previous atlas crop must be reset before applying new artwork")
			Equal(texture.desaturated, state[3] ~= nil)
		end
		Equal(button.icon.atlas, state[1] and "UI-QuestIcon-TurnIn-Normal"
			or (state[2] == 1 and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow"))
		Equal(button.icon:GetWidth(), 16)
		Equal(button.icon:GetHeight(), 16)
	end
end)

QuestTogether:RegisterTest("focus artwork falls back on failed or silently rejected atlas changes and recovers", function()
	for _, failure in ipairs({ "missing", "throw", "false", "unchanged", "cleared", "unreadable" }) do
		local a = Fixture(nil, { Quest(1, "Ready quest", false, true) }); AttachUI(a)
		a:OpenPartyQuestCompare(); a:Advance(0); a:RenderPartyQuestCompare()
		local button = a.partyQuestCompareWindow.rows[1].focusCells[1]
		local icon = button.icon
		local originalSet, originalGet = icon.SetAtlas, icon.GetAtlas
		icon.atlas, icon.texCoords = "Quest-In-Progress-Icon-yellow", { 0.7, 0.8, 0.2, 0.3 }
		icon.SetAtlas = function(self)
			if failure == "throw" then error("fixture missing atlas") end
			if failure == "false" then return false end
			if failure == "cleared" then self.atlas = nil end
		end
		if failure == "missing" then icon.SetAtlas = false end
		if failure == "unreadable" then icon.GetAtlas = function() error("fixture unavailable atlas") end end
		a:RenderPartyQuestCompare()
		Equal(icon.texture, "Interface\\GossipFrame\\ActiveQuestIcon")
		Equal(table.concat(icon.texCoords, ","), "0,1,0,1")
		assert(button:IsShown())
		icon.SetAtlas, icon.GetAtlas = originalSet, originalGet
		a:RenderPartyQuestCompare()
		Equal(icon.atlas, "UI-QuestIcon-TurnIn-Normal")
	end
end)
