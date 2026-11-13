-- Owned frame/store fixtures only. Never call or replace native controller APIs.
local QT = _G.QuestTogether
local function Fixture()
    local a = setmetatable({ db = {profile = {}}, isEnabled = true, runtimeStateStore = {} }, {__index = QT})
    a.API = {GetTime = function() return 100 end}
    a.parent = QT:CreateTestUIRegion(a)
    a.parent:SetSize(1280, 900)
    function a:GetOwnedUIParent() return self.parent end
    function a:CreateOwnedWindowFrame(kind, _, parent, template)
        local frame = self:ApplyTestUITemplate(self:CreateTestUIRegion(self, parent, kind), template)
        function frame:IsEnabled() return self.enabled ~= false end
        return frame
    end
    function a:CreateOwnedUICleanupFrame() return self:CreateTestUIRegion({}) end
    function a:GetOption(key) return key == "windowScale" and 100 or false end
    function a:IsRuntimeRestricted() return self.blocked == true end
    function a:IsWorkBlocked() return self.blocked == true end
    function a:IsNativeGamepadMode() return self.mode ~= false end
    function a:UsesClassicMenuArtwork() return false end
    function a:ConfigureGamepadWindow(frame, policy) frame.testPolicy = policy end
    function a:PresentGamepadWindow(frame) self.selected = frame; return true end
    function a:RefreshGamepadNavigation() self.navigationRefreshes = (self.navigationRefreshes or 0) + 1 end
    function a:IsGamepadWindowRegistered(frame) return self.selected == frame and frame:IsVisible() end
    function a:IsGamepadActionCurrent(frame) return self.selected == frame and frame:IsVisible() end
    function a:GetGamepadIntegrationStatus() return {failed = self.failed == true, enabled = self.disabled ~= true, available = self.unsupported ~= true} end
    function a:MarkGamepadContainer(frame) frame.testContainer = true; return true end
    function a:PrepareGamepadControlHide(control, fallback)
        self.hideGuards = (self.hideGuards or 0) + 1
        self.hideControls = self.hideControls or {}
        self.hideControls[control] = fallback
        return not self.cannotPark and control ~= self.cannotParkControl
    end
    function a:RegisterGamepadObserver(owner, callback)
        self.observers = self.observers or {}; self.observers[owner] = callback
    end
    function a:Debug(_, text) error(text) end
    return a
