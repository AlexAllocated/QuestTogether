-- SPDX-License-Identifier: GPL-3.0-only
local QT = _G.QuestTogether

-- Match only Blizzard's self-loot formats when a native sender GUID is absent.
local function LootPattern(format)
	if type(format) ~= "string" or #format > 512 then return end
	local parts, pos = { "^" }, 1
	while pos <= #format do
		local char = format:sub(pos, pos)
		if char == "%" then
			local token, length = format:sub(pos):match("^%%[1-9]%$([sd])()")
			if not token then token, length = format:sub(pos):match("^%%([sd%%])()") end
			if not token then return end
			parts[#parts + 1] = token == "s" and ".+" or token == "d" and "%d+" or "%%"
			pos = pos + length - 1
		else
			parts[#parts + 1] = char:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
			pos = pos + 1
		end
	end
	return table.concat(parts) .. "$"
end
function QT:CreateQuestStarterNativeAdapter(native)
	local addon = self
	local function Read(fn, ...)
		if type(fn) ~= "function" then return end
		local ok, value = pcall(fn, ...)
		if ok and addon:CanAccessValue(value) then return value end
	end
	local function Ready()
		return addon.isEnabled and not addon.isLoggingOut and not addon.isLeavingWorld
			and not addon.isRunningTests and not addon.suppressLocalAnnouncementDisplayDuringTests
	end
	local function Integer(value, maximum)
		if not addon:CanAccessValue(value) or type(value) ~= "number" then return end
		if value >= 1 and value <= maximum and value == math.floor(value) then return value end
	end
	local function ItemName(id)
		if not Ready() then return end
		local name = Read(native.GetItemNameByID, id)
		if type(name) == "string" and #name > 0 and #name <= 512 and not name:find("[|%c]") then return name end
	end
	local function Loot(text, guid)
		if not Ready() or not addon:CanAccessValue(text) or type(text) ~= "string" or #text > 2048
			or not addon:CanAccessValue(guid) then return end
		local id = Integer(tonumber(text:match("|Hitem:(%d+):")), 1000000000)
		if not id then return end
		if guid ~= nil and guid ~= "" then
			local own = Read(native.UnitGUID, "player")
			return type(own) == "string" and own ~= "" and guid == own and id or nil
		end
		for _, format in ipairs(native.selfLootFormats) do
			local pattern = LootPattern(format)
			if pattern and text:match(pattern) then return id end
		end
	end
	local function Items(wanted)
		if not Ready() then return end
		local rows = {}
		-- Equipped bags only. Never scan bank, mail, equipment or account storage.
		for bag = 0, native.lastBag do
			local slots = Read(native.GetContainerNumSlots, bag)
			if type(slots) ~= "number" or slots < 0 or slots > 160 or slots ~= math.floor(slots) then return end
			for slot = 1, slots do
				local id = Integer(Read(native.GetContainerItemID, bag, slot), 1000000000)
				if id and wanted[id] and rows[id] == nil and Read(native.IsItemDataCachedByID, id) == true then
					local info = Read(native.GetContainerItemQuestInfo, bag, slot)
					if addon:CanAccessTable(info) and type(info) == "table" then
						local questID = Integer(info.questID, 1000000000)
						if addon:CanAccessValue(info.isActive) and addon:CanAccessValue(info.questID) then
							if questID and info.isActive == false then
								local name = ItemName(id)
								if name then rows[id] = { questID = questID, name = name,
									icon = Integer(Read(native.GetItemIconByID, id), 1000000000) } end
							elseif info.questID == nil or info.isActive == true then rows[id] = false end
						end
					end
				end
			end
		end
		return rows
	end
	return {
		ReadQuestStarterLoot = function(...)
			local ok, id = pcall(Loot, ...)
			return ok and id or nil
		end,
		ReadQuestStarterItems = function(wanted)
			local ok, rows = pcall(Items, wanted)
			return ok and rows or nil
		end,
		GetQuestStarterItemName = ItemName,
		RequestQuestStarterItem = function(id)
			if Ready() then Read(native.RequestLoadItemDataByID, id) end
		end,
	}
end
local function Capability(namespace, key)
	if not QT:CanAccessTable(namespace) then return end
	local ok, fn = pcall(function() return namespace[key] end)
	if ok and QT:CanAccessValue(fn) and type(fn) == "function" then return fn end
end
local formats = {}
for _, key in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
	if type(_G[key]) == "string" then formats[#formats + 1] = _G[key] end
end
local lastBag = type(NUM_TOTAL_EQUIPPED_BAG_SLOTS) == "number" and NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4
lastBag = math.min(5, math.max(4, lastBag))
local adapter = QT:CreateQuestStarterNativeAdapter({
	UnitGUID = UnitGUID, selfLootFormats = formats, lastBag = lastBag,
	GetContainerNumSlots = Capability(C_Container, "GetContainerNumSlots"),
	GetContainerItemID = Capability(C_Container, "GetContainerItemID"),
	GetContainerItemQuestInfo = Capability(C_Container, "GetContainerItemQuestInfo"),
	IsItemDataCachedByID = Capability(C_Item, "IsItemDataCachedByID"),
	GetItemNameByID = Capability(C_Item, "GetItemNameByID"),
	GetItemIconByID = Capability(C_Item, "GetItemIconByID"),
	RequestLoadItemDataByID = Capability(C_Item, "RequestLoadItemDataByID"),
})
for key, fn in pairs(adapter) do QT.API[key] = fn end
