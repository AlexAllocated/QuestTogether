-- Explicit presentation policies for ordinary QT windows. No HUD is registered.
local QT = _G.QuestTogether
local L = QT.Translate
function QT:GetGamepadLauncherAnchor()
    if not self.gamepadLauncherAnchor then
        local anchor = self:CreateOwnedWindowFrame("Frame", nil, self:GetOwnedUIParent())
        anchor:SetSize(1, 1); anchor:SetPoint("CENTER"); anchor:EnableMouse(false)
        self.gamepadLauncherAnchor = anchor
    end
    return self.gamepadLauncherAnchor
end
function QT:ConfigureStandardGamepadWindow(frame, role, close, initial, scroll)
	self:GuardGamepadWindowActions(frame, {frame.close, frame.Close, frame.cancel, frame.save, frame.delete,
        frame.activate, frame.discord, frame.clear, frame.SaveButton, frame.RevertButton, frame.ResetButton})
    if self:IsNativeGamepadMode() then
        for _, control in pairs({frame.dragHandle, frame.resizeGrip, frame.Drag, frame.Resize, frame.DragHandle}) do
            self:SetGamepadControlIgnored(control, true)
        end
    end
    self:ConfigureWindowController(frame, { gamepad = {
        role = role, kind = "window", footer = true, scrollFrame = scroll,
        -- Startup patch notes are readable/dismissible immediately. Other
        -- automatic windows and incoming requests remain passive.
        allowAutomaticFocus = role == "release_notes",
        defaultFocus = function() return initial or frame.cancel or frame.close or frame.Close end,
        close = close or function() self:DismissManagedWindow(frame) end,
    } })
end
function QT:PresentStandardGamepadWindow(frame, role, close, initial, scroll, intent)
    if not frame then return false end
    self:ConfigureStandardGamepadWindow(frame, role, close, initial, scroll)
    return self:PresentGamepadWindow(frame, intent or "user")
end

