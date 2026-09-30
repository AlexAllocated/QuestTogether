-- Live-safe: native hosts, unit reads and artwork are all private fixtures.
local QT = _G.QuestTogether
local function Equal(a, b)
	assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local function Fixture()
	local a = setmetatable({
		isEnabled = true,
		now = 100,
		known = true,
		friendly = true,
		player = true,
		name = "Friend-Realm",
		guid = "Player-1",
		unit = "mouseover",
		invalid = 0,
		frames = {},
		reads = 0,
	}, { __index = QT })
	local function Frame(parent, owned)
		local f = { parent = parent, owned = owned, shown = true, width = 180, bottom = 180, scale = 1, points = {} }
		function f:IsForbidden()
			return self.forbidden == true
		end
		function f:IsProtected()
			return self.protected == true
		end
		local function Check(self, write)
			if self.forbidden or (write and not self.owned) then
				a.invalid = a.invalid + 1
				error("unsafe tooltip fixture access")
			end
		end
		function f:IsShown()
			Check(self)
			return self.shown
		end
		function f:GetParent()
			Check(self)
			return self.parent
		end
		function f:GetWidth()
			Check(self)
			return self.width
		end
		function f:GetBottom()
			Check(self)
			return self.bottom
		end
		function f:GetEffectiveScale()
			Check(self)
			return self.scale
		end
		function f:GetUnit()
			Check(self)
			a.reads = a.reads + 1
			return a.name, a.unit
		end
		function f:GetStringHeight()
			Check(self)
			return a.textHeight or 28
		end
		function f:Show()
			Check(self, true)
			self.shown = true
		end
		function f:Hide()
			Check(self, true)
			self.shown = false
		end
		function f:SetWidth(v)
			Check(self, true)
			self.width = v
		end
		function f:SetScale(v)
			Check(self, true)
			self.scale = v
		end
		function f:SetSize(w, h)
			Check(self, true)
			self.width, self.height = w, h
		end
		function f:SetText(v)
			Check(self, true)
			self.text = v
		end
		function f:ClearAllPoints()
			Check(self, true)
			self.points = {}
		end
		function f:SetPoint(...)
			Check(self, true)
			self.points[#self.points + 1] = { ... }
		end
		function f:CreateTexture()
			Check(self, true)
			return Frame(self, true)
		end
		function f:CreateFontString()
			Check(self, true)
			return Frame(self, true)
		end
		for _, method in ipairs({
			"SetFrameStrata",
			"SetClampedToScreen",
			"EnableMouse",
			"SetAllPoints",
			"SetColorTexture",
			"SetTexture",
			"SetJustifyH",
			"SetWordWrap",
			"SetTexCoord",
			"SetVertexColor",
			"SetBlendMode",
		}) do
			f[method] = function(self)
				Check(self, true)
			end
		end
		return f
	end
	a.host, a.parent = Frame(nil, false), Frame(nil, false)
	a.bar = Frame(a.host, false)
	a.bar.bottom = 174
	a.API = {
		GetTime = function()
			return a.now
		end,
		UnitExists = function()
			return true
		end,
		UnitIsPlayer = function()
			return a.player
		end,
		UnitGUID = function()
			return a.guid
		end,
		UnitIsFriend = function()
			return a.friendly
		end,
		GetRealmName = function()
			return "Realm"
		end,
		RegionalUniqueNamesEnabled = function()
			return false
		end,
	}
	function a:GetPlayerTooltipHost()
		return self.host
	end
	function a:GetPlayerTooltipHealthBar()
		return self.bar
	end
	function a:GetPlayerTooltipParent()
		return self.parent
	end
	function a:CreatePlayerTooltipFrame(parent)
		local f = Frame(parent, true)
		self.frames[#self.frames + 1] = f
		return f
	end
	function a:GetUnitFullName()
		return self.name
	end
	function a:GetPlayerFullName()
		return "Me-Realm"
	end
	function a:IsIgnoredPlayerName(name)
		return name == self.ignored
	end
	function a:IsKnownQTPlayer()
		return self.known
	end
	function a:IsWorkBlocked()
		return self.blocked == true
	end
	return a
end

QT:RegisterTest("player tooltip badge matches native width and scale and clears the visible health bar", function()
	local a = Fixture()
	a.qtPlayerPresenceState = { peers = {}, questPartners = { [a.name] = { receivedAt = 100, looking = true } } }
	a.host.scale, a.bar.scale = 0.8, 0.8
	assert(a:UpdatePlayerTooltipBadge())
	local s = a.playerTooltipBadge
	Equal(s.frame.width, 180)
	Equal(s.frame.scale, 0.8)
	Equal(s.label.width, 122)
	Equal(s.frame.points[1][1], "TOPLEFT")
	Equal(s.frame.points[1][5], -10)
	assert(s.icon.qtLookingForPartners and s.label.text:find("Looking for questing partners", 1, true))
	a.host.width, a.host.scale, a.bar.scale, a.bar.bottom = 150, 1, 0.5, 340
	assert(a:UpdatePlayerTooltipBadge())
	Equal(s.frame.width, 150)
	Equal(s.frame.points[1][5], -14)
	a.bar.shown = false
	assert(a:UpdatePlayerTooltipBadge())
	Equal(s.frame.points[1][5], -4)
	Equal(a.invalid, 0)
end)

QT:RegisterTest("player tooltip badge moves above bottom-edge tooltips and wraps without widening them", function()
	local a = Fixture()
	a.host.width, a.host.bottom, a.bar.bottom, a.textHeight = 140, 35, 29, 48
	assert(a:UpdatePlayerTooltipBadge())
	local s = a.playerTooltipBadge
	Equal(s.frame.width, 140)
	Equal(s.frame.height, 68)
	Equal(s.frame.points[1][1], "BOTTOMLEFT")
	Equal(s.frame.points[1][3], "TOPLEFT")
	Equal(a.invalid, 0)
end)

QT:RegisterTest("player tooltip adds partner status only while LFG is active and hides it on expiry", function()
	local a = Fixture()
	a.qtPlayerPresenceState = { peers = {}, questPartners = { [a.name] = { receivedAt = 100, looking = true } } }
	assert(a:UpdatePlayerTooltipBadge())
	assert(a.playerTooltipBadge.icon.qtLookingForPartners)
	a.qtPlayerPresenceState.questPartners[a.name].looking = false
	assert(a:UpdatePlayerTooltipBadge())
	assert(not a.playerTooltipBadge.icon.qtLookingForPartners)
	Equal(a.playerTooltipBadge.label.text, "This player is using QuestTogether")
	a.now = 165
	assert(a:UpdatePlayerTooltipBadge())
	Equal(a.playerTooltipBadge.label.text, "This player is using QuestTogether")
	Equal(a.invalid, 0)
end)

QT:RegisterTest("player tooltips never invent QT identity for friendly strangers or NPCs", function()
	local a = Fixture()
	a.known = false
	assert(not a:UpdatePlayerTooltipBadge())
	Equal(#a.frames, 0)
	a.known = true
	assert(a:UpdatePlayerTooltipBadge())
	Equal(a.playerTooltipBadge.label.text, "This player is using QuestTogether")
	assert(not a.playerTooltipBadge.icon.qtLookingForPartners)
	a.known = false
	assert(not a:UpdatePlayerTooltipBadge())
	assert(not a.playerTooltipBadge.frame.shown)
	a.known, a.player = true, false
	assert(not a:UpdatePlayerTooltipBadge())
	Equal(a.invalid, 0)
end)

QT:RegisterTest(
	"player tooltip badge clears on reuse hide ignore disable and restricted or unreadable hosts",
	function()
		local a = Fixture()
		assert(a:UpdatePlayerTooltipBadge())
		local f = a.playerTooltipBadge.frame
		for _, key in ipairs({ "blocked", "ignored", "isEnabled", "unit", "guid" }) do
			local old = a[key]
			if key == "blocked" then
				a[key] = true
			elseif key == "ignored" then
				a[key] = a.name
			elseif key == "isEnabled" then
				a[key] = false
			else
				a[key] = nil
			end
			assert(not a:UpdatePlayerTooltipBadge())
			assert(not f.shown)
			a[key] = old
			assert(a:UpdatePlayerTooltipBadge())
		end
		a.host.forbidden = true
		local reads = a.reads
		assert(not a:UpdatePlayerTooltipBadge())
		Equal(a.reads, reads)
		assert(not f.shown)
		a.host.forbidden = false
		assert(a:UpdatePlayerTooltipBadge())
		a.host.shown = false
		assert(not a:UpdatePlayerTooltipBadge())
		assert(not f.shown)
		a.host.shown = true
		assert(a:UpdatePlayerTooltipBadge())
		a.bar.forbidden = true
		assert(not a:UpdatePlayerTooltipBadge())
		assert(not f.shown)
		Equal(a.invalid, 0)
	end
)
