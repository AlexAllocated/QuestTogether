-- Private registry/display fixtures only; never touch live LibStub or toolbars.
local QT = _G.QuestTogether
local Equal = QT.LibChev.AssertEqual
local function Fixture()
	local a = setmetatable({ isEnabled = true, hasLoggedIn = true, isRunningTests = false,
		db = { profile = QT:DeepCopy(QT.DEFAULTS.profile) }, calls = {}, identity = "normal", lookups = 0 }, { __index = QT })
	function a:GetOption(key) return self.db.profile[key] end
	function a:IsRuntimeRestricted() return self.restricted == true end
	function a:GetDataBrokerLibrary() self.lookups = self.lookups + 1; return self.library end
	function a:GetMinimapIdentityTexture() return self.identity end
	function a:TogglePartyQuestCompare() self.calls[#self.calls + 1] = "pql"; return true end
	function a:ShowMinimapMenu(frame) self.calls[#self.calls + 1] = frame; return true end
	function a:OpenOptionsWindow() self.calls[#self.calls + 1] = "settings"; return true end
	function a:HandleQuestPartnerCommand(input) self.calls[#self.calls + 1] = input; return true end
	return a
end
local function Library(a)
	local registry, lib = {}, { creates = 0, changes = 0 }
	function lib:GetDataObjectByName(name) return registry[name] end
	function lib:NewDataObject(name, object)
		assert(not registry[name], "must register only once")
		assert(object.type == "launcher" and object.icon and object.label and object.text
			and type(object.OnClick) == "function" and type(object.OnTooltipShow) == "function", "publish complete launcher")
		self.creates = self.creates + 1
		local values = {}
		for key, value in pairs(object) do values[key], object[key] = value, nil end
		setmetatable(object, { __index = values, __newindex = function(_, key, value)
			if values[key] == value then return end
			values[key] = value
			lib.changes = lib.changes + 1
			if lib.throwUpdate then error("broken display update") end
		end })
		registry[name] = object
		Equal(a:RefreshDataBroker(), false, "synchronous display callbacks cannot re-enter registration")
		if self.throwCreate then error("broken display creation") end
		return object
	end
	return lib, registry
end

QT:RegisterTest("data broker tolerates absent late restricted and conflicting libraries without duplicate launchers", function()
	local a = Fixture()
	a.hasLoggedIn = false
	Equal(a:RefreshDataBroker(), false)
	Equal(a.lookups, 0)
	a.hasLoggedIn = true
	Equal(a:RefreshDataBroker(), false, "no library is a normal supported installation")
	a.library = Library(a)
	a.restricted = true
	Equal(a:RefreshDataBroker(), false)
	Equal(a.library.creates, 0)
	a.restricted = false
	a.db.profile.showMinimapButton = false
	assert(a:RefreshDataBroker(), "late library works with minimap hidden")
	local object = a.dataBrokerState.object
	assert(a:RefreshDataBroker())
	Equal(a.library.creates, 1)
	Equal(a.library.changes, 0, "unchanged fields produce no display notifications")
	a.identity, a.db.profile.lookingForQuestPartners = "vip", true
	assert(a:RefreshDataBroker())
	Equal(object.icon, "vip")
	Equal(object.text, QT.Translate("Looking for Questing Partners"))
	a.isEnabled, a.identity = false, "normal"
	assert(a:RefreshDataBroker())
	Equal(object.iconR, 0.5)
	Equal(object.text, QT.Translate("Disabled"))
	local other = Fixture()
	local registry
	other.library, registry = Library(other)
	local foreign = { icon = "someone else" }
	registry.QuestTogether = foreign
	Equal(other:RefreshDataBroker(), false)
	Equal(other.library.creates, 0)
	Equal(foreign.icon, "someone else", "never overwrite another addon's registration")
	Equal(rawget(other.dataBrokerState, "object"), nil)
	assert(QT.isRunningTests and QT:GetDataBrokerLibrary() == nil, "real adapter never exposes the live registry in tests")
end)

QT:RegisterTest("data broker isolates display failures and recovers its own installed proxy", function()
	local a = Fixture()
	a.library = Library(a)
	a.library.throwCreate = true
	Equal(a:RefreshDataBroker(), false)
	Equal(a.dataBrokerState.busy, nil)
	local candidate = a.dataBrokerState.candidate
	assert(candidate)
	assert(a:RefreshDataBroker())
	Equal(a.dataBrokerState.object, candidate)
	Equal(a.library.creates, 1)
	a.library.throwUpdate, a.identity = true, "developer"
	Equal(a:RefreshDataBroker(), false)
	Equal(a.dataBrokerState.busy, nil)
	a.library.throwUpdate = false
	assert(a:RefreshDataBroker())
	Equal(candidate.icon, "developer")
	Equal(a.library.creates, 1)
end)

QT:RegisterTest("data broker actions follow live profiles and respect disabled restricted and foreign frame boundaries", function()
	local a = Fixture()
	a.library = Library(a)
	assert(a:RefreshDataBroker())
	local object, frame = a.dataBrokerState.object, {}
	assert(object.OnClick(frame, "LeftButton")); Equal(a.calls[1], "pql")
	assert(object.OnClick(frame, "RightButton")); Equal(a.calls[2], frame)
	Equal(object.OnClick(frame, "MiddleButton"), false)
	a.db.profile.brokerLeftClick = "partners"
	assert(object.OnClick(frame, "LeftButton")); Equal(a.calls[3], "toggle")
	a.db.profile = QT:DeepCopy(QT.DEFAULTS.profile)
	a.db.profile.brokerLeftClick = "settings"
	a.isEnabled = false
	assert(object.OnClick(frame, "LeftButton")); Equal(a.calls[4], "settings")
	a.db.profile.brokerLeftClick = "pql"
	Equal(object.OnClick(frame, "LeftButton"), false)
	a.db.profile.brokerLeftClick = "none"
	Equal(object.OnClick(frame, "LeftButton"), false)
	Equal(a:ValidateSetting("brokerLeftClick", "other"), nil)
	Equal(a:ValidateSetting("brokerRightClick", "partners"), "partners")
	a.restricted = true
	Equal(object.OnClick(frame, "RightButton"), false)
	a.restricted = false
	frame.IsForbidden = function() return true end
	Equal(object.OnClick(frame, "RightButton"), false)
	frame.IsForbidden = nil
	frame.IsProtected = function() return true end
	Equal(object.OnClick(frame, "RightButton"), false)
	frame.IsProtected = nil
	a.isLoggingOut = true
	Equal(object.OnClick(frame, "RightButton"), false)
	a.isLoggingOut, a.isRunningTests = false, true
	Equal(object.OnClick(frame, "RightButton"), false)
	Equal(#a.calls, 4, "invalid/stale interactions never dispatch actions")
end)

QT:RegisterTest("data broker tooltip uses only guarded public content calls and reflects current click choices", function()
	local a, lines = Fixture(), {}
	a.library = Library(a)
	a.db.profile.showMinimapButton, a.db.profile.brokerRightClick = false, "partners"
	assert(a:RefreshDataBroker())
	local object = a.dataBrokerState.object
	local tooltip = { AddLine = function(_, line) lines[#lines + 1] = line end }
	assert(object.OnTooltipShow(tooltip))
	Equal(lines[1], QT.Translate("QuestTogether"))
	Equal(lines[#lines], string.format(QT.Translate("Right-click: %s"), QT.Translate("Looking for Questing Partners")))
	Equal(next(tooltip), "AddLine", "no state or scripts written to the display's tooltip")
	local count = #lines
	a.restricted = true
	Equal(object.OnTooltipShow(tooltip), false)
	a.restricted = false
	tooltip.IsForbidden = function() return true end
	Equal(object.OnTooltipShow(tooltip), false)
	tooltip.IsForbidden = nil
	tooltip.IsProtected = function() return true end
	Equal(object.OnTooltipShow(tooltip), false)
	Equal(#lines, count)
	tooltip.IsProtected = nil
	tooltip.AddLine = function() error("display tooltip failed") end
	Equal(object.OnTooltipShow(tooltip), false, "third-party failures stay inside the integration")
end)

_G.QuestTogether:RecordTestModule("scripts/regression_data_broker.lua")
