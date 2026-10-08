local QT = _G.QuestTogether
local L = QT.Translate

local function Native(addon, fn, ...)
	if not addon:CanAccessValue(fn) or type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
end

local function Foreign(addon, frame, method, ...)
	return Native(addon, addon:GetAccessibleFrameMember(frame, method), frame, ...)
end

local function Owned(addon, frame, method, ...)
	if not addon.LibChev.CanMutateOwnedRegion(frame) then
		return nil
	end
	return Foreign(addon, frame, method, ...)
end

function QT:GetPlayerTooltipHost()
	return GameTooltip
end

function QT:GetPlayerTooltipHealthBar()
	return GameTooltipStatusBar
end

function QT:GetPlayerTooltipParent()
	return UIParent
end

function QT:CreatePlayerTooltipFrame(parent)
	return CreateFrame("Frame", nil, parent)
end

-- Only read the public unit accessor. Never hook, append lines to, parent under,
-- or store state on Blizzard's tooltip. Polling also covers refreshed unit frames
-- and both legacy and modern tooltip pipelines without replacing their scripts.
function QT:ReadPlayerTooltipUnit()
	if not self.isEnabled or self.isLoggingOut or self:IsWorkBlocked("nameplate_refresh") then
		return nil
	end
	local host = self:GetPlayerTooltipHost()
	if not self:CanAccessForeignFrame(host, true) then
		return nil
	end
	local _, unit = Foreign(self, host, "GetUnit")
	if not self:CanAccessValue(unit) or type(unit) ~= "string" or #unit > 40 or not unit:match("^[%a%d]+$") then
		return nil
	end
	local exists = Native(self, self.API.UnitExists, unit)
	local player = Native(self, self.API.UnitIsPlayer, unit)
	if not self:CanAccessValue(exists) or exists ~= true or not self:CanAccessValue(player) or player ~= true then
		return nil
	end
	local guid = self:SafeTrimString(Native(self, self.API.UnitGUID, unit), "")
	local name = self:NormalizeMemberName(self:GetUnitFullName(unit))
	if guid == "" or not name or self:IsIgnoredPlayerName(name) then
		return nil
	end
	if not self:IsSelfSender(name) and not self:IsKnownQTPlayer(name) then
		return nil
	end
	local looking = self:IsPlayerLookingForQuestPartners(name) == true
	return { host = host, unit = unit, guid = guid, name = name, looking = looking }
end

function QT:HidePlayerTooltipBadge()
	local state = rawget(self, "playerTooltipBadge")
	if not state then
		return
	end
	-- Its UIParent-owned host remains hideable even if GameTooltip is forbidden.
	self:SetQTPlayerIconLookingForPartners(state.icon, false)
	self:HideOwnedUI(state.frame)
	state.name, state.guid = nil, nil
end

