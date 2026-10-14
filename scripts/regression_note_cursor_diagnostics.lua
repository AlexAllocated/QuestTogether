-- All frames and API methods below are private fixtures, safe for /qt test.
local QT = _G.QuestTogether
local function Fixture()
	local addon = setmetatable({ isEnabled = true, reports = {}, frames = {}, focusCalls = 0 }, { __index = QT })
	function addon:IsWorkBlocked() return self.blocked == true end
	function addon:GetAddonVersion() return "fixture" end
	function addon:GetDiagnosticEnvironment() return { version = "test", build = "1", interface = "1", locale = "enUS" } end
	function addon:GetDebugController()
		return { ShowReport = function(_, report, title)
			assert(addon.playerNoteCursorProbe == nil, "capture must retire before opening report")
			assert(addon.playerNoteWindow.noteCursorProbeCounters == nil)
			addon.reports[#addon.reports + 1] = { report = report, title = title }
		end }
	end
	function addon:CreateOwnedUICleanupFrame()
		local region = self:CreateTestUIRegion(self)
		self.frames[#self.frames + 1] = region
		return region
	end
	local function Region(parent, kind)
		local region = addon:CreateTestUIRegion(addon, parent, kind)
		function region:GetObjectType() return kind end
		function region:GetRect() return 10, 10, self.width, self.height end
		function region:GetSize() return self.width, self.height end
		function region:GetAlpha() return self.alpha or 1 end
		function region:GetEffectiveAlpha() return self:GetAlpha() end
		function region:GetNumPoints() return #self.points end
		function region:GetDrawLayer() return "ARTWORK", 0 end
		function region:GetText() error("cursor capture must not read private text") end
		return region
	end
	local window = Region(nil, "Frame")
	addon.playerNoteWindow = window
	window.noteSession = {}
	window.identity = "PRIVATE_PLAYER_SENTINEL"
	window.scroll = Region(window, "ScrollFrame")
	window.box = Region(window.scroll, "EditBox")
	window.box.width, window.box.height = 400, 114
	function window.box:SetFocus() addon.focusCalls = addon.focusCalls + 1; self.focus = true end
	function window.box:GetBlinkSpeed() return 0.5 end
	function window.box:GetFont() return "FixtureFont", 14, "" end
	function window.box:GetTextInsets() return 8, 8, 0, 0 end
	function window.box:GetNumLines() return 1 end
	function window.box:GetCursorPosition() return 4 end
	function window.box:GetTextColor() return 1, 1, 1, 1 end
	function window.scroll:GetVerticalScroll() return 0 end
	function window.scroll:GetVerticalScrollRange() return 0 end
	function window:IsToplevel() return true end
	function window:GetFlattensRenderLayers() return true end
	local font = Region(window.box, "FontString")
	font.text = "PRIVATE_NOTE_SENTINEL"
	local caret = Region(window.box, "Texture")
	caret.width, caret.height = 1, 14
	function caret:GetTexture() return "Interface/CURSOR" end
	function caret:GetVertexColor() return 1, 1, 1, 1 end
	addon.caret = caret
	function addon:Step(elapsed)
		local probe = self.playerNoteCursorProbe
		if probe then probe.driver:RunScript("OnUpdate", elapsed) end
	end
	function addon:Finish()
		self:Step(0)
		for _ = 1, 15 do self:Step(0.2) end
	end
	return addon
end

QT:RegisterTest("note cursor capture observes native caret privately and reports only after three seconds", function()
	local a = Fixture()
	assert(a:CapturePlayerNoteCursorDiagnostics())
	assert(a.focusCalls == 0, "slash cleanup must finish before focus restoration")
	a:Step(0)
	assert(a.focusCalls == 1 and #a.reports == 0)
	local probe, stale = a.playerNoteCursorProbe, a.playerNoteCursorProbe.driver:GetScript("OnUpdate")
	for _ = 1, 14 do a:Step(0.2) end
	assert(#a.reports == 0)
	a.caret:Hide()
	probe.counters.cursorEvents = 50
	probe.counters.cursorW = 0
	a:Step(0.2)
	assert(#a.reports == 1 and a.focusCalls == 1)
	assert(probe.driver:GetScript("OnUpdate") == nil)
	local report = a.reports[1].report
	assert(report:find("samples=16 changes=2", 1, true))
	assert(report:find("texture.2 shown=false", 1, true))
	assert(report:find("points=0.000", 1, true))
	assert(report:find("cursorEvents=50.000", 1, true))
	assert(report:find("cursorW=0.000", 1, true))
	assert(report:find("cursorX=nil", 1, true), "unobserved geometry must not masquerade as zero")
	assert(not report:find("PRIVATE_", 1, true))
	stale(probe.driver, 10)
	assert(#a.reports == 1 and a.focusCalls == 1)
end)

QT:RegisterTest("note cursor capture cancels hidden replaced restricted and departed sessions without stale reports", function()
	for _, cancel in ipairs({
		function(a) a.playerNoteWindow:Hide() end,
		function(a) a.playerNoteWindow.box:Hide() end,
		function(a) a.playerNoteWindow.noteSession = {} end,
		function(a) a.playerNoteWindow = {} end,
		function(a) a.blocked = true end,
		function(a) a.isLoggingOut = true end,
		function(a) a.isEnabled = false end,
		function(a) a.playerNoteWindow.box.forbidden = true end,
	}) do
		local a = Fixture()
		assert(a:CapturePlayerNoteCursorDiagnostics())
		a:Step(0)
		local probe = a.playerNoteCursorProbe
		local stale = probe.driver:GetScript("OnUpdate")
		cancel(a)
		stale(probe.driver, 3)
		assert(a.playerNoteCursorProbe == nil and probe.window.noteCursorProbeCounters == nil)
		assert(probe.driver:GetScript("OnUpdate") == nil and #a.reports == 0)
		stale(probe.driver, 3)
		assert(#a.reports == 0 and a.focusCalls == 1)
	end
	local a = Fixture()
	assert(a:CapturePlayerNoteCursorDiagnostics())
	local probe, stale = a.playerNoteCursorProbe, a.playerNoteCursorProbe.driver:GetScript("OnUpdate")
	a.playerNoteWindow.noteSession = {}
	stale(probe.driver, 3)
	assert(a.focusCalls == 0 and #a.reports == 0, "cancelled startup must not steal focus later")
end)

QT:RegisterTest("note cursor capture supersedes probes and bounds texture reads samples and report memory", function()
	local a = Fixture()
	assert(a:CapturePlayerNoteCursorDiagnostics())
	local previous = a.playerNoteCursorProbe
	local stale = previous.driver:GetScript("OnUpdate")
	assert(a:CapturePlayerNoteCursorDiagnostics())
	local probe = a.playerNoteCursorProbe
	stale(previous.driver, 4)
	assert(a.playerNoteCursorProbe == probe and #a.reports == 0)
	assert(a.playerNoteWindow.noteCursorProbeCounters == probe.counters)
	assert(previous.driver == probe.driver and #a.frames == 1, "repeated captures reuse one owned observer")
	assert(probe.driver:GetScript("OnUpdate") ~= stale)
	local regions = {}
	for index = 1, 20 do
		regions[index] = a.caret
	end
	local reads = 0
	function a.caret:GetTexture()
		reads = reads + 1
		return string.rep("texture", 1000)
	end
	function a.playerNoteWindow.box:GetRegions() return unpack(regions) end
	a:Step(0)
	for index = 1, 15 do
		a.caret.alpha = index / 16
		a:Step(0.2)
	end
	assert(reads == 16 * 8 and probe.samples == 16)
	assert(#a.reports == 1 and #a.reports[1].report <= 16384)
	assert(a.reports[1].report:find("truncated=true", 1, true))
	assert(not a.reports[1].report:find("texture.9", 1, true))
	assert(a.reports[1].report:sub(-11) == "cursorH=nil", "final counters survive report truncation")
end)

QT:RegisterTest("note cursor capture safely reports missing inaccessible and failing native methods", function()
	local a, inaccessible = Fixture(), {}
	function a:CanAccessValue(value) return value ~= inaccessible end
	function a.playerNoteWindow.box:GetFont() return inaccessible, 14 end
	function a.caret:GetTexture() error("PRIVATE_NOTE_IN_ERROR") end
	function a.caret:GetAlpha() return inaccessible end
	a.caret.GetRect = false
	assert(a:CapturePlayerNoteCursorDiagnostics())
	a:Finish()
	local report = a.reports[1].report
	assert(report:find("font=inaccessible,14.000", 1, true))
	assert(report:find("alpha=inaccessible", 1, true))
	assert(report:find("texture=error", 1, true))
	assert(report:find("rect=unavailable", 1, true))
	assert(not report:find("PRIVATE_NOTE_IN_ERROR", 1, true))
	a.playerNoteWindow:Hide()
	assert(not a:CapturePlayerNoteCursorDiagnostics())
	assert(a.playerNoteCursorProbe == nil)
end)

QT:RegisterTest("note cursor diagnostics slash aliases stay local and bypass remote diagnostic requests", function()
	local a = Fixture()
	function a:CapturePlayerNoteCursorDiagnostics() self.captures = (self.captures or 0) + 1; return true end
	function a:RequestRemoteDiagnostics() error("cursor capture is local only") end
	function a:GetDebugController() error("cursor command must bypass generic diagnostic export") end
	a.isLocalDeveloper = true
	assert(a:HandleSlashCommand("diagnostics cursor"))
	assert(a:HandleSlashCommand(" DIAG CURSOR "))
	assert(a.captures == 2)
end)