end
QT:RegisterTest("gamepad choices retain subjects and bound frame allocation across menus", function()
    local a, count = Fixture(), 0
    for iteration = 1, 30 do
        assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
            local submenu = root:CreateButton("Nested")
            submenu:CreateButton("Act", function() count = count + 1 end)
        end))
        local first = a.gamepadActions.frames[1]
        first.actionButtons[1]:GetScript("OnClick")()
        local second = a.gamepadActions.frames[2]
        second.actionButtons[1]:GetScript("OnClick")()
        assert(not a.gamepadActions and not first:IsShown() and not second:IsShown())
    end
    assert(count == 30 and #a.gamepadActionFrames == 2, "action panels leaked frames or repeated a callback")
end)
QT:RegisterTest("gamepad action callbacks cannot survive dismissal or a profile switch", function()
    local a, count = Fixture(), 0
    local function Build(_, root) root:CreateButton("Act", function() count = count + 1 end) end
    assert(a:ShowGamepadContextMenu(a.parent, Build))
    local oldClick = a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")
    a:CloseGamepadActions()
    assert(a:ShowGamepadContextMenu(a.parent, Build))
    oldClick()
    assert(count == 0, "pooled button redirected stale action")
    a.db.profile = {}
    a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")()
    assert(count == 0)
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad action page generations retire callbacks and default to harmless Back", function()
    local a, selected = Fixture(), {}
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        for index=1,80 do
            local id = index
            root:CreateButton("Act " .. index, function() selected[#selected+1] = id end, id)
        end
    end))
    local frame = a.gamepadActions.frames[1]
    assert(frame.testPolicy.defaultFocus() == frame.back)
    assert(#frame.actionPages > 3 and frame.previous:IsShown() and frame.next:IsShown())
    for _, page in ipairs(frame.actionPages) do
        assert(#page > 0 and #page <= 18, "action page exceeded its bounded visible entries")
    end
    local oldClick = frame.actionButtons[1]:GetScript("OnClick")
    local oldNext = frame.next:GetScript("OnClick")
    oldNext()
    assert(frame.page == 2)
    oldClick(); oldNext()
    assert(#selected == 0 and frame.page == 2)
    frame.next:GetScript("OnClick")()
    assert(frame.page == 3 and #frame.actionButtons <= 18)
    local expected = frame.actionPages[3][1].entry.data
    oldClick()
    frame.actionButtons[1]:GetScript("OnClick")()
    assert(#selected == 1 and selected[1] == expected and not a.gamepadActions)
end)
QT:RegisterTest("gamepad compact menus size to content and omit unnecessary paging", function()
    local a = Fixture()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        root:CreateTitle("Choices")
        root:CreateButton("One")
        root:CreateDivider()
        root:CreateButton("Two")
    end))
    local frame = a.gamepadActions.frames[1]
    assert(#frame.actionPages == 1 and frame.page == 1)
    assert(not frame.previous:IsShown() and not frame.next:IsShown(), "short menu kept inactive pagination")
    assert(frame.back:IsVisible() and frame.back:IsEnabled() and frame.testPolicy.defaultFocus() == frame.back)
    assert(frame:GetWidth() > 0 and frame:GetWidth() <= 420)
    assert(frame:GetHeight() > 0 and frame:GetHeight() < 250, "short menu retained full dialog height")
    assert(#frame.actionButtons == 2, "section headings or dividers became focusable buttons")
    for _, row in ipairs(frame.actionButtons) do
        assert(row.template ~= "UIPanelButtonTemplate", "compact menu retained large dialog-button styling")
        assert(row:GetFontString() == row.label and row.label:GetText() == row:GetText())
        assert(row:GetWidth() > 0 and row:GetWidth() < frame:GetWidth() and row:GetHeight() > 0)
    end
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad compact menu footer labels fit the current client language", function()
    local a = Fixture()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        for index=1,80 do root:CreateButton("Choice " .. index) end
    end))
    local frame = a.gamepadActions.frames[1]
    for key, text in pairs({previous = "Previous", next = "Next", back = "Back"}) do
        local button = frame[key]
        assert(button:IsVisible() and button.label:GetText() == QT.Translate(text))
        assert(button:GetHeight() >= button.label:GetStringHeight(), "localized footer label escaped its row")
    end
    assert(frame:GetWidth() <= 420)
    a:CloseGamepadActions()
end, {locale = "client"})
QT:RegisterTest("gamepad compact menu wraps long labels and recomputes pooled geometry", function()
    local a = Fixture()
    local longLabel = string.rep("A lengthy option label ", 8)
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        root:CreateCheckbox(longLabel, true)
    end))
    local frame = a.gamepadActions.frames[1]
    local row = frame.actionButtons[1]
    local tallHeight, wideWidth = frame:GetHeight(), frame:GetWidth()
    assert(wideWidth <= 420 and tallHeight < a.parent:GetHeight())
    assert(row.label:GetText() == longLabel and row.label:GetStringHeight() > 14)
    assert(row:GetHeight() >= row.label:GetStringHeight(), "wrapped label escaped its clickable row")
    a:CloseGamepadActions()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton("Short") end))
    assert(a.gamepadActions.frames[1] == frame and frame.actionButtons[1] == row)
    assert(frame:GetHeight() < tallHeight and frame:GetWidth() <= wideWidth, "pooled menu retained earlier text geometry")
    assert(row.label:GetText() == "Short" and row:GetHeight() >= row.label:GetStringHeight())
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad compact menus retain owner anchors and prompt space through managed layouts", function()
    local a = Fixture()
    a.parent:SetSize(800, 220)
    local owner = a:CreateOwnedWindowFrame("Button", nil, a.parent)
    owner:SetSize(100, 24)
    assert(a:ShowGamepadContextMenu(owner, function(_, root)
        local nested = root:CreateButton("Nested")
        for index=1,8 do nested:CreateButton("Inner " .. index) end
        for index=1,8 do root:CreateButton("Action " .. index) end
    end))
    local frame = a.gamepadActions.frames[1]
    local function FitsAndAnchors(panel, subject)
        local point = panel.points[1]
        assert(point and point[1] == "TOPLEFT" and point[2] == subject and point[3] == "TOPRIGHT",
            "managed layout replaced the contextual menu anchor")
        assert((panel:GetHeight() + 48) * panel:GetScale() <= a.parent:GetHeight() * 0.94 + 0.001,
            "managed layout removed the native prompt allowance")
    end
    FitsAndAnchors(frame, owner)
    local width, height, generation = frame:GetWidth(), frame:GetHeight(), frame.actionGeneration
    frame.actionButtons[1]:GetScript("OnClick")()
    local child = a.gamepadActions.frames[2]
    FitsAndAnchors(child, frame)
    local childWidth, childHeight, childGeneration = child:GetWidth(), child:GetHeight(), child.actionGeneration
    a:RefreshManagedWindowLayouts()
    FitsAndAnchors(frame, owner)
    FitsAndAnchors(child, frame)
    assert(frame:GetWidth() == width and frame:GetHeight() == height and frame.actionGeneration == generation)
    assert(child:GetWidth() == childWidth and child:GetHeight() == childHeight and child.actionGeneration == childGeneration,
        "display refresh rebuilt or reset the current menu")
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad compact menu reuse resets check radio and submenu artwork", function()
    local a = Fixture()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        root:CreateCheckbox("Checked", true)
        root:CreateRadio("Not selected", false)
        root:CreateButton("Nested"):CreateButton("Leaf")
        root:CreateHighlightRadio("Selected text", true)
        root:CreateHighlightRadio("Other text", false)
    end))
    local frame = a.gamepadActions.frames[1]
    local check, radio, submenu = unpack(frame.actionButtons)
    assert(check.checkBase:IsShown() and check.checkMark:IsShown() and not check.arrow:IsShown())
    assert(radio.checkBase:IsShown() and not radio.checkMark:IsShown() and not radio.arrow:IsShown())
    assert(not submenu.checkBase:IsShown() and not submenu.checkMark:IsShown() and submenu.arrow:IsShown())
    local selectedText, otherText = frame.actionButtons[4], frame.actionButtons[5]
    for _, row in ipairs({selectedText, otherText}) do
        assert(not row.checkBase:IsShown() and not row.checkMark:IsShown(), "highlight-only setting added a radio icon")
    end
    assert(selectedText.label.textColor[1] ~= selectedText.label.textColor[2])
    assert(otherText.label.textColor[1] == otherText.label.textColor[2])
    local resting = otherText.label.textColor[1]
    otherText:RunScript("OnEnter")
    assert(otherText.label.textColor[1] > resting)
    otherText:RunScript("OnLeave")
    assert(otherText.label.textColor[1] == resting)
    a:CloseGamepadActions()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        for index=1,5 do root:CreateButton("Plain " .. index) end
    end))
    assert(a.gamepadActions.frames[1] == frame)
    for _, row in ipairs(frame.actionButtons) do
        assert(not row.checkBase:IsShown() and not row.checkMark:IsShown() and not row.arrow:IsShown(), "recycled row retained choice artwork")
        assert(not row:GetText():find("%[x%]") and not row:GetText():find(" >"))
    end
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad menu paging preserves the current page when focus cannot be parked", function()
    local a = Fixture()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        for index=1,80 do root:CreateButton("Choice " .. index) end
    end))
    local frame = a.gamepadActions.frames[1]
    local generation, page = frame.actionGeneration, frame.page
    local first = frame.actionButtons[1]
    local text, click = first:GetText(), first:GetScript("OnClick")
    a.cannotPark = true
    frame.next:GetScript("OnClick")()
    assert(frame.actionGeneration == generation and frame.page == page)
    assert(first:IsShown() and first:GetText() == text and first:GetScript("OnClick") == click)
    assert(frame.back:IsVisible() and frame.previous:IsShown() and frame.next:IsShown())
    a.cannotPark = nil
    frame.next:GetScript("OnClick")()
    assert(frame.page == page + 1 and frame.actionGeneration > generation)
    a:CloseGamepadActions()
    a.hideControls = {}
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton("Only one") end))
    assert(not frame.previous:IsShown() and not frame.next:IsShown())
    assert(a.hideControls[frame.previous] == frame.back and a.hideControls[frame.next] == frame.back,
        "paging controls were hidden without parking native focus")
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad menu initial focus parking failure leaves no partial presentation", function()
    local a = Fixture()
    a.cannotPark = true
    assert(not a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton("Action") end))
    assert(not a.gamepadActions and not a.selected and not a.gamepadActionFrames[1]:IsShown())
    a.cannotPark = nil
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        root:CreateButton("Nested"):CreateButton("Leaf")
    end))
    local frame = a.gamepadActions.frames[1]
    a.cannotPark = true
    frame.actionButtons[1]:GetScript("OnClick")()
    assert(#a.gamepadActions.frames == 1 and a.selected == frame and frame:IsShown())
    assert(not a.gamepadActionFrames[2]:IsShown(), "failed nested page captured a partial dialog")
    a.cannotPark = nil
    frame.actionButtons[1]:GetScript("OnClick")()
    assert(#a.gamepadActions.frames == 2 and a.gamepadActions.frames[2]:IsShown())
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad menus wait for a usable display before native presentation", function()
    for _, size in ipairs({{800, 0}, {0, 600}}) do
        local a = Fixture()
        a.parent:SetSize(unpack(size))
        assert(not a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton("Action") end))
        assert(not a.gamepadActions and not a.selected)
        local frame = a.gamepadActionFrames[1]
        assert(not frame:IsShown() and frame.LayoutActionMenu() == false,
            "unavailable display retained a partial interactive menu")
        a.parent:SetSize(800, 600)
        assert(a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton("Action") end))
        assert(a.gamepadActions.frames[1] == frame and frame:IsVisible())
        a:CloseGamepadActions()
    end
