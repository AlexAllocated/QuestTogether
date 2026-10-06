local L = _G.QuestTogether.Translate
local QuestTogether = _G.QuestTogether
local LibChev = QuestTogether.LibChev
local LOGO = "Interface\\AddOns\\QuestTogether\\Media\\QuestTogetherIcon"
local HEADER_HEIGHT, FOOTER_HEIGHT = 48, 40
local CONTENT_TOP, CONTENT_BOTTOM = 108, 56

-- These factories are addon-owned seams. Tests supply private frames instead
-- of replacing CreateFrame, UIParent, or any shared Blizzard state.
function QuestTogether:GetReleaseNotesUIParent()
	return UIParent
end

function QuestTogether:CreateReleaseNotesUIFrame(...)
	return CreateFrame(...)
end

local function Guard(addon, region)
	return not addon:IsRuntimeRestricted() and LibChev.CanMutateOwnedRegion(region)
end

local function Call(addon, region, method, ...)
	if not Guard(addon, region) then
		error("release notes region unavailable", 0)
	end
	return region[method](region, ...)
end

local function ParentDimension(addon, parent, methodName)
	local method = addon:GetAccessibleFrameMember(parent, methodName)
	if type(method) ~= "function" then
		return nil
	end
	local ok, value = pcall(method, parent)
	value = ok and addon:SafeToNumber(value) or nil
	return value and value > 0 and value or nil
end

local function New(addon, kind, parent)
	if addon:IsRuntimeRestricted() or not addon:CanAccessForeignFrame(parent) then
		error("release notes parent unavailable", 0)
	end
	local frame = addon:CreateReleaseNotesUIFrame(kind, nil, parent)
	if not Guard(addon, frame) then
		error("release notes frame unavailable", 0)
	end
	return frame
end

local function Texture(addon, parent, template, layer, width, height)
	local texture = Call(addon, parent, "CreateTexture", nil, layer or "BORDER", template)
	Call(addon, texture, "ClearAllPoints")
	if width then
		Call(addon, texture, "SetSize", width, height)
	end
	return texture
end

local function Label(addon, parent, font)
	local label = Call(addon, parent, "CreateFontString", nil, "OVERLAY", font or "GameFontHighlight")
	Call(addon, label, "SetJustifyH", "LEFT")
	Call(addon, label, "SetJustifyV", "TOP")
	Call(addon, label, "SetWordWrap", true)
	return label
end

local function Script(addon, frame, region, event, callback)
	Call(addon, region, "SetScript", event, function(_, ...)
		-- Ignore the callback's self; only captured addon-owned objects are used.
		if Guard(addon, frame) and Guard(addon, region) then
			pcall(callback, ...)
		end
	end)
end