-- Records remain owned by their request services. The menu retains a reference
-- only so a superseded/expired request can never activate its replacement.
function QT:GetGamepadPendingRequests()
    local result = {}
    if not self.isEnabled then return result end
    local now, profile = self.API.GetTime(), self.db and self.db.profile
    local function Collect(kind, state, predicate)
        for key, request in pairs(state and state.incoming or {}) do
            if type(request) == "table" and type(request.expires) == "number" and now < request.expires
                and (not request.profile or request.profile == profile) and not self:IsIgnoredPlayerName(request.sender)
                and predicate(request) then
                result[#result + 1] = {kind = kind, state = state, key = key, request = request, profile = profile}
            end
        end
    end
    Collect("share", rawget(self, "partyQuestShareState"), function(r) return self:IsPartyRequestPromptCurrent(r, "share") end)
    Collect("join", rawget(self, "partyJoinState"), function(r)
        return type(r.created) == "number" and self:IsPartyRequestPromptCurrent(r, "join")
    end)
    local reminder = rawget(self, "partyChatReminderState")
    if reminder and reminder.request and reminder.profile == profile then
        result[#result + 1] = {kind = "reminder", state = reminder, request = reminder.request, profile = profile}
    end
    table.sort(result, function(a,b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return tostring(a.key or "") < tostring(b.key or "")
    end)
    return result
end
function QT:OpenGamepadPendingRequest(record)
    if not record or self:IsWorkBlocked("foreign_frame_mutation") then return false end
    local live = false
    for _, candidate in ipairs(self:GetGamepadPendingRequests()) do
        if candidate.state == record.state and candidate.request == record.request and candidate.profile == record.profile then live = true; break end
    end
    if not live then return false end
    local frame
    if record.kind == "share" then frame = self:RenderPartyQuestSharePrompt(record.request)
    elseif record.kind == "join" then frame = self:RenderPartyJoinPrompt(record.request)
    else self:RenderPartyChatReminder(record.request); frame = rawget(self, "partyChatReminderFrame") end
    if not frame or frame.request ~= record.request then return false end
    return self:PresentGamepadWindow(frame, "user")
end
function QT:PopulateGamepadPendingRequests(root)
    local records = self:GetGamepadPendingRequests()
    local menu = root:CreateButton(L("Pending Requests"))
    menu:SetEnabled(#records > 0)
    for _, record in ipairs(records) do
        local label = record.kind == "share" and L("QuestTogether · Share request")
            or record.kind == "join" and L("QuestTogether · Join request") or L("QuestTogether · Party chat announcements")
        local sender = record.request.sender
        if sender then label = label .. ": " .. sender:gsub("|", "||") end
        if record.kind == "share" then label = label .. " - " .. self:GetQuestTitle(record.request.questId) end
        menu:CreateButton(label, function() self:OpenGamepadPendingRequest(record) end)
    end
end

function QT:ConfigureRecentCompanionsGamepad(frame)
    local function Move(row, delta)
        if not self:IsGamepadActionCurrent(frame) or not frame.session then return nil end
        local entries, index = self:GetRecentCompanions()
        for i, entry in ipairs(entries) do if entry.name == frame.gamepadCompanionIdentity then index = i; break end end
        if not index then for i, entry in ipairs(entries) do if entry.name == row.identity then index = i; break end end end
        if not index then return frame.close end
        local nextIndex = index + delta
        if nextIndex < 1 then return frame.close end
        if nextIndex > #entries then return frame.clear end
        frame.gamepadCompanionIdentity = entries[nextIndex].name
        frame.offset = math.max(0, math.min(frame.offset or 0, nextIndex - 1))
        if nextIndex > frame.offset + #frame.rows then frame.offset = nextIndex - #frame.rows end
        self:RefreshRecentCompanionsWindow()
        return frame.rows[nextIndex - frame.offset]
    end
    self:ConfigureWindowController(frame, { gamepad = { role = "companions", footer = true,
        defaultFocus = function() return frame.rows[1].identity and frame.rows[1] or frame.close end,
        close = function() self:DismissRecentCompanions() end,
        onSelection = function(_, button)
            if frame.gamepadCompanionParking then return end
            frame.gamepadCompanionIdentity, frame.gamepadCompanionIndex = nil, nil
            for index, row in ipairs(frame.rows) do
                if button == row and row.identity then
                    frame.gamepadCompanionIdentity = row.identity
                    frame.gamepadCompanionIndex = (frame.offset or 0) + index
                    break
                end
            end
        end,
    } })
    self:GuardGamepadWindowActions(frame, {frame.close, frame.clear})
    if not self:IsNativeGamepadMode() then return end
    self:MarkGamepadContainer(frame.list)
    for _, row in ipairs(frame.rows) do
        self:SetGamepadDirectionOverride(row, "UP", function() return Move(row, -1) end)
        self:SetGamepadDirectionOverride(row, "DOWN", function() return Move(row, 1) end)
        row.OnSmartNavClick = function()
            if not self:IsGamepadActionCurrent(frame) or frame.gamepadCompanionParking
                or not row.identity or row.identity ~= frame.gamepadCompanionIdentity then return end
            local _, _, selected = self:GetNativeGamepadFocus()
            if selected == row then self:ShowRecentCompanionMenu(row, row.identity) end
        end
    end
end
function QT:PrepareRecentCompanionsGamepadRefresh(frame, entries, offset, visibleRows)
    if not self:IsGamepadWindowFocused(frame) then return offset end
    local identity, index = frame.gamepadCompanionIdentity, frame.gamepadCompanionIndex
    if identity then
        local found
        for i, entry in ipairs(entries) do if entry.name == identity then found = i; break end end
        index = found or (#entries > 0 and math.max(1, math.min(index or offset + 1, #entries)))
        frame.gamepadCompanionIdentity = index and entries[index].name or nil
        frame.gamepadCompanionIndex = index
        if index then offset = math.max(0, math.min(offset, index - 1)); offset = math.max(offset, index - visibleRows) end
    end
    -- Retarget before hiding/reusing a selected row; the native cursor must not
    -- inherit that child's Hide and tear down input outside the wrapped path.
    frame.gamepadCompanionParking = true
    if not self:PrepareGamepadControlHide(frame.list, frame.close) then
        frame.gamepadCompanionParking = nil
        return nil
    end
    return offset
end
function QT:RefreshRecentCompanionsGamepad(frame)
    frame.gamepadCompanionParking = nil
    if not self:IsGamepadWindowFocused(frame) or not frame.gamepadCompanionIdentity then return end
    local target
    for _, row in ipairs(frame.rows) do if row.identity == frame.gamepadCompanionIdentity then target = row; break end end
    if not target then target = frame.rows[1].identity and frame.rows[1] or frame.close end
    self:RefreshGamepadNavigation(frame, target)
end

-- Explicit Show is user intent for library-owned presenters; inherited OnShow
-- after UIParent restoration is deliberately not an activation signal.
function QT:PresentOnExplicitShow(frame)
    if frame.qtExplicitGamepadShow then return end
    frame.qtExplicitGamepadShow = true
    local show = frame.Show
    frame.Show = function(owned, ...)
        show(owned, ...)
        self:PresentGamepadWindow(owned, "user")
    end
end
function QT:ConfigureDiagnosticGamepadWindow(frame)
    self:ConfigureStandardGamepadWindow(frame, "diagnostics", nil, frame.Close, frame.Scroll)
    self:PresentOnExplicitShow(frame)
    local categoryClick = frame.Category:GetScript("OnClick")
    frame.Category:SetScript("OnClick", function(control, ...)
        if not self:IsNativeGamepadMode() then return categoryClick(control, ...) end
        self:ShowGamepadContextMenu(control, function(_, root)
            local controller = self:GetDebugController()
            for _, category in ipairs(controller:GetCategories()) do
                root:CreateRadio(category, function() return controller:GetCategory() == category end, function()
                    controller:SetCategory(category)
                    self:RefreshGamepadNavigation(frame)
                end)
            end
        end)
    end)
    -- The library exposes these owned controls through its supported callback.
    -- Its log/report switch hides them; park before their native Hide happens.
    for _, control in pairs({frame.Category, frame.Search, frame.Popup, frame.Buttons.clear}) do
        local hide, setShown = control.Hide, control.SetShown
        control.Hide = function(owned)
            if self:PrepareGamepadControlHide(owned, frame.Close) then return hide(owned) end
        end
        control.SetShown = function(owned, shown)
            if shown or self:PrepareGamepadControlHide(owned, frame.Close) then return setShown(owned, shown) end
        end
    end
    self:GuardGamepadWindowActions(frame, frame.Buttons)
    self:GuardGamepadWindowActions(frame, {frame.Category})
end
function QT:GuardGamepadWindowActions(frame, controls)
    frame.qtGamepadActionGuards = frame.qtGamepadActionGuards or {}
    for _, control in pairs(controls) do
        if control and self.LibChev.CanMutateOwnedRegion(control) and type(control.GetScript) == "function" then
            local original = control:GetScript("OnClick")
            if original and frame.qtGamepadActionGuards[control] ~= original then
                local wrapper = function(...)
                    if self:IsNativeGamepadMode() then
                        local status = self:GetGamepadIntegrationStatus()
                        if status and status.failed or self:IsGamepadWindowRegistered(frame) and not self:IsGamepadActionCurrent(frame) then return end
                    end
                    return original(...)
                end
                frame.qtGamepadActionGuards[control] = wrapper
                control:SetScript("OnClick", wrapper)
            end
        end
    end
end
