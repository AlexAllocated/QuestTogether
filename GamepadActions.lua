-- Owned choice descriptions and panels. Native navigation owns input; this
-- module only renders actions already supplied by QT features.
local QT = _G.QuestTogether
local L = QT.Translate
local MAX_PAGE_ROWS, MAX_DEPTH, MAX_ENTRIES = 18, 8, 256
local INSET, ROW_HEIGHT, TEXT_GUTTER, PROMPT_SPACE = 8, 24, 26, 48
local Description = {}
Description.__index = Description
local function Add(parent, kind, text, action, selected, data)
    local root = parent.root or parent
    if root.count >= MAX_ENTRIES then error("gamepad action capacity", 0) end
    root.count = root.count + 1
    local entry = setmetatable({ root = root, children = {}, kind = kind,
        text = tostring(text or ""), action = action, selected = selected, data = data, enabled = true,
        qtOwnedActionPanel = true }, Description)
    parent.children[#parent.children + 1] = entry
    return entry
end
function Description:CreateButton(text, action, data) return Add(self, "button", text, action, nil, data) end
function Description:CreateTitle(text) return Add(self, "title", text) end
function Description:CreateDivider() return Add(self, "divider", "") end
function Description:CreateSpacer() return self:CreateDivider() end
function Description:CreateCheckbox(text, selected, action, data) return Add(self, "check", text, action, selected, data) end
function Description:CreateRadio(text, selected, action, data) return Add(self, "radio", text, action, selected, data) end
function Description:CreateHighlightRadio(text, selected, action, data) return Add(self, "highlightRadio", text, action, selected, data) end
function Description:SetEnabled(value) self.enabled = value == true end
function Description:SetTooltip(callback) self.tooltip = callback end
function Description:SetMinimumWidth(width)
    if type(width) == "number" and width == width then self.minimumWidth = math.max(0, math.min(400, width)) end
end
function QT:BuildGamepadActionDescription(owner, generator)
    local root = setmetatable({ children = {}, count = 0, qtOwnedActionPanel = true }, Description)
    generator(owner, root)
    return root
end
local function Current(addon, state)
    local status = addon:GetGamepadIntegrationStatus()
    local valid = rawget(addon, "gamepadActions") == state and state.profile == (addon.db and addon.db.profile)
        and not addon.isLoggingOut and not addon:IsWorkBlocked("foreign_frame_mutation")
        and addon:IsNativeGamepadMode() and status and not status.failed
        and (not state.native or (status.available and status.enabled))
    if not valid then return false end
    if state.current then local ok, current = pcall(state.current); return ok and current == true end
    return true
end
function QT:IsGamepadActionPanelOpen()
    return rawget(self, "gamepadActions") ~= nil
end
function QT:CloseGamepadActions()
    local state = rawget(self, "gamepadActions")
    self.gamepadActions = nil
    if not state then return end
    if state.dropdownOwner then state.dropdownOwner:SetOwnedMenuOpen(false) end
    for i = #state.frames, 1, -1 do self:DismissManagedWindow(state.frames[i], "action_close") end
end
local function Back(addon, state, frame)
    if rawget(addon, "gamepadActions") ~= state then return end
    if state.frames[#state.frames] ~= frame then return end
    if #state.frames == 1 then addon:CloseGamepadActions(); return end
    table.remove(state.frames)
    frame.actionSession = nil
    addon:DismissManagedWindow(frame, "action_back")
end

-- Only the artwork resembles Blizzard's menus. Plain owned buttons avoid the
-- native menu compositor/focus path that failed the live safety gate.
local function MenuButton(addon, frame)
    local button = addon:CreateOwnedWindowFrame("Button", nil, frame)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetJustifyH("LEFT"); button.label:SetWordWrap(true)
    button:SetFontString(button.label)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(); highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetAlpha(0.65); button:SetHighlightTexture(highlight, "ADD")
    button.highlight = highlight
    button.checkBase = button:CreateTexture(nil, "ARTWORK")
    button.checkBase:SetSize(16, 16); button.checkBase:SetPoint("LEFT", 4, 0)
    button.checkMark = button:CreateTexture(nil, "OVERLAY")
    button.checkMark:SetSize(16, 16); button.checkMark:SetPoint("CENTER", button.checkBase, "CENTER")
    button.arrow = button:CreateTexture(nil, "ARTWORK")
    button.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    button.arrow:SetSize(16, 16); button.arrow:SetPoint("RIGHT", -4, 0)
    button.checkBase:Hide(); button.checkMark:Hide(); button.arrow:Hide()
    return button
end

local function CreateMenu(addon)
    local parent = addon:GetOwnedUIParent()
    if not addon:CanAccessForeignFrame(parent) then return end
    local frame = addon:CreateOwnedWindowFrame("Frame", nil, parent)
    if not addon:CanMutateOwnedUI(frame) then return end
    frame:Hide(); frame:SetSize(260, 100); frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true); frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    -- The native Select/Back legend is below the window and owns its own layout.
    frame:SetClampRectInsets(-17, 17, 12, -PROMPT_SPACE)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", INSET + TEXT_GUTTER, -INSET)
    frame.title:SetJustifyH("LEFT"); frame.title:SetWordWrap(true)
    frame.measure = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.measure:Hide(); frame.measure:SetWordWrap(true)
    frame.divider = frame:CreateTexture(nil, "ARTWORK")
    frame.divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    frame.actionButtons, frame.actionLines = {}, {}
    addon:RegisterManagedWindow(frame, nil, nil, nil, nil, function()
        if frame.LayoutActionMenu then return frame.LayoutActionMenu() end
        return false
    end)
    return frame
end

local function LayoutMenu(addon, frame, node)
    local measure, width = frame.measure, math.max(220, node.minimumWidth or 0)
    local function Measure(text)
        measure:SetWidth(0); measure:SetText(text)
        return measure:GetStringWidth()
    end
    width = math.max(width, Measure(node.text) + 2 * (INSET + TEXT_GUTTER))
    for _, text in ipairs({L("Previous"), L("Next"), L("Back")}) do
        width = math.max(width, 3 * (Measure(text) + 12) + 2 * INSET)
    end
    for _, entry in ipairs(node.children) do
        width = math.max(width, entry.minimumWidth or 0, Measure(entry.text) + 2 * (INSET + TEXT_GUTTER))
    end
    width = math.min(400, math.ceil(width))
    local textWidth = width - 2 * (INSET + TEXT_GUTTER)
    local footerHeight = ROW_HEIGHT
    measure:SetWidth((width - 2 * INSET) / 3 - 4)
    for _, text in ipairs({L("Previous"), L("Next"), L("Back")}) do
        measure:SetText(text); footerHeight = math.max(footerHeight, measure:GetStringHeight() + 8)
    end
    frame.title:SetWidth(textWidth); frame.title:SetText(node.text)
    frame.title:SetShown(node.text ~= "")
    local top = node.text == "" and INSET or INSET + frame.title:GetStringHeight() + 10
    local parent = addon:GetOwnedUIParent()
    local heightGetter = addon:GetAccessibleFrameMember(parent, "GetHeight")
    local ok, height = pcall(function() return heightGetter(parent) end)
    height = ok and addon:SafeToNumber(height) or nil
    local budget = math.max(100, math.min(480, (height or 600) * 0.90 / addon:GetWindowScale() - top - footerHeight - 16 - PROMPT_SPACE))
    local pages, rows, used = {}, {}, 0
    for _, entry in ipairs(node.children) do
        measure:SetWidth(textWidth); measure:SetText(entry.text)
        local rowHeight = entry.kind == "divider" and 8 or math.max(ROW_HEIGHT, measure:GetStringHeight() + 8)
        if #rows > 0 and (used + rowHeight > budget or #rows >= MAX_PAGE_ROWS) then
            pages[#pages + 1], rows, used = rows, {}, 0
        end
        rows[#rows + 1] = {entry = entry, height = rowHeight}
        used = used + rowHeight
    end
    if #rows > 0 then pages[#pages + 1] = rows end
    frame.actionPages, frame.menuWidth, frame.menuTop, frame.menuFooterHeight = pages, width, top, footerHeight
end

local function FitMenu(addon, frame, parent, below)
    local root = addon:GetOwnedUIParent()
    if not addon:CanAccessForeignFrame(root) then return false end
    local ok, w, h = pcall(function() return root:GetWidth(), root:GetHeight() end)
    w, h = ok and addon:SafeToNumber(w) or nil, ok and addon:SafeToNumber(h) or nil
    if not w or not h or w <= 0 or h <= 0 then return false end
    frame:SetSize(frame.menuWidth, frame.menuHeight)
    frame:SetScale(math.min(addon:GetWindowScale(), w * 0.94 / frame.menuWidth, h * 0.94 / (frame.menuHeight + PROMPT_SPACE)))
    frame:ClearAllPoints(); frame:SetPoint("CENTER")
    if parent and addon:CanAccessForeignFrame(parent, true) then
        frame:ClearAllPoints()
        if below then frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -5)
        else frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0) end
    end
    return true
end

local function ShowPage(addon, state, node, parent, page)
    if not Current(addon, state) or #state.frames >= MAX_DEPTH then return false end
    local index = #state.frames + 1
    addon.gamepadActionFrames = rawget(addon, "gamepadActionFrames") or {}
    local frame = addon.gamepadActionFrames[index]
    if frame and frame:IsShown() then return false end -- deferred retirement still owns it
    if not frame then
        frame = CreateMenu(addon)
        if not frame then return false end
        addon.gamepadActionFrames[index] = frame
    end
    addon:ApplyOwnedMenuArtwork(frame, state.menuStyle, state.menuClassic)
    LayoutMenu(addon, frame, node)
    state.frames[index] = frame
    local session = {}
    frame.actionSession = session
    local buttons, lines = frame.actionButtons, frame.actionLines
    local function Active(generation)
        return Current(addon, state) and state.frames[index] == frame and state.frames[#state.frames] == frame
            and frame.actionSession == session and (not generation or frame.actionGeneration == generation)
            and frame:IsVisible()
            and (not addon:IsGamepadWindowRegistered(frame) or addon:IsGamepadActionCurrent(frame))
    end
    local function Select(entry, generation)
        if not Active(generation) or not entry.enabled then return end
        if #entry.children > 0 then ShowPage(addon, state, entry, frame, 1); return end
        local callback, data = entry.action, entry.data
        addon:CloseGamepadActions()
        -- A failed or deferred native detach cannot execute a later manual action.
        for _, oldFrame in ipairs(state.frames) do if oldFrame:IsShown() then return end end
        local status = addon:GetGamepadIntegrationStatus()
        if callback and status and not status.failed and (not state.native or (status.available and status.enabled))
            and state.profile == (addon.db and addon.db.profile) and not addon.isLoggingOut
            and addon:IsNativeGamepadMode() and not addon:IsWorkBlocked("foreign_frame_mutation") then callback(data) end
    end
    local function Render(number)
        if not Current(addon, state) or frame.actionSession ~= session or state.frames[index] ~= frame then return false end
        for _, button in ipairs(buttons) do
            if state.native and not addon:PrepareGamepadControlHide(button, frame.back) then return false end
        end
        for _, button in ipairs({frame.previous, frame.next}) do
            if state.native and not addon:PrepareGamepadControlHide(button, frame.back) then return false end
        end
        frame.actionGeneration = (frame.actionGeneration or 0) + 1
        local generation = frame.actionGeneration
        frame.page = number
        for _, button in ipairs(buttons) do button:Hide() end
        for _, label in ipairs(lines) do label:Hide() end
        local y, count, labels = -frame.menuTop, 0, 0
        local contentWidth = frame.menuWidth - 2 * INSET
        for _, row in ipairs(frame.actionPages[number]) do
            local entry = row.entry
            if entry.kind == "title" or entry.kind == "divider" then
                labels = labels + 1
                local label = lines[labels]
                if not label then
                    label = addon:CreateOwnedWindowFrame("Frame", nil, frame)
                    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    label.text:SetPoint("LEFT", TEXT_GUTTER, 0); label.text:SetJustifyH("LEFT"); label.text:SetWordWrap(true)
                    label.line = label:CreateTexture(nil, "ARTWORK")
                    label.line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
                    label.line:SetPoint("LEFT", 4, 0); label.line:SetPoint("RIGHT", -4, 0); label.line:SetHeight(8)
                    lines[labels] = label
                end
                label:ClearAllPoints(); label:SetPoint("TOPLEFT", INSET, y); label:SetSize(contentWidth, row.height)
                label.text:SetWidth(contentWidth - 2 * TEXT_GUTTER); label.text:SetText(entry.text)
                label.text:SetShown(entry.kind == "title"); label.line:SetShown(entry.kind == "divider"); label:Show()
            else
                count = count + 1
                local button = buttons[count]
                if not button then button = MenuButton(addon, frame); buttons[count] = button end
                button:ClearAllPoints(); button:SetPoint("TOPLEFT", INSET, y); button:SetSize(contentWidth, row.height)
                button.label:ClearAllPoints(); button.label:SetPoint("LEFT", TEXT_GUTTER, 0)
                button.label:SetWidth(contentWidth - 2 * TEXT_GUTTER)
                local selected = type(entry.selected) == "function" and entry.selected(entry.data) or entry.selected == true
                button:SetText(entry.text)
                local check = entry.kind == "check" or entry.kind == "radio"
                if check then
                    button.checkBase:SetAtlas(entry.kind == "radio" and "common-dropdown-tickradial" or "common-dropdown-ticksquare", true)
                    button.checkMark:SetAtlas(entry.kind == "radio" and "common-dropdown-icon-radialtick-yellow" or "common-dropdown-icon-checkmark-yellow", true)
                    button.checkMark:ClearAllPoints()
                    if entry.kind == "radio" then button.checkMark:SetPoint("TOPLEFT", button.checkBase, "TOPLEFT")
                    else button.checkMark:SetPoint("CENTER", button.checkBase, "CENTER", 2, 1) end
                end
                button.checkBase:SetShown(check); button.checkMark:SetShown(check and selected == true)
                button.arrow:SetShown(#entry.children > 0)
                local highlighted = entry.kind == "highlightRadio"
                if highlighted then button.highlight:SetAtlas("common-dropdown-customize-mouseover"); button.highlight:SetAlpha(0.15); button.highlight:SetBlendMode("BLEND")
                else button.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); button.highlight:SetAlpha(0.65); button.highlight:SetBlendMode("ADD") end
                local function TextColor(over)
                    if not entry.enabled then button.label:SetTextColor(0.5, 0.5, 0.5)
                    elseif highlighted and not selected then
                        local gray = over and 1 or 0.9; button.label:SetTextColor(gray, gray, gray)
                    else button.label:SetTextColor(1, 0.82, 0) end
                end
                TextColor(false)
                button:SetEnabled(entry.enabled); button:Show()
                button:SetScript("OnClick", function() Select(entry, generation) end)
                button:SetScript("OnEnter", function()
                    if not Active(generation) then return end
                    TextColor(true)
                    if not entry.tooltip or not addon:CanAccessForeignFrame(GameTooltip) then return end
                    GameTooltip:SetOwner(button, "ANCHOR_RIGHT"); entry.tooltip(GameTooltip); GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function()
                    if Active(generation) then TextColor(false) end
                    if addon:CanAccessForeignFrame(GameTooltip) and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
                end)
            end
            y = y - row.height
        end
        local paged = #frame.actionPages > 1
        frame.previous:SetShown(paged); frame.next:SetShown(paged)
        frame.previous:SetEnabled(number > 1); frame.next:SetEnabled(number < #frame.actionPages)
        frame.previous.label:SetTextColor(number > 1 and 1 or 0.5, number > 1 and 0.82 or 0.5, number > 1 and 0 or 0.5)
        frame.next.label:SetTextColor(number < #frame.actionPages and 1 or 0.5, number < #frame.actionPages and 0.82 or 0.5, number < #frame.actionPages and 0 or 0.5)
        frame.previous:SetScript("OnClick", function()
            if Active(generation) and frame.page > 1 then Render(frame.page - 1) end
        end)
        frame.next:SetScript("OnClick", function()
            if Active(generation) and frame.page < #frame.actionPages then Render(frame.page + 1) end
        end)
        frame.back:SetScript("OnClick", function() if Active(generation) then Back(addon, state, frame) end end)
        frame.divider:ClearAllPoints(); frame.divider:SetPoint("TOPLEFT", INSET + 4, y - 2)
        frame.divider:SetSize(contentWidth - 8, 8)
        frame.menuHeight = -y + frame.menuFooterHeight + INSET + 8
        if not FitMenu(addon, frame, parent, index == 1 and state.dropdownOwner ~= nil) then return false end
        if state.native then addon:RefreshGamepadNavigation(frame, frame.back) end
        return true
    end
    local function Footer(key, text, column)
        local b = frame[key] or MenuButton(addon, frame)
        local width = (frame.menuWidth - 2 * INSET) / 3
        b:ClearAllPoints(); b:SetSize(width, frame.menuFooterHeight); b:SetPoint("BOTTOMLEFT", INSET + column * width, INSET)
        b.label:ClearAllPoints(); b.label:SetPoint("CENTER"); b.label:SetWidth(width - 4); b.label:SetJustifyH("CENTER")
        b:SetText(text)
        return b
    end
    frame.previous = Footer("previous", L("Previous"), 0)
    frame.next = Footer("next", L("Next"), 1)
    frame.back = Footer("back", L("Back"), 2)
    addon:ConfigureWindowController(frame, { gamepad = state.native and { role = "actions", kind = "popup", footer = true,
        defaultFocus = function() return frame.back end,
        close = function() if frame.actionSession == session then Back(addon, state, frame) end end } or nil,
        dismiss = function(reason)
            if reason ~= "action_back" and reason ~= "action_close" and rawget(addon, "gamepadActions") == state then addon:CloseGamepadActions() end
        end })
    frame.escapeAction = function() if frame.actionSession == session then Back(addon, state, frame) end end
    frame.LayoutActionMenu = function()
        if not Current(addon, state) or frame.actionSession ~= session or not frame.menuHeight then return false end
        return FitMenu(addon, frame, parent, index == 1 and state.dropdownOwner ~= nil)
    end
    if not Render(page or 1) then
        frame.actionSession = nil; state.frames[index] = nil
        if index == 1 then addon.gamepadActions = nil end
        return false
    end
    frame:Show(); frame:Raise()
    if state.native and addon:PresentGamepadWindow(frame, {userInitiated = true, parent = index > 1 and parent or nil}) ~= true then
        addon:CloseGamepadActions(); return false
    end
    return true
end
function QT:ShowGamepadContextMenu(owner, generator, current, presentation)
    if not self:IsNativeGamepadMode() or self:IsWorkBlocked("foreign_frame_mutation") then return false end
    local status = self:GetGamepadIntegrationStatus()
    if not status or status.failed then return false end
    self:CloseGamepadActions()
    local ok, root = pcall(self.BuildGamepadActionDescription, self, owner, generator)
    if not ok then self:Debug("Action description unavailable", "GAMEPAD"); return false end
    if #root.children == 0 then return false end
    local dropdown = presentation and presentation.kind == "dropdown" and self:CanMutateOwnedUI(owner)
    root.text = dropdown and "" or "QuestTogether"
    local state = { frames = {}, profile = self.db and self.db.profile, current = current,
        dropdownOwner = dropdown and owner or nil,
        menuStyle = presentation and presentation.style or "standard",
        menuClassic = presentation and presentation.classic == true or not presentation and self:UsesClassicMenuArtwork(),
        native = status.enabled and status.available or false }
    self.gamepadActions = state
    local shown = ShowPage(self, state, root, owner, 1)
    if not shown then self:CloseGamepadActions() end
    if dropdown then owner:SetOwnedMenuOpen(shown == true) end
    return shown
end

-- Selection changes are frequent; settings only need an observer refresh when
-- the integration mode itself changes. Explicit value/show updates still refresh.
local function ObserveMode(addon, callback)
    local mode, available, enabled, failed
    local function Remember()
        local status = addon:GetGamepadIntegrationStatus()
        local nextMode = addon:IsNativeGamepadMode()
        local nextAvailable = status and status.available or false
        local nextEnabled = status and status.enabled or false
        local nextFailed = status and status.failed or false
        local changed = mode ~= nextMode or available ~= nextAvailable or enabled ~= nextEnabled or failed ~= nextFailed
        mode, available, enabled, failed = nextMode, nextAvailable, nextEnabled, nextFailed
        return changed
    end
    Remember()
    return function() if Remember() then callback() end end
end

-- A sibling owned button replaces the intrinsic dropdown receiver. Its native
-- menu is generated only in mouse mode; inherited parent shows never claim focus.
function QT:ConfigureGamepadDropdown(dropdown, generator, label, style)
    if not dropdown or not self:CanMutateOwnedUI(dropdown) then return end
    local status = self:GetGamepadIntegrationStatus()
    if not dropdown.qtGamepadChoice and not (status and status.available) and not self:IsNativeGamepadMode() then
        dropdown:SetupMenu(generator)
        return
    end
    local choice = dropdown.qtGamepadChoice
    if choice then
        if choice.generator ~= generator then choice.generator = generator; choice.nativeGenerator = nil end
        if label ~= nil then choice.text = label end
        choice.refresh()
        return choice
    end
    local background = self:GetAccessibleFrameMember(dropdown, "Background")
    local classic = self:UsesClassicMenuArtwork()
    if background and self:CanAccessForeignFrame(background) then
        local ok, atlas = pcall(function() return background:GetAtlas() end)
        if ok and self:CanAccessValue(atlas) and type(atlas) == "string" and style ~= "settings" then
            classic = atlas:find("-classic-", 1, true) ~= nil
        end
    end
    choice = self:CreateOwnedDropdownButton(dropdown:GetParent(), style, classic)
    if not choice then return end
    choice:SetAllPoints(dropdown); choice:Hide(); dropdown.qtGamepadChoice = choice
    choice.generator, choice.text = generator, label or ""
    choice.wantedShown = dropdown:IsShown()
    local show, hide, enabled, defaultText = dropdown.Show, dropdown.Hide, dropdown.SetEnabled, dropdown.SetDefaultText
    local function Refresh()
        if choice.refreshing or self:IsWorkBlocked("foreign_frame_mutation")
            or not self:CanMutateOwnedUI(dropdown) or not self:CanMutateOwnedUI(choice) then return end
        choice.refreshing = true
        if self:IsNativeGamepadMode() then
            local current = self:GetGamepadIntegrationStatus()
            -- Unsupported native Settings can own this receiver independently.
            -- Keep it in place if safe retirement cannot be proven; the owned
            -- mouse choice overlays it without mutating native navigation.
            if dropdown:IsShown() and self:PrepareGamepadControlHide(dropdown) then hide(dropdown) end
            if not choice.wantedShown and not self:PrepareGamepadControlHide(choice) then choice.refreshing = nil; return end
            choice:SetText(choice.text)
            choice:SetEnabled(dropdown:IsEnabled() and current and not current.failed or false)
            choice:RefreshVisualState()
            if choice.wantedShown then choice:Show() else choice:Hide() end
        else
            if not self:PrepareGamepadControlHide(choice) then choice.refreshing = nil; return end
            choice:Hide()
            if choice.wantedShown then show(dropdown) else hide(dropdown) end
            if choice.nativeGenerator ~= choice.generator then
                dropdown:SetupMenu(choice.generator)
                choice.nativeGenerator = choice.generator
            end
        end
        local state = rawget(self, "gamepadActions")
        if state and state.dropdownOwner == choice and (not choice:IsVisible() or not choice:IsEnabled()) then
            self:CloseGamepadActions()
        end
        choice.refreshing = nil
    end
    choice.refresh = Refresh
    dropdown.Show = function(control) choice.wantedShown = true; Refresh() end
    dropdown.Hide = function(control) choice.wantedShown = false; Refresh() end
    dropdown.SetShown = function(control, shown) choice.wantedShown = shown == true; Refresh() end
    dropdown.SetEnabled = function(control, value) enabled(control, value); Refresh() end
    dropdown.SetDefaultText = function(control, value)
        choice.text = value; defaultText(control, value); choice:SetText(value)
    end
    choice:SetScript("OnClick", function()
        local wantedGenerator = choice.generator
        local function CurrentChoice()
            return self:CanMutateOwnedUI(choice) and choice:IsVisible() and choice:IsEnabled()
                and choice.generator == wantedGenerator and choice.wantedShown
        end
        if CurrentChoice() then
            local state = rawget(self, "gamepadActions")
            if state and state.dropdownOwner == choice then self:CloseGamepadActions(); return end
            self:ShowGamepadContextMenu(choice, wantedGenerator, CurrentChoice,
                {kind = "dropdown", style = choice.dropdownStyle, classic = choice.dropdownClassic})
        end
    end)
    choice:HookScript("OnHide", function()
        local state = rawget(self, "gamepadActions")
        if state and state.dropdownOwner == choice then self:CloseGamepadActions() end
        self:HideSettingsTooltip(choice)
    end)
    choice:HookScript("OnEnter", function()
        if not self:IsWorkBlocked("foreign_frame_mutation") and self:CanMutateOwnedUI(choice)
            and choice.Text:IsTruncated() then self:ShowSettingsTooltip(choice, choice:GetText(), "") end
    end)
    choice:HookScript("OnLeave", function() self:HideSettingsTooltip(choice) end)
    dropdown:GetParent():HookScript("OnShow", Refresh)
    self:RegisterGamepadObserver(choice, ObserveMode(self, Refresh))
    Refresh()
    return choice
end

-- Settings steppers normally read the native menu's generated radio records.
-- In controller mode those records are deliberately absent (or stale from mouse
-- mode), so resolve the current owned options afresh for every arrow action.
function QT:ConfigureGamepadDropdownSteppers(control, getEntries)
    if control.qtGamepadSteppers then return end
    control.qtGamepadSteppers = true
    local nativeIncrement, nativeDecrement, nativeUpdate = control.Increment, control.Decrement, control.UpdateSteppers
    local function Selection()
        local entries = getEntries()
        for index, entry in ipairs(entries) do
            local selected = entry.checked
            if type(selected) == "function" then
                local ok, value = pcall(selected)
                selected = ok and value == true
            end
            if selected == true then return entries, index end
        end
        return entries
    end
    local function Update(frame)
        if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanMutateOwnedUI(frame) then return end
        if not self:IsNativeGamepadMode() then if nativeUpdate then nativeUpdate(frame) end; return end
        local entries, index = Selection()
        local status = self:GetGamepadIntegrationStatus()
        local available = status and not status.failed and frame.Dropdown:IsEnabled()
        frame.DecrementButton:SetEnabled(available and index ~= nil and index > 1 or false)
        frame.IncrementButton:SetEnabled(available and index ~= nil and index < #entries or false)
        if status and status.available and status.enabled and not status.failed then self:MarkGamepadContainer(frame) end
    end
    local function Step(frame, delta, original, ...)
        if not self:IsNativeGamepadMode() then if original then return original(frame, ...) end; return end
        local status = self:GetGamepadIntegrationStatus()
        if self:IsWorkBlocked("foreign_frame_mutation") or not self:CanMutateOwnedUI(frame) or not frame:IsVisible()
            or not frame.Dropdown:IsEnabled() or not status or status.failed then return end
        local entries, index = Selection()
        local entry = index and entries[index + delta]
        if entry and type(entry.func) == "function" then entry.func() end
        Update(frame)
    end
    control.Increment = function(frame, ...) return Step(frame, 1, nativeIncrement, ...) end
    control.Decrement = function(frame, ...) return Step(frame, -1, nativeDecrement, ...) end
    control.UpdateSteppers = Update
    -- These scripts belong to QT's control instance. Cover mouse presses too,
    -- while keeping the original behavior intact outside native controller mode.
    for _, pair in ipairs({ { control.IncrementButton, "Increment" }, { control.DecrementButton, "Decrement" } }) do
        local button, method = pair[1], pair[2]
        local click = button:GetScript("OnClick")
        button:SetScript("OnClick", function(...)
            if self:IsNativeGamepadMode() then return control[method](control) end
            if click then return click(...) end
        end)
    end
    control:HookScript("OnShow", function() Update(control) end)
    self:RegisterGamepadObserver(control, ObserveMode(self, function() Update(control) end))
    Update(control)
end
