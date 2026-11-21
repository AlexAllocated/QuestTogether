-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether

function QuestTogether:GetPersonalBubbleAnchorKey()
	if self:UsesRegionalPlayerNames() then
		return self:GetCurrentCharacterKey()
	end
	if self.GetPlayerFullName then
		local fullName = self:GetPlayerFullName()
		if fullName and fullName ~= "" then
			return fullName
		end
	end

	local playerName = self:GetPlayerName()
	if playerName and playerName ~= "" then
		return playerName
	end

	return "player"
end

function QuestTogether:GetPersonalBubbleAnchorStore()
	if not self.db or not self.db.global then
		return nil
	end

	if type(self.db.global.personalBubbleAnchors) ~= "table" then
		self.db.global.personalBubbleAnchors = {}
	end

	return self.db.global.personalBubbleAnchors
end

function QuestTogether:GetPersonalBubbleAnchor()
	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local anchor = {
		point = defaults.point,
		relativePoint = defaults.relativePoint,
		x = defaults.x,
		y = defaults.y,
	}

	local store = self:GetPersonalBubbleAnchorStore()
	local key = self:GetPersonalBubbleAnchorKey()
	local saved = store and store[key] or nil
	if type(saved) ~= "table" then
		return anchor
	end

	if type(saved.point) == "string" and saved.point ~= "" then
		anchor.point = saved.point
	end
	if type(saved.relativePoint) == "string" and saved.relativePoint ~= "" then
		anchor.relativePoint = saved.relativePoint
	end
	local numericX = self:SafeToNumber(saved.x)
	if numericX ~= nil then
		anchor.x = numericX
	end
	local numericY = self:SafeToNumber(saved.y)
	if numericY ~= nil then
		anchor.y = numericY
	end

	return anchor
end

function QuestTogether:SetPersonalBubbleAnchor(point, relativePoint, offsetX, offsetY)
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	local defaults = self.DEFAULT_PERSONAL_BUBBLE_ANCHOR
	local numericOffsetX = self:SafeToNumber(offsetX)
	local numericOffsetY = self:SafeToNumber(offsetY)
	store[self:GetPersonalBubbleAnchorKey()] = {
		point = type(point) == "string" and point ~= "" and point or defaults.point,
		relativePoint = type(relativePoint) == "string" and relativePoint ~= "" and relativePoint
			or defaults.relativePoint,
		x = numericOffsetX ~= nil and numericOffsetX or defaults.x,
		y = numericOffsetY ~= nil and numericOffsetY or defaults.y,
	}

	if self.ApplySavedPersonalBubbleAnchor then
		self:ApplySavedPersonalBubbleAnchor()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	return true
end

function QuestTogether:ResetPersonalBubbleAnchor()
	local store = self:GetPersonalBubbleAnchorStore()
	if not store then
		return false
	end

	store[self:GetPersonalBubbleAnchorKey()] = nil
	if self.ApplySavedPersonalBubbleAnchor then
		self:ApplySavedPersonalBubbleAnchor()
	end
	if self.RefreshPersonalBubbleAnchorVisualState then
		self:RefreshPersonalBubbleAnchorVisualState()
	end
	return true
end