end)
QT:RegisterTest("gamepad menu layout callbacks cannot survive a replaced session", function()
    local a = Fixture()
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton("Before") end))
    local frame = a.gamepadActions.frames[1]
    local oldLayout = frame.LayoutActionMenu
    a:CloseGamepadActions()
    assert(oldLayout() == false and not frame:IsShown())
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root) root:CreateButton(string.rep("After ", 20)) end))
    local width, height, generation = frame:GetWidth(), frame:GetHeight(), frame.actionGeneration
    assert(oldLayout() == false)
    assert(frame:GetWidth() == width and frame:GetHeight() == height and frame.actionGeneration == generation)
    local info = a.managedWindows[frame]
    local layout = info.layout
    info.layout = function() error("private layout fixture failure") end
    assert(not pcall(a.ApplyWindowLayout, a, frame))
    assert(not info.applying, "failed transient layout left the shared layout owner locked")
    info.layout = layout
    assert(a:ApplyWindowLayout(frame))
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad action submenu reuse and disabled integration reject retained clicks", function()
    local a, calls = Fixture(), 0
    assert(a:ShowGamepadContextMenu(a.parent, function(_, root)
        root:CreateButton("First"):CreateButton("Delete", function() calls = calls + 1 end)
        root:CreateButton("Second"):CreateButton("Other", function() calls = calls + 1 end)
    end))
    local first = a.gamepadActions.frames[1]
    first.actionButtons[1]:GetScript("OnClick")()
    local second = a.gamepadActions.frames[2]
    local stale = second.actionButtons[1]:GetScript("OnClick")
    second.back:GetScript("OnClick")()
    a.selected = first
    first.actionButtons[2]:GetScript("OnClick")()
    assert(a.gamepadActions.frames[2] == second)
    stale(); assert(calls == 0)
    a.disabled = true
    second.actionButtons[1]:GetScript("OnClick")()
    assert(calls == 0)
    a:CloseGamepadActions()
