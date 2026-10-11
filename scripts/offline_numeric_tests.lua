-- Offline only: deliberately excluded from the TOC and in-game test totals.
-- WoW's arithmetic can reject zero division instead of producing a NaN.
return function(addon)
	local nan = 0 / 0
	assert(nan ~= nan, "offline interpreter must supply a real NaN; never skip numeric rejection coverage")
	assert(addon:SafeToNumber(nan) == nil)
	assert(addon.LibChev.Number(nan) == nil)
	assert(addon:EncodeCommRecord("LOC", { mask = nan }) == nil)
	assert(addon:EncodeCommRecord("STATE", {
		records = { { topic = "QTPR", data = { active = true }, revision = nan } },
	}) == nil)
	local scale, x, y = addon:FitWindowGeometry(nan, nan, nan, nan, nan, nan, nan)
	assert(scale == 1 and x == 0.5 and y == 0.5, "NaN geometry must use finite defaults")

	-- Exercise actual saved-layout restoration with private regions, not only
	-- the shared numeric guard. No live window, parent, or addon state is changed.
	local frame = { width = 1250, height = 720 }
	function frame:IsForbidden()
		return false
	end
	function frame:IsProtected()
		return false
	end
	function frame:GetWidth()
		return self.width
	end
	function frame:GetHeight()
		return self.height
	end
	function frame:SetSize(width, height)
		self.width, self.height = width, height
	end
	function frame:SetScale(value)
		self.scale = value
	end
	function frame:ClearAllPoints() end
	function frame:SetPoint(_, _, _, px, py)
		self.x, self.y = px, py
	end
	function frame:SetClampedToScreen(value)
		self.clamped = value
	end
	local root = {
		GetWidth = function()
			return 3440
		end,
		GetHeight = function()
			return 1440
		end,
	}
	local fixture = setmetatable({
		db = {
			profile = {
				windowScale = 100,
				windowLayouts = { log = { width = nan, height = nan, x = nan, y = nan } },
			},
		},
		managedWindows = {},
	}, { __index = addon })
	function fixture:IsWorkBlocked()
		return false
	end
	function fixture:CanAccessForeignFrame()
		return true
	end
	function fixture:GetOwnedUIParent()
		return root
	end
	fixture.managedWindows[frame] = {
		key = "log",
		width = 1250,
		height = 720,
		minWidth = 700,
		minHeight = 500,
		profile = fixture.db.profile,
	}
	assert(fixture:ApplyWindowLayout(frame, true))
	assert(frame.width == 1250 and frame.height == 720, "NaN saved sizes must use registered dimensions")
	assert(frame.scale == 1 and frame.x == 1720 and frame.y == 720 and frame.clamped)
	print("Offline-only NaN codec and window-restoration checks passed.")
end
