-- All fixtures are private addon objects. Never replace game globals in /qt test.
local QuestTogether = _G.QuestTogether
local function Equal(actual, expected)
	if actual ~= expected then
		error("expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
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
	function methods:IsForbidden() return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false end
	function methods:IsProtected() return self.protected == true or (self.parent and self.parent:IsProtected()) or false end
	function methods:SetScript(event, callback)
		self.scripts[event] = callback
	end
	function methods:CreateFontString()
		return Frame(self)
	end
	function methods:CreateTexture()
		return Frame(self)
	end
	function methods:SetText(value)
		self.text = value
	end
	function methods:SetWidth(value)
		self.width = value
	end
	function methods:SetHeight(value)
		self.height = value
	end
	function methods:SetSize(width, height)
		self.width, self.height = width, height
	end
	function methods:GetWidth()
		return self.width
	end
	function methods:GetHeight()
		return self.height
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
	-- These presentation-only methods are intentionally stubbed; behavioral
	-- methods above are implemented and all other method names are rejected.
	for _, name in ipairs({
		"SetPoint",
		"ClearAllPoints",
		"SetJustifyH",
		"SetJustifyV",
		"SetMaxLines",
		"SetTextColor",
		"SetFrameStrata",
		"SetToplevel",
		"SetFlattensRenderLayers",
		"SetClampedToScreen",
		"SetMovable",
		"EnableMouse",
		"RegisterForDrag",
		"StartMoving",
		"StopMovingOrSizing",
		"SetBackdrop",
		"SetBackdropColor",
		"SetBackdropBorderColor",
		"SetScale",
		"SetAllPoints",
		"SetColorTexture",
		"SetTexture",
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

QuestTogether:RegisterTest("comparison titles refresh on load results and drain a bounded load queue", function()
	local a = Fixture()
	AttachUI(a)
	a.QueuePartyQuestCompareRender = QuestTogether.QueuePartyQuestCompareRender
	local loaded, requests = {}, {}
	function a:GetQuestSnapshot() return nil end
	a.API.GetLocalizedQuestTitle = function(id) return loaded[id] end
	a.API.RequestLocalizedQuestTitle = function(id) requests[#requests + 1] = id end
	a:OpenPartyQuestCompare()
	local remote = {}
	for id = 1, 12 do remote[id] = Quest(id, "Foreign title " .. id) end
	Reply(a, "Friend-Realm", remote, true, true)
	a:Advance(0.1)
	Equal(#requests, 10)
	local id = requests[1]
	loaded[id] = "Loaded local title"
	a:QUEST_DATA_LOAD_RESULT(nil, id, true)
	a:Advance(0.1)
	local displayed = false
	for _, row in ipairs(a.partyQuestCompareWindow.rows) do
		if row.data and row.data.questId == id then
			Equal(row.title.text, "Loaded local title")
			displayed = true
		end
	end
	assert(displayed, "native load completion must replace the displayed fallback immediately")
	local wires = #a.wire
	for _ = 1, 8 do a:Advance(30) end
	local counts = {}
	for _, questID in ipairs(requests) do counts[questID] = (counts[questID] or 0) + 1 end
	for questID = 1, 12 do Equal(counts[questID], questID == id and 1 or 2) end
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
	function a:GetQuestSnapshot() return nil end
	a.API.GetLocalizedQuestTitle = function() return title end
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
	function a:RenderPartyQuestCompare() error("stale render reached replacement session") end
	a:Advance(0.1)
end)

QuestTogether:RegisterTest(
	"party compare vertical scrollbar follows filtered rows and resets a collapsed range",
	function()
		local entries = {}
		for id = 1, 13 do
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
		Reply(a, "Friend-Realm", { Quest(14) }, true, true)
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), true)
		Equal(frame.horizontal:IsShown(), false)
		frame.vertical:SetValue(1)
		Equal(a.partyQuestCompareSession.offset, 1)
		frame.filter:SetChecked(true)
		frame.filter.scripts.OnClick(frame.filter)
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), false)
		Equal(frame.vertical:GetValue(), 0)
		Equal(a.partyQuestCompareSession.offset, 0)
		frame.filter:SetChecked(false)
		frame.filter.scripts.OnClick(frame.filter)
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), true)
		frame.refresh.scripts.OnClick()
		a:RenderPartyQuestCompare()
		Equal(frame.vertical:IsShown(), false) -- Remote rows await a new snapshot.
	end
)