end)

local function Dropdown(a)
    local control = a:CreateOwnedWindowFrame("Frame", nil, a.parent)
    control.Dropdown = a:CreateOwnedWindowFrame("Button", nil, control)
    control.IncrementButton = a:CreateOwnedWindowFrame("Button", nil, control)
    control.DecrementButton = a:CreateOwnedWindowFrame("Button", nil, control)
    local dropdown = control.Dropdown
    function dropdown:SetDefaultText(text) self.testText = text end
    function dropdown:SetupMenu(generator) self.nativeGenerations = (self.nativeGenerations or 0) + 1; self.nativeGenerator = generator end
    function control:UpdateSteppers() self.nativeUpdates = (self.nativeUpdates or 0) + 1 end
    function control:Increment() self.nativeIncrements = (self.nativeIncrements or 0) + 1 end
    function control:Decrement() self.nativeDecrements = (self.nativeDecrements or 0) + 1 end
    control.IncrementButton:SetScript("OnClick", function() control:Increment() end)
    control.DecrementButton:SetScript("OnClick", function() control:Decrement() end)
    return control, dropdown
end

local function DropdownAppearance(button)
    return tostring(button.Background:GetAtlas()) .. "/" .. tostring(button.Arrow:GetAtlas())
        .. "/" .. tostring(button.Arrow:IsShown())