local function Button(addon, frame, parent, text, callback, arrow, jump)
	local button = New(addon, "Button", parent)
	local artwork = {
		{ "SetNormalTexture", "DialogButtonNormalTexture" },
		{ "SetPushedTexture", "DialogButtonPushedTexture" },
		{ "SetHighlightTexture", "DialogButtonHighlightTexture" },
	}
	if arrow then
		artwork[#artwork + 1] = { "SetDisabledTexture" }
	end
	for _, art in ipairs(artwork) do
		local texture = Texture(addon, button, not arrow and art[2] or nil, "ARTWORK")
		if arrow then
			-- The native Down artwork shifts its glyph. Keep all arrow states in
			-- the same position so the jump bar and hover overlay stay aligned.
			Call(addon, texture, "SetTexture", "Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "-Up")
			if art[1] == "SetPushedTexture" then
				Call(addon, texture, "SetVertexColor", 0.7, 0.7, 0.7, 1)
			elseif art[1] == "SetHighlightTexture" then
				Call(addon, texture, "SetBlendMode", "ADD")
				Call(addon, texture, "SetAlpha", 0.3)
			end
		end
		Call(addon, texture, "SetAllPoints")
		Call(addon, button, art[1], texture)
	end
	if jump then
		local bar = Texture(addon, button, nil, "OVERLAY", 2, 12)
		Call(addon, bar, "SetPoint", arrow == "PrevPage" and "LEFT" or "RIGHT", arrow == "PrevPage" and 9 or -9, 0)
		Call(addon, bar, "SetColorTexture", 1, 0.85, 0.55, 1)
	end
	button.label = Label(addon, button, "GameFontNormalSmall")
	Call(addon, button.label, "SetPoint", "CENTER")
	Call(addon, button.label, "SetJustifyH", "CENTER")
	Call(addon, button.label, "SetText", arrow and "" or text)
	if arrow then
		local tip = New(addon, "Frame", button)
		Call(addon, tip, "Hide")
		Call(addon, tip, "SetFrameStrata", "TOOLTIP")
		Call(addon, tip, "SetClampedToScreen", true)
		Call(addon, tip, "SetPoint", "TOP", button, "BOTTOM", 0, -4)
		local background = Texture(addon, tip, nil, "BACKGROUND")
		Call(addon, background, "SetAllPoints")
		Call(addon, background, "SetColorTexture", 0.04, 0.04, 0.04, 0.96)
		local label = Label(addon, tip, "GameFontHighlightSmall")
		Call(addon, label, "SetPoint", "CENTER")
		Call(addon, label, "SetText", text)
		local width = addon:SafeToNumber(Call(addon, label, "GetStringWidth")) or 100
		Call(addon, tip, "SetSize", math.ceil(width) + 20, 28)
		Script(addon, frame, button, "OnEnter", function()
			Call(addon, tip, "Show")
		end)
		local function HideTip()
			if LibChev.CanMutateOwnedRegion(tip) then
				tip:Hide()
			end
		end
		Call(addon, button, "SetScript", "OnLeave", HideTip)
		Call(addon, button, "SetScript", "OnHide", HideTip)
	end
	Script(addon, frame, button, "OnClick", callback)
	return button
end

local function SetScroll(addon, frame, value)
	value = addon:SafeToNumber(value)
	if not value then
		return
	end
	value = math.max(0, math.min(frame.maximumScroll or 0, value))
	Call(addon, frame.scroll, "SetVerticalScroll", value)
	frame.scrollOffset = value
	frame.syncScroll = true
	local ok, err = pcall(Call, addon, frame.slider, "SetValue", value)
	frame.syncScroll = false
	if not ok then
		error(err, 0)
	end
end

local function CreatePartnerExamples(addon, parent)
	local gallery = New(addon, "Frame", parent)
	Call(addon, gallery, "Hide")
	gallery.columns, gallery.themeLabels = {}, {}
	for index = 1, 2 do
		local column = New(addon, "Frame", gallery)
		gallery.columns[index] = column
		local heading = Label(addon, column, "GameFontNormalSmall")
		heading.themeRole = "heading"
		gallery.themeLabels[#gallery.themeLabels + 1] = heading
		Call(addon, heading, "SetPoint", "TOPLEFT")
		Call(addon, heading, "SetPoint", "TOPRIGHT")
		Call(addon, heading, "SetHeight", 32)
		Call(addon, heading, "SetJustifyH", "CENTER")
		Call(addon, heading, "SetText", index == 1 and L("QT player") or L("Looking for questing partners"))
		local logo = Texture(addon, column, nil, "ARTWORK", 32, 32)
		Call(addon, logo, "SetPoint", "TOP", column, "TOP", -28, -38)
		Call(addon, logo, "SetTexture", LOGO)
		if index == 2 then
			for layer = 1, 8 do
				local angle = (layer - 1) * math.pi / 4
				local glow = Texture(addon, column, nil, "BACKGROUND", 32, 32)
				Call(addon, glow, "SetPoint", "CENTER", logo, "CENTER", 4 * math.cos(angle), 4 * math.sin(angle))
				Call(addon, glow, "SetTexture", LOGO)
				Call(addon, glow, "SetVertexColor", 1, 0.78, 0.12, 0.9)
				Call(addon, glow, "SetBlendMode", "ADD")
			end
		end
		local function Circle(size, layer, r, g, b, alpha, additive)
			local circle = Texture(addon, column, nil, layer, size, size)
			Call(addon, circle, "SetPoint", "TOP", column, "TOP", 28, -54 + size / 2)
			Call(addon, circle, "SetColorTexture", r, g, b, alpha)
			if additive then
				Call(addon, circle, "SetBlendMode", "ADD")
			end
			local mask = Call(addon, column, "CreateMaskTexture")
			Call(addon, mask, "SetAllPoints", circle)
			Call(
				addon,
				mask,
				"SetTexture",
				"Interface\\CharacterFrame\\TempPortraitAlphaMask",
				"CLAMPTOBLACKADDITIVE",
				"CLAMPTOBLACKADDITIVE"
			)
			Call(addon, circle, "AddMaskTexture", mask)
		end
		if index == 1 then
			Circle(12, "BACKGROUND", 0, 0, 0, 1)
		else
			for layer = 1, 4 do
				Circle(16 - (layer - 1) * 2, "BACKGROUND", 1, 0.8, 0.15, 0.06 + layer * 0.07, true)
			end
		end
		Circle(9, "ARTWORK", 0.25, 0.78, 0.92, 1)
		for _, example in ipairs({ { -28, L("Logo") }, { 28, L("Map dot") } }) do
			local caption = Label(addon, column, "GameFontHighlightSmall")
			caption.themeRole = "body"
			gallery.themeLabels[#gallery.themeLabels + 1] = caption
			Call(addon, caption, "SetPoint", "TOP", column, "TOP", example[1], -80)
			Call(addon, caption, "SetText", example[2])
		end
	end
	return gallery
end

-- Slice the existing artwork so neither scroll roll nor its end caps stretch
-- with the body. All nine regions belong to this window.
local function CreateParchment(addon, frame)
	frame.parchmentPieces = {}
	local xs, ys = { 0, 32 / 1024, 992 / 1024, 1 }, { 0, 36 / 512, 476 / 512, 1 }
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = Texture(addon, frame, nil, "BACKGROUND")
			frame.parchmentPieces[#frame.parchmentPieces + 1] = piece
			Call(addon, piece, "SetTexture", addon:GetScrollWindowTheme().texture)
			Call(addon, piece, "SetTexCoord", xs[column], xs[column + 1], ys[row], ys[row + 1])
			local left = column == 1 and 0 or 32
			local right = column == 3 and 0 or -32
			local top = row == 1 and 0 or -HEADER_HEIGHT
			local bottom = row == 3 and 0 or FOOTER_HEIGHT
			if column == 2 then
				Call(addon, piece, "SetPoint", "TOPLEFT", frame, "TOPLEFT", left, top)
				Call(addon, piece, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
			else
				local side = column == 1 and "LEFT" or "RIGHT"
				Call(addon, piece, "SetPoint", "TOP" .. side, frame, "TOP" .. side, 0, top)
				Call(addon, piece, "SetPoint", "BOTTOM" .. side, frame, "BOTTOM" .. side, 0, bottom)
				Call(addon, piece, "SetWidth", 32)
			end
			-- The top/bottom slices have fixed heights, so replace the vertical anchors.
			if row ~= 2 then
				Call(addon, piece, "ClearAllPoints")
				local edge = row == 1 and "TOP" or "BOTTOM"
				if column == 2 then
					Call(addon, piece, "SetPoint", edge .. "LEFT", frame, edge .. "LEFT", 32, 0)
					Call(addon, piece, "SetPoint", edge .. "RIGHT", frame, edge .. "RIGHT", -32, 0)
				else
					local side = column == 1 and "LEFT" or "RIGHT"
					Call(addon, piece, "SetPoint", edge .. side, frame, edge .. side, 0, 0)
				end
				Call(addon, piece, "SetHeight", row == 1 and HEADER_HEIGHT or FOOTER_HEIGHT)
			end
		end
	end
end

local function HistoryRow(addon, frame, selected)
	local row = New(addon, "Button", frame.content)
	row.background = Texture(addon, row, nil, "BACKGROUND")
	Call(addon, row.background, "SetAllPoints")
	local highlight = Texture(addon, row, nil, "HIGHLIGHT")
	Call(addon, highlight, "SetAllPoints")
	Call(addon, highlight, "SetColorTexture", 0.8, 0.65, 0.35, 0.16)
	Call(addon, row, "SetHighlightTexture", highlight)
	row.rule = Texture(addon, row, nil, "BORDER")
	Call(addon, row.rule, "SetPoint", "BOTTOMLEFT", 12, 0)
	Call(addon, row.rule, "SetPoint", "BOTTOMRIGHT", -12, 0)
	Call(addon, row.rule, "SetHeight", 1)
	row.version = Label(addon, row, "GameFontNormal")
	Call(addon, row.version, "SetPoint", "TOPLEFT", 14, -10)
	row.date = Label(addon, row, "GameFontHighlightSmall")
	Call(addon, row.date, "SetPoint", "TOPRIGHT", -14, -12)
	Call(addon, row.date, "SetJustifyH", "RIGHT")
	Call(addon, row.date, "SetWidth", 110)
	row.label = Label(addon, row, "GameFontHighlight")
	Call(addon, row.label, "SetPoint", "TOPLEFT", 14, -32)
	Script(addon, frame, row, "OnClick", function()
		addon:ShowReleaseNotesPage(selected)
	end)
	return row
end

local function Create(addon, parent)
	local frame = New(addon, "Frame", parent)
	Call(addon, frame, "Hide")
	-- Cache immediately so an interrupted build can be hidden and retried.
	addon.releaseNotesWindow = frame
	Call(addon, frame, "SetPoint", "CENTER")
	Call(addon, frame, "SetFrameStrata", "MEDIUM")
	Call(addon, frame, "SetToplevel", true)
	Call(addon, frame, "SetFlattensRenderLayers", true)
	Call(addon, frame, "SetClampedToScreen", true)
	Call(addon, frame, "EnableMouse", true)
	CreateParchment(addon, frame)
	frame.headerLogo = Texture(addon, frame, nil, "ARTWORK", 26, 26)
	Call(addon, frame.headerLogo, "SetPoint", "TOPLEFT", 26, -11)
	Call(addon, frame.headerLogo, "SetTexture", LOGO)
	frame.title = Label(addon, frame, "GameFontNormalLarge")
	Call(addon, frame.title, "SetPoint", "LEFT", frame.headerLogo, "RIGHT", 10, 0)
	Call(addon, frame.title, "SetHeight", 30)
	Call(addon, frame.title, "SetJustifyV", "MIDDLE")
	Call(addon, frame.title, "SetWordWrap", false)
	frame.close = New(addon, "Button", frame)
	Call(addon, frame.close, "SetSize", 32, 32)
	Call(addon, frame.close, "SetPoint", "TOPRIGHT", -18, -8)
	for _, art in ipairs({
		{ "SetNormalTexture", "Up" },
		{ "SetPushedTexture", "Down" },
		{ "SetHighlightTexture", "Highlight" },
	}) do
		local texture = Texture(addon, frame.close, nil, "ARTWORK")
		Call(addon, texture, "SetAllPoints")
		Call(addon, texture, "SetTexture", "Interface\\Buttons\\UI-Panel-MinimizeButton-" .. art[2])
		if art[2] == "Highlight" then
			Call(addon, texture, "SetBlendMode", "ADD")
		end
		Call(addon, frame.close, art[1], texture)
	end
	-- Dismissal is safe on accessible, unprotected owned regions even when
	-- combat starts after presentation. Keep layout/native actions restricted.
	Call(addon, frame.close, "SetScript", "OnClick", function()
		if LibChev.CanMutateOwnedRegion(frame) and LibChev.CanMutateOwnedRegion(frame.close) then
			frame:Hide()
		end
	end)
	frame.settings = Button(addon, frame, frame, L("Settings"), function()
		if addon:OpenOptionsWindow() == true then
			Call(addon, frame, "Hide")
		end
	end)
	Call(addon, frame.settings, "SetSize", 130, 24)
	Call(addon, frame.settings, "SetPoint", "BOTTOMRIGHT", -40, 8)
	frame.discord = Button(addon, frame, frame, L("Join our Discord"), function()
		if addon:OpenDiscordSupport() then
			Call(addon, frame, "Hide")
		end
	end)
	local discordTextWidth = addon:SafeToNumber(Call(addon, frame.discord.label, "GetStringWidth")) or 128
	Call(addon, frame.discord, "SetSize", math.ceil(discordTextWidth) + 32, 24)
	Call(addon, frame.discord, "SetPoint", "BOTTOMLEFT", 30, 8)
	frame.navigation = {}
	for index, text in ipairs({ L("Oldest"), L("Older"), L("History"), L("Newer"), L("Latest") }) do
		local action = index
		frame.navigation[index] = Button(addon, frame, frame, text, function()
			local browser = rawget(addon, "releaseNotesBrowser")
			if not browser then
				return
			end
			if action == 1 then
				addon:ShowReleaseNotesPage(#browser.entries)
			elseif action == 2 then
				addon:ShowReleaseNotesPage(browser.index + 1)
			elseif action == 3 then
				addon:ShowReleaseNotesPage(browser.index, not browser.history)
			elseif action == 4 then
				addon:ShowReleaseNotesPage(browser.index - 1)
			else
				addon:ShowReleaseNotesPage(1)
			end
		end, index < 3 and "PrevPage" or index > 3 and "NextPage" or nil, index == 1 or index == 5)
	end
	frame.historyRows = {}
	frame.scroll = New(addon, "ScrollFrame", frame)
	Call(addon, frame.scroll, "SetPoint", "TOPLEFT", 30, -CONTENT_TOP)
	Call(addon, frame.scroll, "EnableMouseWheel", true)
	frame.content = New(addon, "Frame", frame.scroll)
	Call(addon, frame.scroll, "SetScrollChild", frame.content)
	frame.partnerExamples = CreatePartnerExamples(addon, frame.content)
	frame.slider = New(addon, "Slider", frame)
	Call(addon, frame.slider, "Hide")
	Call(addon, frame.slider, "SetPoint", "TOPLEFT", frame.scroll, "TOPRIGHT", 8, 0)
	Call(addon, frame.slider, "SetWidth", 14)
	Call(addon, frame.slider, "SetOrientation", "VERTICAL")
	Call(addon, frame.slider, "SetMinMaxValues", 0, 0)
	Call(addon, frame.slider, "SetValueStep", 1)
	Call(addon, frame.slider, "EnableMouseWheel", true)
	local track = Texture(addon, frame.slider, nil, "BACKGROUND")
	Call(addon, track, "SetAllPoints")
	Call(addon, track, "SetColorTexture", 0.12, 0.12, 0.12, 0.85)
	local thumb = Texture(addon, frame.slider, nil, "OVERLAY", 18, 30)
	Call(addon, thumb, "SetTexture", "Interface\\Buttons\\UI-ScrollBar-Knob")
	Call(addon, frame.slider, "SetThumbTexture", thumb)
	Script(addon, frame, frame.slider, "OnValueChanged", function(value)
		if not frame.syncScroll then
			SetScroll(addon, frame, value)
		end
	end)
	local function Wheel(delta)
		delta = addon:SafeToNumber(delta)
		if delta then
			SetScroll(addon, frame, (frame.scrollOffset or 0) - delta * 36)
		end
	end
	Script(addon, frame, frame.scroll, "OnMouseWheel", Wheel)
	Script(addon, frame, frame.slider, "OnMouseWheel", Wheel)
	Call(addon, frame, "SetMovable", true)
	Call(addon, frame, "SetResizable", true)
	frame.dragHandle = New(addon, "Frame", frame)
	Call(addon, frame.dragHandle, "SetPoint", "TOPLEFT", 18, 0)
	Call(addon, frame.dragHandle, "SetPoint", "TOPRIGHT", -54, 0)
	Call(addon, frame.dragHandle, "SetHeight", HEADER_HEIGHT)
	Call(addon, frame.dragHandle, "EnableMouse", true)
	Call(addon, frame.dragHandle, "RegisterForDrag", "LeftButton")
	Script(addon, frame, frame.dragHandle, "OnDragStart", function()
		Call(addon, frame, "StartMoving")
		frame.dragging = true
	end)
	frame.resizeGrip = New(addon, "Button", frame)
	Call(addon, frame.resizeGrip, "SetSize", 24, 24)
	Call(addon, frame.resizeGrip, "SetPoint", "BOTTOMRIGHT", -9, 6)
	for _, art in ipairs({
		{ "SetNormalTexture", "Up" },
		{ "SetPushedTexture", "Down" },
		{ "SetHighlightTexture", "Highlight" },
	}) do
		Call(addon, frame.resizeGrip, art[1], "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-" .. art[2])
	end
	Script(addon, frame, frame.resizeGrip, "OnMouseDown", function(button)
		if button == "LeftButton" then
			-- Arm before the native call: it can synchronously deliver OnSizeChanged.
			frame.userWidth = addon:SafeToNumber(Call(addon, frame, "GetWidth"))
			frame.userHeight = addon:SafeToNumber(Call(addon, frame, "GetHeight"))
			frame.resizing = true
			Call(addon, frame, "StartSizing", "BOTTOMRIGHT", true)
		end
	end)
	-- Stopping an owned drag remains safe if restrictions start mid-gesture.
	local function StopDrag()
		if LibChev.CanMutateOwnedRegion(frame) and (frame.dragging or frame.resizing) then
			frame:StopMovingOrSizing()
			frame.dragging, frame.resizing = nil, nil
		end
	end
	Call(addon, frame.dragHandle, "SetScript", "OnDragStop", StopDrag)
	Call(addon, frame.resizeGrip, "SetScript", "OnMouseUp", StopDrag)
	Call(addon, frame, "SetScript", "OnHide", StopDrag)
	Script(addon, frame, frame, "OnSizeChanged", function(width, height)
		if frame.resizing and not frame.rendering then
			width, height = addon:SafeToNumber(width), addon:SafeToNumber(height)
			if width and height and frame.notes then
				frame.userWidth, frame.userHeight = width, height
				addon:RenderReleaseNotesWindow(frame.notes, frame.version, frame.isFirstUse, true)
			end
		end
	end)
	frame.labels, frame.ready = {}, true
	return frame
end

local function ApplyTheme(addon, frame)
	local theme = addon:GetScrollWindowTheme()
	for _, piece in ipairs(frame.parchmentPieces) do
		Call(addon, piece, "SetVertexColor", unpack(theme.tint))
	end
	Call(addon, frame.title, "SetTextColor", unpack(theme.heading))
	for index, row in ipairs(frame.historyRows) do
		Call(addon, row.version, "SetTextColor", unpack(theme.heading))
		Call(addon, row.date, "SetTextColor", unpack(theme.muted))
		Call(addon, row.label, "SetTextColor", unpack(theme.body))
		local shade = theme.dark and 1 or 0
		Call(addon, row.background, "SetColorTexture", shade, shade, shade, index % 2 == 1 and 0.045 or 0.015)
		Call(
			addon,
			row.rule,
			"SetColorTexture",
			unpack(theme.dark and { 1, 0.85, 0.55, 0.18 } or { 0.3, 0.2, 0.1, 0.2 })
		)
	end
	for _, label in ipairs(frame.labels) do
		Call(addon, label, "SetTextColor", unpack(theme[label.themeRole or "body"]))
	end
	for _, label in ipairs(frame.partnerExamples.themeLabels) do
		Call(addon, label, "SetTextColor", unpack(theme[label.themeRole]))
	end
end

function QuestTogether:QueueReleaseNotesThemeRefresh()
	local frame = rawget(self, "releaseNotesWindow")
	if not frame or not frame.ready then
		return
	end
	self:ScheduleDeferredWork("foreign_frame_mutation", "release_notes_theme", function()
		if rawget(self, "releaseNotesWindow") == frame and Guard(self, frame) then
			-- Recolor existing regions only: do not change pages, scroll, visibility,
			-- or the version acknowledgement when the preference changes.
			pcall(ApplyTheme, self, frame)
		end
	end, 0, "release notes theme")
end

local function Render(addon, notes, version, isFirstUse, preserveScroll)
	if addon:IsRuntimeRestricted() or not addon:CanAccessTable(notes) then
		return false
	end
	local parent = addon:GetReleaseNotesUIParent()
	if not addon:CanAccessForeignFrame(parent) then
		return false
	end
	local parentWidth = ParentDimension(addon, parent, "GetWidth")
	local parentHeight = ParentDimension(addon, parent, "GetHeight")
	if not parentWidth or not parentHeight then
		return false
	end
	local frame = rawget(addon, "releaseNotesWindow")
	if frame and not Guard(addon, frame) then
		return false
	end
	if frame and not frame.ready then
		Call(addon, frame, "Hide")
		addon.releaseNotesWindow = nil
		frame = nil
	end
	frame = frame or Create(addon, parent)
	frame.rendering = true
	frame.notes, frame.version, frame.isFirstUse = notes, version, isFirstUse
	local oldScroll = preserveScroll and frame.scrollOffset or 0
	local scale = math.min(1, parentWidth * 0.92 / 520, parentHeight * 0.92 / 320)
	local maximumWidth = math.max(520, math.min(1100, parentWidth * 0.92 / scale))
	local maximumHeight = math.max(320, math.min(1000, parentHeight * 0.92 / scale))
	local width = math.max(520, math.min(frame.userWidth or 700, maximumWidth))
	Call(addon, frame, "SetResizeBounds", 520, 320, maximumWidth, maximumHeight)
	local contentWidth, offset, count = width - 76, 0, 0
	local browser = rawget(addon, "releaseNotesBrowser")
	local history = browser and browser.history
	local entry = browser and browser.entries[browser.index]
	local historyWidth = 160
	local navigationWidth = historyWidth + 4 * 32 + 4 * 6
	local navigationLeft = 30 + (contentWidth - navigationWidth) / 2
	local navigationX = { 0, 38, 76, 82 + historyWidth, 120 + historyWidth }
	for index, button in ipairs(frame.navigation) do
		local buttonWidth = index == 3 and historyWidth or 32
		Call(addon, button, "ClearAllPoints")
		Call(addon, button, "SetPoint", "TOPLEFT", navigationLeft + navigationX[index], -60)
		Call(addon, button, "SetSize", buttonWidth, 32)
		Call(addon, button.label, "SetWidth", buttonWidth - 8)
		local enabled = browser ~= nil
			and (
				index == 3
				or (index == 1 and (history or browser.index < #browser.entries))
				or (index == 5 and (history or browser.index > 1))
				or (
					not history
					and (index == 2 and browser.index < #browser.entries or index == 4 and browser.index > 1)
				)
			)
		Call(addon, button, "SetEnabled", enabled)
		-- A click can disable its own navigation button at a history boundary.
		-- Do not retain the previous press across that page/enable transition.
		Call(addon, button, "SetButtonState", "NORMAL", false)
		Call(addon, index ~= 3 and button or button.label, "SetAlpha", enabled and 1 or 0.4)
	end
	Call(addon, frame.navigation[3].label, "SetText", history and L("Back") or L("History"))
	for _, row in ipairs(frame.historyRows) do
		Call(addon, row, "Hide")
	end
	Call(addon, frame, "SetScale", scale)
	Call(addon, frame.title, "SetWidth", width - 134)
	Call(addon, frame.title, "SetText", "QuestTogether " .. addon:SafeTrimString(version, ""))
	local function Add(text, font, gap)
		text = addon:SafeTrimString(text, "")
		if text == "" then
			return
		end
		count = count + 1
		local label = frame.labels[count]
		if not label then
			label = Label(addon, frame.content, font)
			frame.labels[count] = label
		end
		Call(addon, label, "SetFontObject", font)
		label.themeRole = font:find("Normal", 1, true) and "heading" or "body"
		Call(addon, label, "ClearAllPoints")
		Call(addon, label, "SetPoint", "TOPLEFT", 0, -offset)
		Call(addon, label, "SetWidth", contentWidth)
		Call(addon, label, "SetText", text)
		Call(addon, label, "Show")
		local height = addon:SafeToNumber(Call(addon, label, "GetStringHeight"))
		if not height or height <= 0 then
			error("release notes text measurement unavailable", 0)
		end
		offset = offset + height + gap
	end
	Call(addon, frame.partnerExamples, "Hide")
	if history then
		offset = 0
		Call(addon, frame.title, "SetText", "QuestTogether — " .. L("Release history"))
		Add(L("Release history"), "GameFontNormalLarge", 12)
		Add(L("Choose a version to read its patch notes. Dates are in UTC."), "GameFontHighlight", 16)
		for index, item in ipairs(browser.entries) do
			local row = frame.historyRows[index]
			if not row then
				row = HistoryRow(addon, frame, index)
				frame.historyRows[index] = row
			end
			Call(addon, row.version, "SetWidth", contentWidth - 152)
			Call(addon, row.version, "SetText", item.version)
			Call(addon, row.date, "SetText", item.date or L("Date unavailable"))
			Call(addon, row.label, "SetWidth", contentWidth - 28)
			Call(addon, row.label, "SetText", addon:SafeTrimString(item.notes.sections[1].title, ""))
			local rowHeight = math.max(60, (addon:SafeToNumber(Call(addon, row.label, "GetStringHeight")) or 14) + 44)
			Call(addon, row, "ClearAllPoints")
			Call(addon, row, "SetPoint", "TOPLEFT", 0, -offset)
			Call(addon, row, "SetSize", contentWidth, rowHeight)
			Call(addon, row, "Show")
			offset = offset + rowHeight + 2
		end
	else
		Add(isFirstUse and L("Welcome to QuestTogether") or L("What's new"), "GameFontNormalLarge", 14)
		if entry and entry.date then
			Add(string.format(L("Release date (UTC): %s"), entry.date), "GameFontHighlightSmall", 12)
		end
		if entry and entry.englishOnly then
			Add(L("These notes are available in English only."), "GameFontHighlightSmall", 12)
		end
		Add(notes.welcome, "GameFontHighlight", 18)
		local examplesShown = false
		if addon:CanAccessTable(notes.sections) then
			for _, section in ipairs(notes.sections) do
				if addon:CanAccessTable(section) then
					Add(section.title, "GameFontNormal", 8)
					if addon:CanAccessTable(section.items) then
						for _, item in ipairs(section.items) do
							local text = addon:SafeTrimString(item, "")
							if text ~= "" then
								Add("• " .. text, "GameFontHighlight", 9)
							end
						end
					end
					if section.illustration == "quest-partners" and not examplesShown then
						local gallery = frame.partnerExamples
						Call(addon, gallery, "ClearAllPoints")
						Call(addon, gallery, "SetPoint", "TOPLEFT", 0, -offset)
						Call(addon, gallery, "SetSize", contentWidth, 112)
						for index, column in ipairs(gallery.columns) do
							Call(addon, column, "ClearAllPoints")
							Call(addon, column, "SetPoint", "TOPLEFT", (index - 1) * contentWidth / 2, 0)
							Call(addon, column, "SetSize", contentWidth / 2, 112)
						end
						Call(addon, gallery, "Show")
						offset, examplesShown = offset + 120, true
					end
					offset = offset + 10
				end
			end
		end
	end
	for index = count + 1, #frame.labels do
		Call(addon, frame.labels[index], "Hide")
	end
	local contentHeight = math.max(1, offset)
	local height = math.min(
		maximumHeight,
		math.max(320, frame.userHeight or math.min(650, contentHeight + CONTENT_TOP + CONTENT_BOTTOM))
	)
	local viewportHeight = height - CONTENT_TOP - CONTENT_BOTTOM
	Call(addon, frame, "SetSize", width, height)
	Call(addon, frame.scroll, "SetSize", contentWidth, viewportHeight)
	Call(addon, frame.content, "SetSize", contentWidth, math.max(contentHeight, viewportHeight))
	Call(addon, frame.slider, "SetHeight", viewportHeight)
	frame.maximumScroll = math.max(0, contentHeight - viewportHeight)
	Call(addon, frame.slider, "SetMinMaxValues", 0, frame.maximumScroll)
	Call(addon, frame.slider, frame.maximumScroll > 0 and "Show" or "Hide")
	SetScroll(addon, frame, oldScroll or 0)
	ApplyTheme(addon, frame)
	frame.rendering = nil
	Call(addon, frame, "Show")
	local visible = Call(addon, frame, "IsVisible")
	return addon:CanAccessValue(visible) and visible == true
end

function QuestTogether:RenderReleaseNotesWindow(notes, version, isFirstUse, preserveScroll)
	local ok, visible = pcall(Render, self, notes, version, isFirstUse, preserveScroll)
	if not ok then
		local frame = rawget(self, "releaseNotesWindow")
		if Guard(self, frame) then
			frame.rendering = nil
			pcall(Call, self, frame, "Hide")
		end
	end
	return ok and visible == true
end