function QT:UpdatePlayerTooltipBadge()
	local row = self:ReadPlayerTooltipUnit()
	if not row then
		self:HidePlayerTooltipBadge()
		return false
	end
	local state = rawget(self, "playerTooltipBadge")
	if not state then
		local parent = self:GetPlayerTooltipParent()
		if not self:CanAccessForeignFrame(parent) then
			return false
		end
		local frame = self:CreatePlayerTooltipFrame(parent)
		if not self.LibChev.CanMutateOwnedRegion(frame) then
			return false
		end
		state = { frame = frame, parent = parent }
		self.playerTooltipBadge = state
		Owned(self, frame, "Hide")
		Owned(self, frame, "SetFrameStrata", "TOOLTIP")
		Owned(self, frame, "SetClampedToScreen", true)
		Owned(self, frame, "EnableMouse", false)
		local background = Owned(self, frame, "CreateTexture", nil, "BACKGROUND")
		Owned(self, background, "SetAllPoints")
		Owned(self, background, "SetColorTexture", 0.035, 0.035, 0.045, 0.97)
		state.icon = self:CreatePlayerTooltipFrame(frame)
		Owned(self, state.icon, "SetSize", 26, 26)
		Owned(self, state.icon, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 10, -10)
		local logo = Owned(self, state.icon, "CreateTexture", nil, "ARTWORK")
		Owned(self, logo, "SetAllPoints")
		Owned(self, logo, "SetTexture", self.NAMEPLATE_PLAYER_ICON_TEXTURE)
		state.label = Owned(self, frame, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
		Owned(self, state.label, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 46, -10)
		Owned(self, state.label, "SetJustifyH", "LEFT")
		Owned(self, state.label, "SetWordWrap", true)
	end
	if
		not self.LibChev.CanMutateOwnedRegion(state.frame)
		or not self.LibChev.CanMutateOwnedRegion(state.icon)
		or not self.LibChev.CanMutateOwnedRegion(state.label)
	then
		self:HidePlayerTooltipBadge()
		return false
	end
	local width = self:SafeToNumber(Foreign(self, row.host, "GetWidth"))
	local bottom = self:SafeToNumber(Foreign(self, row.host, "GetBottom"))
	local scale = self:SafeToNumber(Foreign(self, row.host, "GetEffectiveScale"))
	local parentScale = self:SafeToNumber(Foreign(self, state.parent, "GetEffectiveScale"))
	if not width or not bottom or width <= 64 or not scale or scale <= 0 or not parentScale or parentScale <= 0 then
		self:HidePlayerTooltipBadge()
		return false
	end
	-- Match the tooltip's effective width even when it uses a custom UI scale.
	Owned(self, state.frame, "SetScale", scale / parentScale)
	local gap = 4
	local bar = self:GetPlayerTooltipHealthBar()
	if not self:CanAccessValue(bar) then
		self:HidePlayerTooltipBadge()
		return false
	end
	if bar ~= nil then
		if not self:CanAccessForeignFrame(bar) then
			self:HidePlayerTooltipBadge()
			return false
		end
		local shown = Foreign(self, bar, "IsShown")
		if not self:CanAccessValue(shown) then
			self:HidePlayerTooltipBadge()
			return false
		end
		if shown == true then
			local barParent = Foreign(self, bar, "GetParent")
			if not self:CanAccessValue(barParent) then
				self:HidePlayerTooltipBadge()
				return false
			end
			if barParent == row.host then
				local barBottom = self:SafeToNumber(Foreign(self, bar, "GetBottom"))
				local barScale = self:SafeToNumber(Foreign(self, bar, "GetEffectiveScale"))
				if not barBottom or not barScale or barScale <= 0 then
					self:HidePlayerTooltipBadge()
					return false
				end
				gap = math.max(gap, bottom - barBottom * barScale / scale + 4)
			end
		end
	end
	local text = L("This player is using QuestTogether")
	if row.looking then
		text = text .. "\n|cffffd34d" .. L("Looking for questing partners") .. "|r"
	end
	Owned(self, state.label, "SetWidth", width - 58)
	Owned(self, state.label, "SetText", text)
	local height = self:SafeToNumber(Owned(self, state.label, "GetStringHeight"))
	if not height then
		self:HidePlayerTooltipBadge()
		return false
	end
	height = math.max(46, height + 20)
	Owned(self, state.frame, "SetSize", width, height)
	Owned(self, state.frame, "ClearAllPoints")
	-- Put the section above a bottom-edge tooltip instead of covering its text.
	if bottom < height + gap then
		Owned(self, state.frame, "SetPoint", "BOTTOMLEFT", row.host, "TOPLEFT", 0, 2)
	else
		Owned(self, state.frame, "SetPoint", "TOPLEFT", row.host, "BOTTOMLEFT", 0, -gap)
	end
	if not self:SetQTPlayerIconLookingForPartners(state.icon, row.looking) then
		self:HidePlayerTooltipBadge()
		return false
	end
	state.name, state.guid = row.name, row.guid
	self:CancelOwnedUICleanup(state.frame)
	Owned(self, state.frame, "Show")
	return true
end
