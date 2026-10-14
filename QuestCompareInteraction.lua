-- Presentation-only state: narrowing a column never changes the roster or
-- the snapshots used to compare, share, or calculate party progress.
local QT = _G.QuestTogether
local FULL_WIDTH, COMPACT_WIDTH = 130, 64

function QT:GetPartyQuestCompareColumns(session)
	local columns, retained, width = {}, {}, 0
	for index, member in ipairs(session and session.members or {}) do
		local collapsed = session.collapsedPlayers and session.collapsedPlayers[member.name] == true
		local size = collapsed and COMPACT_WIDTH or FULL_WIDTH
		columns[index] = { left = 346 + width, width = size - 4, collapsed = collapsed }
		if collapsed then retained[member.name] = true end
		width = width + size
	end
	if session then session.collapsedPlayers = retained end
	return columns, width
end

function QT:SetPartyQuestColumnCollapsed(name, collapsed, expectedSession)
	local session = self.partyQuestCompareSession
	if not session or (expectedSession and session ~= expectedSession)
		or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	local found = false
	for _, member in ipairs(session.members) do
		if member.name == name then found = true; break end
	end
	if not found then return false end
	session.collapsedPlayers = session.collapsedPlayers or {}
	session.collapsedPlayers[name] = collapsed == true or nil
	self:QueuePartyQuestCompareRender()
	return true
end

function QT:RestorePartyQuestColumns(expectedSession)
	local session = self.partyQuestCompareSession
	if not session or (expectedSession and session ~= expectedSession)
		or self:IsWorkBlocked("foreign_frame_mutation") then return false end
	session.collapsedPlayers = {}
	self:QueuePartyQuestCompareRender()
	return true
end

-- Roots and their current pixel positions come from the window's existing
-- layout pass, including animated detail heights. No second geometry model.
function QT:GetPartyQuestKeyboardTarget(rows, questID, key, pageHeight)
	if not rows or #rows == 0 then return nil end
	local index = 1
	for i, row in ipairs(rows) do
		if row.questId == questID then index = i; break end
	end
	if key == "HOME" then index = 1
	elseif key == "END" then index = #rows
	elseif key == "UP" then index = math.max(1, index - 1)
	elseif key == "DOWN" then index = math.min(#rows, index + 1)
	elseif key == "PAGEUP" or key == "PAGEDOWN" then
		local direction = key == "PAGEUP" and -1 or 1
		local target = rows[index].top + direction * math.max(42, pageHeight or 42)
		local nextIndex = math.max(1, math.min(#rows, index + direction))
		while nextIndex > 1 and nextIndex < #rows
			and ((direction > 0 and rows[nextIndex].top < target)
				or (direction < 0 and rows[nextIndex].top > target)) do
			nextIndex = nextIndex + direction
		end
		index = nextIndex
	end
	return rows[index]
end