QuestTogether:RegisterTest(
	"party compare horizontal scrollbar follows column overflow independently of rows",
	function()
		local a = Fixture(nil, { Quest(1) })
		AttachUI(a)
		a:OpenPartyQuestCompare()
		a:RenderPartyQuestCompare()
		local frame = a.partyQuestCompareWindow
		local originalWidth = frame.viewport:GetWidth()
		frame.viewport:SetWidth(frame.content:GetWidth())
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), false) -- Exactly fitting columns need no bar.
		frame.viewport:SetWidth(frame.content:GetWidth() - 1)
		a:RenderPartyQuestCompare()
		Equal(frame.horizontal:IsShown(), true)
		Equal(frame.vertical:IsShown(), false)
		frame.horizontal:SetValue(1)
		Equal(frame.viewport.horizontalScroll, 1)
		frame.viewport:SetWidth(originalWidth)
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
	Equal(#frame.rows, 13)
	Equal(frame.title.text, "Party Quest Compare")
	Equal(frame.filter.children[1].text, "Hide quests I don't have")
	Equal(frame.filter.checked, false)
	Equal(#a:BuildPartyQuestDiffRows(), 2)
	frame.filter:SetChecked(true)
	frame.filter.scripts.OnClick(frame.filter)
	a:RenderPartyQuestCompare()
	Equal(a:GetOption("compareHideOtherQuests"), true)
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	Equal(frame.rows[1].action.text, "Share")
	frame.rows[1].action.scripts.OnClick()
	Equal(a.pushes, 1)
	frame.filter:SetChecked(false)
	frame.filter.scripts.OnClick(frame.filter)
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
	Equal(frame.filter.checked, false)
	Equal(frame.footer.text, "No quests to display.")
	Reply(a, "Friend-Realm", { Quest(2, "Their quest", true) }, true, true)
	a:RenderPartyQuestCompare()
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	frame.filter:SetChecked(true)
	frame.filter.scripts.OnClick(frame.filter)
	a:RenderPartyQuestCompare()
	Equal(#a:BuildPartyQuestDiffRows(), 0)
	assert(frame.footer.text:find("Uncheck ‘Hide quests I don't have’", 1, true))
	frame.filter:SetChecked(false)
	frame.filter.scripts.OnClick(frame.filter)
	a:RenderPartyQuestCompare()
	Equal(#a:BuildPartyQuestDiffRows(), 1)
	assert(not frame.footer.text:find("Uncheck", 1, true))
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
		"BuildQuestCompareEntries",
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
	assert(a:HandleSlashCommand("  compare   DEBUG  "))
	local preview, livePending = a.partyQuestComparePreview, a.pendingQuestCompareRequests.keep
	local frame = preview.partyQuestCompareWindow
	Equal(frame.shown, true)
	Equal(frame.title.text, "Party Quest Compare — Debug Preview")
	Equal(#frame.rows, 13)
	Equal(#preview.partyQuestCompareSession.members, 3)
	Equal(#preview:BuildPartyQuestDiffRows(), 16)
	Equal(frame.filter.checked, false)
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
	frame.vertical:SetValue(3)
	Equal(preview.partyQuestCompareSession.offset, 3)
	assert(frame.summary.text:find("DEBUG PREVIEW", 1, true))
	Equal(a.partyQuestCompareSession, liveSession)
	Equal(a.partyQuestShareState, liveShares)
	Equal(a.pendingQuestCompareRequests.keep, livePending)
	Equal(#a.wire, 0)
	Equal(a.pushes, 0)
	Equal(#a.delayed, 0)
end)

QuestTogether:RegisterTest("compare preview actions simulate feedback and Refresh and filter stay private", function()
	local a = PreviewFixture()
	assert(a:OpenPartyQuestComparePreview())
	local preview, share, request = a.partyQuestComparePreview
	local frame = preview.partyQuestCompareWindow
	for _, row in ipairs(frame.rows) do
		if row.data.action == "share" and not share then
			share = row
		end
		if row.data.action == "request" and not request then
			request = row
		end
	end
	assert(share and request)
	local sharedID, requestedID = share.data.questId, request.data.questId
	share.action.scripts.OnClick()
	Equal(share.hint.text, "Share attempted")
	request.action.scripts.OnClick()
	Equal(request.hint.text, "Awaiting confirmation")
	assert(frame.footer.text:find("Preview only", 1, true))
	frame.filter:SetChecked(true)
	frame.filter.scripts.OnClick(frame.filter)
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
	Equal(frame.filter.checked, true)
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
	Equal(rawget(a, "partyQuestComparePreview"), nil)
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
		assert(string.find(a.partyQuestCompareWindow.footer.text, "Join a party together", 1, true))
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
		Equal(a.partyQuestCompareWindow.title.text, "Party Quest Compare")
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
				Equal(a.partyQuestCompareWindow.footer.text, "Close the world map to finish loading quests.")
				session.message = "Existing feedback"
				a:RenderPartyQuestCompare()
				Equal(a.partyQuestCompareWindow.footer.text, "Existing feedback")
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
			assert(a.partyQuestCompareWindow.footer.text ~= "Close the world map to finish loading quests.")
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
		function a:GetPartyQuestUIParent() return Frame() end
		function a:CanAccessForeignFrame() return true end
		function a:CreatePartyQuestUIFrame() return Frame() end
		a:OpenPartyQuestCompare()
		Reply(a, "Friend-Realm", {}, true, true)
		a:RenderPartyQuestCompare()
		local frame = a.partyQuestCompareWindow
		Equal(frame.title.text, QuestTogether.TranslateForLocale("Party Quest Compare", locale))
		Equal(frame.filter.children[1].text, QuestTogether.TranslateForLocale("Hide quests I don't have", locale))
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
	local function T(key) return QuestTogether.TranslateForLocale(key, locale) end
	local a = Fixture(nil, { Quest(1, "Local quest", true) })
	AttachUI(a)
	a:OpenPartyQuestCompare()
	Reply(a, "Friend-Realm", {}, true, true)
	a:RenderPartyQuestCompare()
	local frame = a.partyQuestCompareWindow
	Equal(frame.title.text, T("Party Quest Compare"))
	Equal(frame.filter.children[1].text, T("Hide quests I don't have"))
	Equal(frame.rows[1].action.text, T("Share"))
	function a:GetQuestTitle() return "Local quest" end
	assert(a:HandlePartyQuestShareMessage(SharePacket(a), "Friend-Realm", "PARTY"))
	a:RenderPartyQuestSharePrompt()
	local prompt = a.partyQuestSharePrompt
	Equal(prompt.title.text, T("QuestTogether · Share request"))
	Equal(prompt.always.children[1].text, T("Always allow party share requests"))
	Equal(prompt.message.text, string.format(T("%s would like you to share\n[%s]\nwith the party."), "Friend-Realm", "Local quest"))
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

QuestTogether:RegisterTest("retired share and join prompts dismiss safely during restrictions without showing their successors", function()
	for _, kind in ipairs({ "share", "join" }) do
		local a = Fixture(nil, { Quest(1, "Share me", true) })
		AttachUI(a)
		a.QueuePartyQuestSharePrompt = QuestTogether.QueuePartyQuestSharePrompt
		function a:GetQuestTitle() return "Share me" end
		function a:SendPartyQuestShareMessage() return true end
		function a:SendPartyJoinMessage() return true end
		local first = { sender = kind == "share" and "Friend-Realm" or "Visitor-Realm", key = "first", questId = 1,
			requestId = "r1", id = "j1", order = 1, created = 100, expires = 160 }
		local second = { sender = kind == "share" and "Friend-Realm" or "Other-Realm", key = "second", questId = 1,
			requestId = "r2", id = "j2", order = 2, created = 101, expires = 170 }
		local render, finish, queue, state, frameKey
		if kind == "share" then
			a.partyQuestShareState = { incoming = { first = first, second = second } }
			state = a.partyQuestShareState
			render, finish, queue = a.RenderPartyQuestSharePrompt, a.FinishPartyQuestShare, a.QueuePartyQuestSharePrompt
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
end)

QuestTogether:RegisterTest("retired consent prompts quarantine protected and forbidden frames until safe teardown", function()
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
end)
