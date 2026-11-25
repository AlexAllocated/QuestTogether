-- SPDX-License-Identifier: GPL-3.0-only
-- Explicit local loot observations only; bag moves and login never create events.
local QT = _G.QuestTogether
local L = QT.Translate
local LIMIT, LIFETIME, INTERVAL = 16, 10, 0.5
local function Count(rows)
	local n = 0
	for _ in pairs(rows) do n = n + 1 end
	return n
end
function QT:ResetQuestStarterItems()
	self.questStarterItems = nil
end
function QT:CHAT_MSG_LOOT(_, text, _, _, _, _, _, _, _, _, _, _, guid)
	if not self.isEnabled or self.isLoggingOut or self.isLeavingWorld then return end
	local id = self.API.ReadQuestStarterLoot(text, guid)
	if not id then return end
	local now = self.API.GetTime()
	local state = self.questStarterItems
	if not state or state.profile ~= self.db.profile then
		state = { profile = self.db.profile, pending = {}, seen = {}, nextRead = now }
		self.questStarterItems = state
	end
	for item, expiry in pairs(state.seen) do if now >= expiry then state.seen[item] = nil end end
	if state.seen[id] or state.pending[id] or Count(state.pending) >= LIMIT or Count(state.seen) >= 64 then return end
	state.pending[id] = now + LIFETIME
	state.seen[id] = now + 30
	self.API.RequestQuestStarterItem(id)
end
function QT:UpdateQuestStarterItems()
	local state = self.questStarterItems
	if not state then return end
	if not self.isEnabled or self.isLoggingOut or self.isLeavingWorld or state.profile ~= self.db.profile then
		self:ResetQuestStarterItems()
		return
	end
	local now = self.API.GetTime()
	for id, expiry in pairs(state.pending) do if now >= expiry then state.pending[id] = nil end end
	for id, expiry in pairs(state.seen) do if now >= expiry then state.seen[id] = nil end end
	if not next(state.pending) or now < state.nextRead then return end
	state.nextRead = now + INTERVAL
	local rows = self.API.ReadQuestStarterItems(state.pending)
	if not rows or self.questStarterItems ~= state or state.profile ~= self.db.profile then return end
	for id, row in pairs(rows) do
		if self.questStarterItems ~= state or state.profile ~= self.db.profile
			or not self.isEnabled or self.isLoggingOut or self.isLeavingWorld then return end
		if state.pending[id] then
			state.pending[id] = nil
			if row then
				self:PublishAnnouncementEvent("QUEST_STARTER_FOUND", L("Quest-starting item found: ") .. row.name,
					row.questID, { iconAsset = row.icon, iconKind = "texture",
						eventFacts = self:BuildAnnouncementFacts("QUEST_STARTER_FOUND", id) })
			end
		end
	end
end
