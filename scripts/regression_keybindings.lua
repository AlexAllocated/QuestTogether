-- Private addon/controller services only; never assigns keys or native globals.
local QT = _G.QuestTogether
local ACTIONS = { "menu", "party_log", "quest_partners", "stop_follow", "chat", "settings" }

local function Fixture()
	local a = setmetatable({
		isInitialized = true,
		isEnabled = true,
		isLoggingOut = false,
		db = { profile = {}, global = {} },
		calls = {},
		states = {},
	}, { __index = QT })
	function a:IsRuntimeRestricted()
		return self.restricted == true
	end
	local function Call(name)
		a.calls[#a.calls + 1] = name
		return a.result
	end
	function a:OpenQuickMenu()
		return Call("menu")
	end
	function a:TogglePartyQuestCompare()
		return Call("party_log")
	end
	function a:HandleQuestPartnerCommand(action)
		assert(action == "toggle")
		return Call("quest_partners")
	end
	function a:OpenOptionsWindow()
		return Call("settings")
	end
	a.API = {
		OpenQTChatComposer = function()
			return Call("chat")
		end,
		SetPartyNavigationQuest = function()
			error("binding must not change native focus")
		end,
		SetUserWaypoint = function()
			error("binding must not change native waypoint")
		end,
	}
	local function Controller(name)
		local state = { following = name, expectedQuest = 123, attempt = {}, resuming = true }
		a.states[name] = state
		return a:CreatePartyFocusController({
			peek = function()
				return state
			end,
			save = function(target)
				assert(target == nil)
				Call("save:" .. name)
			end,
			publish = function()
				Call("publish:" .. name)
			end,
			changed = function()
				Call("changed:" .. name)
			end,
		})
	end
	a.partyFocusController = Controller("live")
	a.previewController = Controller("preview")
	function a:GetPartyFocusController()
		return self.partyFocusController
	end
	return a
end

QT:RegisterTest("keybindings dispatch only the six declared player actions", function()
	local a = Fixture()
	for _, action in ipairs({ "menu", "party_log", "quest_partners", "chat", "settings" }) do
		a.calls = {}
		assert(a:HandleKeybinding(action), "a nil UI return still means the action was invoked")
		assert(#a.calls == 1 and a.calls[1] == action)
		a.result = false
		assert(not a:HandleKeybinding(action), "explicit failures remain failures")
		a.result = nil
	end
	a.calls = {}
	for _, action in ipairs({ "", "debug", "ping", "ad", "PARTY_LOG", "unknown", {} }) do
		assert(not a:HandleKeybinding(action))
	end
	assert(not a:HandleKeybinding(nil) and #a.calls == 0)
	a.API.OpenQTChatComposer = nil
	assert(not a:HandleKeybinding("chat"))
end)

QT:RegisterTest("keybindings cannot run before initialization or after logout begins", function()
	for _, setup in ipairs({
		function(a)
			a.isInitialized = false
		end,
		function(a)
			a.db = false
		end,
		function(a)
			a.db.profile = nil
		end,
		function(a)
			a.isLoggingOut = true
		end,
	}) do
		local a = Fixture()
		setup(a)
		for _, action in ipairs(ACTIONS) do
			assert(not a:HandleKeybinding(action))
		end
		assert(#a.calls == 0 and a.states.live.following == "live")
	end
end)

QT:RegisterTest("keybindings block restricted UI actions but can cancel following intent", function()
	local a = Fixture()
	a.restricted = true
	for _, action in ipairs({ "menu", "party_log", "quest_partners", "chat", "settings" }) do
		assert(not a:HandleKeybinding(action))
	end
	assert(#a.calls == 0)
	assert(a:HandleKeybinding("stop_follow"))
	assert(not a.states.live.following and not a.states.live.expectedQuest and not a.states.live.attempt)
	assert(table.concat(a.calls, ",") == "save:live,publish:live,changed:live")
end)

QT:RegisterTest("keybindings keep configuration and social actions available while QT features are disabled", function()
	local a = Fixture()
	a.isEnabled = false
	for _, action in ipairs({ "menu", "quest_partners", "chat", "settings" }) do
		assert(a:HandleKeybinding(action))
	end
	assert(table.concat(a.calls, ",") == "menu,quest_partners,chat,settings")
	-- PQL owns its disabled message and can still close an existing preview.
	a.result = false
	assert(not a:HandleKeybinding("party_log") and a.calls[#a.calls] == "party_log")
	assert(a:HandleKeybinding("stop_follow") and not a.states.live.following)
end)

QT:RegisterTest("keybinding stop follow cancels the active preview without changing native focus", function()
	local a = Fixture()
	a:AcquirePartyFocusController(a.previewController)
	assert(a:HandleKeybinding("stop_follow"))
	assert(not a.states.preview.following and a.states.live.following == "live")
	assert(table.concat(a.calls, ",") == "save:preview,publish:preview,changed:preview")
	assert(a.nativePartyFocusOwner == a.previewController, "stopping a preview must not hand native focus back")
	assert(not a:HandleKeybinding("stop_follow"), "repeated stop does not invent a new follow session")
	a.nativePartyFocusOwner = nil
	assert(a:HandleKeybinding("stop_follow") and not a.states.live.following)
end)
