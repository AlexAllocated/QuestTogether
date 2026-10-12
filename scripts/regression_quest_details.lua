-- Private data and frame fixtures only; safe for /qt test.
local QT = _G.QuestTogether
local function Fixture()
	local a = setmetatable({ pending = {}, db = { profile = {} }, frames = {}, reads = 0, requests = 0 }, { __index = QT })
	function a:IsRuntimeRestricted() return self.blocked == true end
	function a:IsWorkBlocked() return self.blocked == true end
	function a:GetOption(key) return key == "windowScale" and 100 or false end
	function a:ScheduleRuntimeWork(_, key, callback, options)
		assert(options.lifetime == "ui" and options.owner)
		self.pending[key] = { run = callback, options = options }
	end
	function a:CancelRuntimeWorkOwner(owner)
		owner.active = false
		for key, pending in pairs(self.pending) do
			if pending.options.owner == owner then self.pending[key] = nil end
		end
	end
	function a:RecordDiagnosticError(_, err) self.error = tostring(err) end
	a.parent = QT:CreateTestUIRegion(a, nil, "Parent")
	a.parent.width, a.parent.height = 1280, 720
	function a:GetOwnedUIParent() return self.parent end
	function a:CreateOwnedWindowFrame(kind, name, parent, template)
		assert(name == nil and not self.blocked)
		local frame = QT:CreateTestUIRegion(self, parent, kind)
		self:ApplyTestUITemplate(frame, template)
		frame.events = {}
		function frame:RegisterEvent(event) self:Check(); self.events[event] = true end
		function frame:UnregisterAllEvents() self:Check(true); self.events = {} end
		self.frames[#self.frames + 1] = frame
		return frame
	end
	a.API = {
		CanOpenQuestDetails = function() return true end,
		GetQuestDetailsLink = function(id) return "quest:" .. id .. ":0" end,
		GetTooltipDataForHyperlink = function(link)
			a.reads = a.reads + 1
			a.lastLink = link
			return a.data
		end,
		RequestLocalizedQuestTitle = function(id) a.requests = a.requests + 1; a.requestedID = id end,
	}
	return a
end
local function Check(a, parentWrites)
	assert(not a.error, a.error)
	assert((a.invalidCalls or 0) == 0, "reader attempted an unsafe UI call")
	assert(a.parent.writes == (parentWrites or 0), "reader modified a foreign parent")
end
local function FlushRefresh(a)
	for key, pending in pairs(a.pending) do
		if pending.options.mode == "nextFrame" then
			a.pending[key] = nil
			pending.run()
		end
	end
end

QT:RegisterTest("quest reader copies generic tooltip prose and both columns without retaining foreign data", function()
	local a = Fixture()
	a.data = { dataInstanceID = 42, lines = {
		{ leftText = "|cffffff00Wolf Hunt|r" },
		{ leftText = "Please help the village.\nWe need supplies." },
		{ leftText = "|Ticon:16|tCollect |Hitem:1|h[Supplies]|h", rightText = "0/5" },
	} }
	local result = assert(a:ReadQuestDetails(12345))
	assert(result.text == "Wolf Hunt\n\nPlease help the village.\nWe need supplies.\n\nCollect [Supplies]    0/5")
	assert(result.dataInstanceID == 42 and a.lastLink == "quest:12345:0")
	a.data.lines[2].leftText = "changed"
	assert(result.text:find("Please help", 1, true))
end)

QT:RegisterTest("quest reader bounds native text and rejects inaccessible fields without unsafe reads", function()
	local a = Fixture()
	local inaccessible = setmetatable({}, { __index = function() error("inaccessible") end,
		__tostring = function() error("inaccessible") end })
	function a:CanAccessValue(value) return value ~= inaccessible end
	function a:CanAccessTable(value) return type(value) == "table" and value ~= inaccessible end
	for _, data in ipairs({ inaccessible, { lines = inaccessible }, { lines = {} } }) do
		a.data = data
		assert(a:ReadQuestDetails(1) == nil)
	end
	a.data = { dataInstanceID = inaccessible, lines = { inaccessible, { leftText = inaccessible, rightText = "Safe" } } }
	local safe = assert(a:ReadQuestDetails(1))
	assert(safe.text == "Safe" and safe.dataInstanceID == nil)
	for _, data in ipairs({ { lines = { { leftText = string.rep("x", 4097) } } },
		{ lines = {} }, { lines = {} } }) do
		if #data.lines == 0 then
			local count, length = a.limitCase and 9 or 129, a.limitCase and 4096 or 1
			for i = 1, count do data.lines[i] = { leftText = string.rep("x", length) } end
			a.limitCase = true
		end
		a.data = data
		local result, reason = a:ReadQuestDetails(1)
		assert(result == nil and reason == "too_large")
	end
	a.blocked = true
	local reads = a.reads
	assert(a:ReadQuestDetails(1) == nil and a.reads == reads)
end)

QT:RegisterTest("quest details use owned parchment scrolling and reset when another quest opens", function()
	local a = Fixture()
	a.data = { dataInstanceID = 42, lines = { { leftText = string.rep("Quest story. ", 250) } } }
	assert(a:ShowQuestDetails(12345, "|Hquesttogetherquest:12345|h[Wolf Hunt]|h"), a.error)
	local frame, count = a.questDetailsWindow, #a.frames
	assert(frame:IsVisible() and frame.title.text == "Wolf Hunt")
	assert(frame.body.text == a.data.lines[1].leftText:match("^(.-)%s*$"))
	assert(frame.maximumScroll > 0 and frame.scrollBar.template == "MinimalScrollBar")
	assert(frame.close.template == "UIPanelCloseButton")
	frame.scroll:RunScript("OnMouseWheel", -3)
	assert(frame.scrollOffset > 0)
	local oldSession = frame.session
	a.data = { lines = { { leftText = "Another quest" } } }
	assert(a:ShowQuestDetails(54321, "[Another quest]"), a.error)
	assert(a.questDetailsWindow == frame and #a.frames == count)
	assert(not oldSession.active and frame.scrollOffset == 0 and frame.maximumScroll == 0)
	assert(frame.body.text == "Another quest")
	frame.close:RunScript("OnClick")
	assert(not frame:IsShown() and frame.session == nil and next(frame.events) == nil)
	Check(a)
end)

QT:RegisterTest("quest details cache refreshes are scoped and retired callbacks cannot replace a new quest", function()
	local a = Fixture()
	assert(a:ShowQuestDetails(1, "[First]"), a.error)
	local frame = a.questDetailsWindow
	assert(frame.body.text == "Loading quest details..." and a.requests == 1)
	local timeout = a.pending.quest_details_timeout.run
	a.data = { dataInstanceID = 42, lines = { { leftText = "First description" } } }
	frame:RunScript("OnEvent", "QUEST_DATA_LOAD_RESULT", 1, true)
	FlushRefresh(a)
	assert(frame.body.text == "First description")
	local reads = a.reads
	frame:RunScript("OnEvent", "TOOLTIP_DATA_UPDATE", 99)
	FlushRefresh(a)
	assert(a.reads == reads)
	a.data.lines[1].leftText = "Resolved objectives"
	frame:RunScript("OnEvent", "TOOLTIP_DATA_UPDATE", 42)
	assert(a.reads == reads, "tooltip events should defer reading until the next frame")
	FlushRefresh(a)
	assert(frame.body.text == "Resolved objectives")
	a.data = nil
	assert(a:ShowQuestDetails(2, "[Second]"), a.error)
	timeout()
	assert(frame.body.text == "Loading quest details...")
	a.pending.quest_details_timeout.run()
	assert(frame.body.text == "Quest details are unavailable.")
	local retiredTimeout = a.pending.quest_details_timeout.run
	a:DismissManagedWindow(frame)
	a.data = { lines = { { leftText = "Late text" } } }
	retiredTimeout()
	frame:RunScript("OnEvent", "QUEST_DATA_LOAD_RESULT", 2, true)
	FlushRefresh(a)
	assert(not frame:IsShown() and frame.session == nil)
	Check(a)
end)

QT:RegisterTest("quest details suspend under hidden parents and refresh safely on return", function()
	local a = Fixture()
	a.data = { lines = { { leftText = "Initial" } } }
	assert(a:ShowQuestDetails(1, "[Quest]"), a.error)
	local frame, session = a.questDetailsWindow, a.questDetailsWindow.session
	a.parent:Hide()
	assert(frame:IsShown() and not frame:IsVisible() and frame.session == session)
	assert(next(frame.events) == nil)
	a.data.lines[1].leftText = "Updated"
	a.parent:Show()
	assert(frame.body.text == "Updated" and frame.session == session)
	a.blocked = true
	local reads = a.reads
	frame:RunScript("OnEvent", "QUEST_DATA_LOAD_RESULT", 1, true)
	assert(a.reads == reads)
	assert(not a:ShowQuestDetails(2, "[Blocked]"))
	a.blocked = false
	a:DismissManagedWindow(frame)
	Check(a, 2)
end)