end

QT:RegisterTest("owned gamepad dropdown skins preserve disclosure and reset transient input state", function()
    for _, variant in ipairs({{"standard", false}, {"standard", true}, {"settings", false}}) do
        local a = Fixture()
        local button = assert(a:CreateOwnedDropdownButton(a.parent, unpack(variant)))
        button:SetSize(180, 25)
        button:SetText("Current selection")
        assert(button.kind == "Button" and button.template ~= "UIPanelButtonTemplate")
        assert(button:GetFontString() == button.Text and button.Text:GetText() == "Current selection")
        assert(button.Background:GetAtlas() and button.Arrow:GetAtlas(), "dropdown lost native disclosure artwork")
        local normal = DropdownAppearance(button)
        button:RunScript("OnEnter")
        assert(button.dropdownOver == true)
        button:RunScript("OnMouseDown", "LeftButton")
        assert(button.dropdownDown == true and DropdownAppearance(button) ~= normal)
        button:RunScript("OnMouseUp", "LeftButton")
        assert(not button.dropdownDown)
        button:RunScript("OnLeave")
        assert(not button.dropdownOver and DropdownAppearance(button) == normal)
        button:SetOwnedMenuOpen(true)
        assert(button.dropdownMenuOpen == true)
        button:SetOwnedMenuOpen(false)
        button:RunScript("OnMouseDown", "LeftButton")
        button:SetEnabled(false)
        assert(not button.dropdownDown and DropdownAppearance(button) ~= normal, "disabled dropdown retained its pressed appearance")
        local disabledBackground, disabledArrow = button.Background:GetAtlas(), button.Arrow:GetAtlas()
        button:RunScript("OnMouseDown", "LeftButton")
        button:RunScript("OnEnter")
        assert(not button.dropdownDown and button.Background:GetAtlas() == disabledBackground
            and button.Arrow:GetAtlas() == disabledArrow, "disabled hover restored enabled dropdown artwork")
        button:SetEnabled(true)
        button:RunScript("OnLeave")
        assert(DropdownAppearance(button) == normal)
        button:RunScript("OnEnter")
        button:RunScript("OnMouseDown", "LeftButton")
        button:Hide()
        assert(not button.dropdownDown and not button.dropdownOver, "hidden dropdown retained a missed release")
        button:Show()
        assert(DropdownAppearance(button) == normal)
        local writes = button.writes + button.Background.writes + button.Arrow.writes + button.Text.writes
        a.blocked = true
        button:RunScript("OnMouseDown", "LeftButton")
        button:RunScript("OnEnter")
        assert(writes == button.writes + button.Background.writes + button.Arrow.writes + button.Text.writes,
            "dropdown skin mutated through restrictions")
    end
end)

