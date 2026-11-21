-- SPDX-License-Identifier: GPL-3.0-only
-- Plate presentation consumes player-presence evidence.
local QT = _G.QuestTogether

function QT:ShouldShowQTPlayerLogoForName(name)
	name = self:NormalizeMemberName(name)
	return self.isEnabled == true
		and name ~= nil
		and not self:IsSelfSender(name)
		and not self:IsIgnoredPlayerName(name)
		and self:IsKnownQTPlayer(name)
end

function QT:IsFriendlyQTPlayerUnit(unitToken)
	if
		not self:IsNameplateUnitToken(unitToken)
		or not self:DoesNameplateUnitExist(unitToken)
		or not self:IsNameplateUnitPlayer(unitToken)
	then
		return false
	end
	local ok, friendly = pcall(self.API.UnitIsFriend, "player", unitToken)
	if not ok or not self:CanAccessValue(friendly) or friendly ~= true then
		return false
	end
	local name = self:NormalizeMemberName(self:GetUnitFullName(unitToken))
	return self:ShouldShowQTPlayerLogoForName(name), name
end
