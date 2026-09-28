-- This module runs in /qt test too: all regions and adapters are private.
local QuestTogether = _G.QuestTogether
local function Equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function Region(addon, parent, kind)
	local region = { parent = parent, kind = kind, shown = true, scripts = {}, points = {}, writes = 0 }
	function region:IsForbidden()
		return self.forbidden == true or (self.parent and self.parent:IsForbidden()) or false
	end
	function region:IsProtected()
		return self.protected == true or (self.parent and self.parent:IsProtected()) or false
	end
	function region:IsShown()
		return self.shown
	end
	function region:IsVisible()
		return self.shown and (not self.parent or self.parent:IsVisible())
	end
	function region:Check()
		assert(not addon.blocked and not self:IsForbidden() and not self:IsProtected(), "unsafe owned mutation")
		self.writes = self.writes + 1
	end
	function region:Show()
		self:Check()
		self.shown = true
	end
	function region:Hide()
		self:Check()
		self.shown = false
	end
	function region:SetSize(width, height)
		self:Check()
		self.width, self.height = width, height
	end
	function region:SetWidth(value)
		self:Check()
		self.width = value
	end
	function region:SetHeight(value)
		self:Check()
		self.height = value
	end
	function region:GetWidth()
		assert(not self:IsForbidden())
		return self.width
	end
	function region:GetHeight()
		assert(not self:IsForbidden())
		return self.height
	end
	function region:SetScale(value)
		self:Check()
		self.scale = value
	end
	function region:SetPoint(...)
		self:Check()
		self.points[#self.points + 1] = { ... }
	end
	function region:ClearAllPoints()
		self:Check()
		self.points = {}
	end
	function region:SetText(value)
		self:Check()
		self.text = value
	end
	function region:SetFontObject(value)
		self:Check()
		self.font = value
	end
	function region:GetStringHeight()
		assert(not self:IsForbidden())
		if addon.measureUnavailable then
			return nil
		end
		local size = self.font == "GameFontNormalLarge" and 20 or 14
		local columns = math.max(1, math.floor((self.width or 500) / 7))
		return math.max(1, math.ceil(#(self.text or "") / columns)) * size
	end
	function region:SetScript(event, callback)
		self:Check()
		self.scripts[event] = callback
	end
	function region:CreateTexture(_, _, template)
		self:Check()
		if addon.failTextureCreate then
			addon.failTextureCreate = false
			error("fixture texture creation interrupted")
		end
		local texture = Region(addon, self, "Texture")
		texture.template = template
		addon.regions[#addon.regions + 1] = texture
		return texture
	end
	function region:CreateFontString(_, _, font)
		self:Check()
		local label = Region(addon, self, "FontString")
		label.font = font
		addon.regions[#addon.regions + 1] = label
		return label
	end
	function region:SetScrollChild(child)
		self:Check()
		self.child = child
	end
	function region:SetVerticalScroll(value)
		self:Check()
		self.offset = value
	end
	function region:SetMinMaxValues(minimum, maximum)
		self:Check()
		self.minimum, self.maximum = minimum, maximum
	end
	function region:SetValue(value)
		self:Check()
		self.value = value
		if self.scripts.OnValueChanged then
			self.scripts.OnValueChanged(self, value)
		end
	end
	function region:SetTexture(value)
		self:Check()
		self.texture = value
	end
	for _, method in ipairs({
		"SetFrameStrata",
		"SetToplevel",
		"SetFlattensRenderLayers",
		"SetClampedToScreen",
		"EnableMouse",
		"SetAllPoints",
		"SetHorizTile",
		"SetVertTile",
		"SetBlendMode",
		"SetColorTexture",
		"SetJustifyH",
		"SetJustifyV",
		"SetWordWrap",
		"SetNormalTexture",
		"SetPushedTexture",
		"SetHighlightTexture",
		"EnableMouseWheel",
		"SetOrientation",
		"SetValueStep",
		"SetThumbTexture",
	}) do
		region[method] = function(self)
			self:Check()
		end
	end
	return region
end

local function Fixture()
	local addon = setmetatable({ regions = {}, frames = {}, settingsOpened = 0 }, { __index = QuestTogether })
	addon.parent = Region(addon, nil, "Parent")
	addon.parent.width, addon.parent.height = 1920, 1080
	function addon:GetReleaseNotesUIParent()
		return self.parent
	end
	function addon:CreateReleaseNotesUIFrame(kind, name, parent, template)
		assert(not name and not template, "frames must use owned scripts and texture-only art")
		assert(not self.blocked and not parent:IsForbidden())
		local frame = Region(self, parent, kind)
		self.frames[#self.frames + 1] = frame
		self.regions[#self.regions + 1] = frame
		return frame
	end
	function addon:IsRuntimeRestricted()
		return self.blocked == true
	end
	function addon:OpenOptionsWindow()
		self.settingsOpened = self.settingsOpened + 1
		if self.settingsThrows then
			error("fixture settings unavailable")
		end
		return self.settingsResult ~= false
	end
	return addon
end

local function Notes(count)
	local items = {}
	for index = 1, count or 2 do
		items[index] = "Improvement " .. index .. ": quest progress is easier to follow with your party."
	end
	return {
		version = "5.9.2",
		welcome = "Quest progress and celebrations for your party.",
		sections = {
			{ title = "Latest changes", items = items },
		},
	}
end

QuestTogether:RegisterTest("release notes window sizes to content and reuses only owned frames", function()
	local a = Fixture()
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	local frame, frameCount = a.releaseNotesWindow, #a.frames
	assert(frame:IsVisible())
	Equal(frame.title.text, "QuestTogether 5.9.2")
	Equal(frame.logo.texture, "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon")
	assert(-frame.labels[1].points[1][3] > frame.logo.height, "welcome text must clear the logo")
	Equal(frame.labels[1].text, "Welcome to QuestTogether")
	Equal(frame.labels[3].text, "Latest changes")
	assert(frame.labels[4].text:find("Improvement 1", 1, true))
	Equal(frame.slider.shown, false)
	Equal(frame.maximumScroll, 0)
	Equal(a.parent.writes, 0)
	Equal(next(a.parent.scripts), nil)
	local firstHeight = frame.height
	assert(a:RenderReleaseNotesWindow(Notes(40), "5.10.0", false))
	Equal(a.releaseNotesWindow, frame)
	Equal(#a.frames, frameCount)
	Equal(frame.labels[1].text, "What's new")
	assert(frame.height > firstHeight and frame.maximumScroll > 0 and frame.slider.shown)
	assert(frame.height * frame.scale < a.parent.height)
	assert(a:RenderReleaseNotesWindow(Notes(1), "5.10.0", false))
	Equal(frame.slider.shown, false)
	Equal(frame.labels[5].shown, false)
	Equal(frame.scroll.offset, 0)
	Equal(frame.slider.value, 0)
	frame.settings.scripts.OnClick({})
	Equal(a.settingsOpened, 1)
	Equal(frame:IsVisible(), false)
	assert(a:RenderReleaseNotesWindow(Notes(1), "5.10.0", false))
	frame.close.scripts.OnClick({})
	Equal(frame:IsVisible(), false)
	assert(frame.footer.text:find("/qt notes", 1, true))
end)

QuestTogether:RegisterTest(
	"release notes settings action keeps the welcome visible when settings cannot open",
	function()
		local a = Fixture()
		assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
		local frame = a.releaseNotesWindow
		a.settingsResult = false
		frame.settings.scripts.OnClick({})
		assert(frame:IsVisible())
		a.settingsThrows = true
		frame.settings.scripts.OnClick({})
		assert(frame:IsVisible())
		a.settingsThrows, a.settingsResult = false, true
		frame.settings.scripts.OnClick({})
		Equal(frame:IsVisible(), false)
		Equal(a.settingsOpened, 3)
	end
)

QuestTogether:RegisterTest("release notes overflow scrolling clamps and resets when reopened", function()
	local a = Fixture()
	a.parent.width, a.parent.height = 480, 340
	assert(a:RenderReleaseNotesWindow(Notes(40), "5.9.2", false))
	local frame = a.releaseNotesWindow
	assert(frame.height * frame.scale <= a.parent.height)
	assert(frame.width * frame.scale <= a.parent.width)
	frame.scroll.scripts.OnMouseWheel({}, -2)
	Equal(frame.scroll.offset, 72)
	Equal(frame.slider.value, 72)
	frame.slider.scripts.OnValueChanged({}, frame.maximumScroll + 100)
	Equal(frame.scroll.offset, frame.maximumScroll)
	frame.slider.scripts.OnMouseWheel({}, 10000)
	Equal(frame.scroll.offset, 0)
	frame.slider.scripts.OnValueChanged({}, math.huge)
	Equal(frame.scroll.offset, 0)
	frame.slider.scripts.OnValueChanged({}, 100)
	assert(a:RenderReleaseNotesWindow(Notes(40), "5.9.2", false))
	Equal(frame.scroll.offset, 0)
	Equal(frame.slider.value, 0)
end)

QuestTogether:RegisterTest("release notes only confirms actual visibility and retries unavailable layout", function()
	local a = Fixture()
	a.parent.shown = false
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	assert(a.releaseNotesWindow:IsShown())
	Equal(a.releaseNotesWindow:IsVisible(), false)
	a.parent.shown = true
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	a.measureUnavailable = true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(a.releaseNotesWindow:IsShown(), false)
	a.measureUnavailable = false
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	local b = Fixture()
	b.parent.width = 0
	Equal(b:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#b.frames, 0)
	b.parent.width = math.huge
	Equal(b:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#b.frames, 0)
	b.parent.width = 800
	assert(b:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
end)

QuestTogether:RegisterTest("release notes stale callbacks and rendering respect restrictions and quarantine", function()
	for _, boundary in ipairs({ "restricted", "forbidden", "protected" }) do
		local a = Fixture()
		assert(a:RenderReleaseNotesWindow(Notes(40), "5.9.2", false))
		local frame = a.releaseNotesWindow
		if boundary == "restricted" then
			a.blocked = true
		else
			a.parent[boundary] = true
		end
		local writes = 0
		for _, region in ipairs(a.regions) do
			writes = writes + region.writes
		end
		frame.close.scripts.OnClick({})
		frame.settings.scripts.OnClick({})
		frame.scroll.scripts.OnMouseWheel({}, -1)
		frame.slider.scripts.OnValueChanged({}, 36)
		Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false), false)
		Equal(a.settingsOpened, 0)
		local after = 0
		for _, region in ipairs(a.regions) do
			after = after + region.writes
		end
		Equal(after, writes)
		a.blocked, a.parent.forbidden, a.parent.protected = false, false, false
		assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false))
	end
	local a = Fixture()
	a.blocked = true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#a.frames, 0)
	a.blocked, a.parent.forbidden = false, true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	Equal(#a.frames, 0)
end)

QuestTogether:RegisterTest(
	"release notes rejects an individually forbidden cached label without touching it",
	function()
		local a = Fixture()
		assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false))
		local label = a.releaseNotesWindow.labels[4]
		label.forbidden = true
		local writes = label.writes
		Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false), false)
		Equal(label.writes, writes)
		Equal(a.releaseNotesWindow:IsShown(), false)
		label.forbidden = false
		assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", false))
	end
)

QuestTogether:RegisterTest("release notes interrupted construction remains hidden and retries safely", function()
	local a = Fixture()
	a.failTextureCreate = true
	Equal(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true), false)
	local partial = a.releaseNotesWindow
	assert(partial and not partial:IsShown() and not partial.ready)
	assert(a:RenderReleaseNotesWindow(Notes(), "5.9.2", true))
	assert(a.releaseNotesWindow ~= partial and a.releaseNotesWindow.ready)
	Equal(partial:IsShown(), false)
	Equal(a.parent.writes, 0)
end)