QT:RegisterTest("gamepad dropdown choices anchor below the receiver and retire their open indicator", function()
    local a, calls = Fixture(), 0
    local control, dropdown = Dropdown(a)
    local choice = assert(a:ConfigureGamepadDropdown(dropdown, function(_, root)
        root:CreateButton("Nested"):CreateButton("Choose", function() calls = calls + 1 end)
    end, "Selected", "settings"))
    assert(choice.Background and choice.Arrow and choice.Text)
    choice:RunScript("OnMouseDown", "LeftButton")
    choice:RunScript("OnMouseUp", "LeftButton")
    assert(not a.gamepadActions and calls == 0, "artwork dispatched an extra menu activation")
    choice:RunScript("OnClick", "LeftButton")
    local first = a.gamepadActions.frames[1]
    assert(choice.dropdownMenuOpen == true)
    local point = first.points[1]
    assert(point and point[2] == choice and point[1]:find("TOP") and point[3]:find("BOTTOM"),
        "dropdown choices opened beside the control instead of underneath it")
    assert(not first.title:IsShown(), "dropdown choices retained the unrelated QuestTogether heading")
    first.actionButtons[1]:GetScript("OnClick")()
    local nested = a.gamepadActions.frames[2]
    assert(choice.dropdownMenuOpen == true)
    nested.back:GetScript("OnClick")()
    a.selected = first
    assert(choice.dropdownMenuOpen == true, "nested Back closed the dropdown owner indicator")
    first.back:GetScript("OnClick")()
    assert(not choice.dropdownMenuOpen and not a.gamepadActions)
    choice:RunScript("OnClick", "LeftButton")
    first = a.gamepadActions.frames[1]
    first.actionButtons[1]:GetScript("OnClick")()
    a.gamepadActions.frames[2].actionButtons[1]:GetScript("OnClick")()
    assert(calls == 1 and not choice.dropdownMenuOpen and not a.gamepadActions)
    a.cannotPark = true
    choice:RunScript("OnClick", "LeftButton")
    assert(not choice.dropdownMenuOpen and not a.gamepadActions, "failed popup left the choice looking open")
end)

QT:RegisterTest("gamepad dropdown skins retain text generator identity and explanatory tooltips", function()
    local a, calls = Fixture(), 0
    local control, dropdown = Dropdown(a)
    local choice = assert(a:ConfigureGamepadDropdown(dropdown, function(_, root)
        root:CreateButton("Old action", function() calls = calls + 1 end)
    end, "Before", "settings"))
    function a:ShowSettingsTooltip(owner, title, text)
        self.tooltipOwner, self.tooltipTitle, self.tooltipText = owner, title, text
    end
    function a:HideSettingsTooltip(owner)
        if self.tooltipOwner == owner then self.tooltipOwner = nil end
    end
    choice.Text:SetWidth(20)
    choice:RunScript("OnEnter")
    assert(a.tooltipOwner == choice and a.tooltipTitle == "Before" and a.tooltipText == "",
        "truncated HUD selection lost its full-value tooltip")
    choice:RunScript("OnLeave")
    assert(not a.tooltipOwner)
    a:AttachSettingsTooltip(choice, "Setting title", "Setting explanation")
    choice:RunScript("OnEnter")
    assert(a.tooltipOwner == choice and a.tooltipTitle == "Setting title" and a.tooltipText == "Setting explanation")
    assert(choice.dropdownOver == true, "tooltip hook replaced dropdown hover artwork")
    choice:RunScript("OnLeave")
    assert(not a.tooltipOwner and not choice.dropdownOver)
    choice:RunScript("OnClick", "LeftButton")
    local oldAction = a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")
    local replaced = a:ConfigureGamepadDropdown(dropdown, function(_, root)
        root:CreateButton("New action", function() calls = calls + 10 end)
    end, "After", "settings")
    assert(replaced == choice and choice.Text:GetText() == "After")
    oldAction(); assert(calls == 0)
    a:CloseGamepadActions()
    dropdown:SetDefaultText("Current label")
    assert(choice.Text:GetText() == "Current label")
    dropdown:SetEnabled(false)
    choice:RunScript("OnEnter")
    assert(a.tooltipOwner == choice, "disabled setting lost its explanation")
    choice:RunScript("OnClick", "LeftButton")
    assert(not a.gamepadActions)
    control:Hide()
    assert(not a.tooltipOwner and not choice.dropdownDown and not choice.dropdownOver)
    control:Show()
    dropdown:SetEnabled(true)
    choice:RunScript("OnClick", "LeftButton")
    a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")()
    assert(calls == 10 and not choice.dropdownMenuOpen)
end)

QT:RegisterTest("gamepad dropdowns preserve visibility enabled state and mouse menus without native fallback", function()
    local a, calls = Fixture(), 0
    local control, dropdown = Dropdown(a)
    local function Generator(_, root) root:CreateButton("Choose", function() calls=calls+1 end) end
    local choice = assert(a:ConfigureGamepadDropdown(dropdown, Generator))
    assert(choice:IsShown() and not dropdown:IsShown() and not dropdown.nativeGenerations)
    dropdown:SetDefaultText("Current value")
    assert(choice:GetText() == "Current value")
    choice:GetScript("OnClick")()
    local action = a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")
    dropdown:SetEnabled(false); action()
    assert(calls == 0 and not choice:IsEnabled())
    a:CloseGamepadActions()
    dropdown:SetEnabled(true)
    dropdown:Hide(); assert(not choice:IsShown())
    a.mode=false; a.observers[choice]()
    assert(not dropdown:IsShown() and not choice:IsShown())
    dropdown:Show(); assert(dropdown:IsShown() and dropdown.nativeGenerations == 1)
    a.mode=true; a.failed=true; a.observers[choice]()
    assert(not dropdown:IsShown() and choice:IsShown() and not choice:IsEnabled())
    choice:GetScript("OnClick")(); assert(not a.gamepadActions and calls==0)
    a.failed=false; a.observers[choice]()
    choice:GetScript("OnClick")()
    action=a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")
    a:ConfigureGamepadDropdown(dropdown,function() end)
    action(); assert(calls==0)
    a:CloseGamepadActions()
end)
QT:RegisterTest("gamepad Settings arrows use current owned options and preserve original mouse stepping", function()
    local a = Fixture()
    local control, dropdown = Dropdown(a)
    local value=2
    local function Entries()
        local entries={}
        for index=1,3 do
            local id=index
            entries[index]={checked=function() return value==id end,func=function() value=id end}
        end
        return entries
    end
    a:ConfigureGamepadDropdownSteppers(control,Entries)
    control.IncrementButton:GetScript("OnClick")()
    assert(value==3 and not control.IncrementButton:IsEnabled() and control.testContainer)
    control:Increment(); assert(value==3)
    control.DecrementButton:GetScript("OnClick")()
    assert(value==2 and not control.nativeUpdates and not control.nativeIncrements)
    dropdown:SetEnabled(false)
    control:Decrement(); assert(value==2)
    dropdown:SetEnabled(true)
    a.disabled=true; control:Decrement(); assert(value==1)
    a.failed=true; control:Increment(); assert(value==1)
    a.disabled=false; a.failed=false; a.mode=false
    control.IncrementButton:GetScript("OnClick")()
    control:UpdateSteppers()
    assert(control.nativeIncrements==1 and control.nativeUpdates==1 and value==1)
end)
QT:RegisterTest("disabled or unavailable controller integration keeps owned mouse choices without native registration", function()
    for _, flag in ipairs({"disabled", "unsupported"}) do
        local a, calls = Fixture(), 0
        a[flag] = true
        local control, dropdown = Dropdown(a)
        local function Generator(_, root)
            root:CreateButton("Nested"):CreateButton("Choose", function() calls = calls + 1 end)
        end
        local choice = assert(a:ConfigureGamepadDropdown(dropdown, Generator))
        assert(choice:IsShown() and choice:IsEnabled() and not dropdown.nativeGenerations)
        choice:GetScript("OnClick")()
        local first = a.gamepadActions.frames[1]
        assert(not first.testPolicy and not a.selected and not a.navigationRefreshes)
        first.actionButtons[1]:GetScript("OnClick")()
        local nested = a.gamepadActions.frames[2]
        assert(not nested.testPolicy and not a.selected)
        nested.actionButtons[1]:GetScript("OnClick")()
        assert(calls == 1 and not a.gamepadActions)
        choice:GetScript("OnClick")()
        local stale = a.gamepadActions.frames[1].actionButtons[1]:GetScript("OnClick")
        a.db.profile = {}; stale()
        assert(#a.gamepadActions.frames == 1 and calls == 1)
        a:CloseGamepadActions()
        a.failed = true; a.observers[choice]()
        choice:GetScript("OnClick")()
        assert(not a.gamepadActions and not choice:IsEnabled())
    end
end)
QT:RegisterTest("gamepad settings observers ignore native selection churn and unsafe dropdown hides", function()
    local a = Fixture()
    local control, dropdown = Dropdown(a)
    local choice = a:ConfigureGamepadDropdown(dropdown, function(_, root) root:CreateButton("Choose") end)
    local rows = 0
    a:ConfigureGamepadDropdownSteppers(control, function()
        rows = rows + 1
        return {{checked = true, func = function() end}}
    end)
    local originalRows, originalHides = rows, a.hideGuards
    for _=1,100 do a.observers[choice](); a.observers[control]() end
    assert(rows == originalRows and a.hideGuards == originalHides)
    a.disabled = true; a.observers[choice](); a.observers[control]()
    assert(rows == originalRows + 1 and choice:IsEnabled())
    a.mode = false; a.observers[choice]()
    assert(dropdown:IsShown())
    a.mode = true; a.unsupported = true; a.cannotPark = true; a.observers[choice]()
    assert(dropdown:IsShown() and choice:IsShown(), "unproven native receiver must remain while mouse choice overlays it")
    local generations = dropdown.nativeGenerations
    a.observers[choice]()
    assert(dropdown.nativeGenerations == generations)
end)
QT:RegisterTest("gamepad menu capacity and protected target exclusion are explicit", function()
    local a = Fixture()
    local model = a:BuildGamepadActionDescription(nil, function(_, root)
        a:PopulateLocationTargetMenu(root, "Somebody")
        for i=1,256 do root:CreateButton(tostring(i)) end
    end)
    assert(model.count == 256)
    assert(not pcall(function() model:CreateButton("overflow") end))
end)
QT:RegisterTest("pending controller requests require the same live record and expiry", function()
    local a, opened = Fixture(), 0
    function a:IsIgnoredPlayerName() return false end
    function a:IsGroupedSender() return true end
    function a:RenderPartyQuestSharePrompt(request) opened = opened + 1; return {request=request} end
    a.partyQuestShareState = {incoming = {one = {key="one",sender="Friend",questId=3,expires=110}}}
    local record = a:GetGamepadPendingRequests()[1]
    assert(record and a:OpenGamepadPendingRequest(record) and opened == 1)
    a.partyQuestShareState.incoming.one = {key="one",sender="Friend",questId=3,expires=110}
    assert(not a:OpenGamepadPendingRequest(record) and opened == 1)
    a.partyQuestShareState.incoming.one.expires = 99
    assert(#a:GetGamepadPendingRequests() == 0)
end)
_G.QuestTogether:RecordTestModule("scripts/regression_gamepad_actions.lua")
