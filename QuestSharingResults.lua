local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local RESULT_LIFETIME = 60

local function EscapePattern(text)
	return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- A native result names a player, not a quest. Never use timing to attach it to
-- an individual QT request: a different addon or the quest log can share too.
local function ResultPattern(format)
	local parts, index, captures = { "^" }, 1, 0
	while index <= #format do
		local marker = format:find("%", index, true)
		if not marker then
			parts[#parts + 1] = EscapePattern(format:sub(index))
			break
		end
		parts[#parts + 1] = EscapePattern(format:sub(index, marker - 1))
		if format:sub(marker, marker + 1) == "%%" then
			parts[#parts + 1], index = "%%", marker + 2
		elseif format:sub(marker, marker + 1) == "%s" or format:sub(marker, marker + 3) == "%1$s" then
			captures = captures + 1
			parts[#parts + 1] = "(.+)"
			index = marker + (format:sub(marker, marker + 1) == "%s" and 2 or 4)
		else
			return nil
		end
	end
	parts[#parts + 1] = "$"
	return captures == 1 and table.concat(parts) or nil
end

function QuestTogether:FindQuestShareResultPlayer(value)
	local text = self:NormalizeQuestDisplayTitleText(value)
	if #text > 120 or text == "" then
		return nil
	end
	text = text:match("^%[([^%[%]]+)%]$") or text
	local normalized = self:NormalizeMemberName(text)
	local match
	for name in pairs(self.partyMembers or {}) do
		if not self:IsSelfSender(name) then
			if text:find("-", 1, true) and name == normalized then
				return not self:IsIgnoredPlayerName(name) and name or nil
			end
			if not text:find("-", 1, true) and name:match("^([^-]+)") == text then
				if match then
					return nil
				end
				match = name
			end
		end
	end
	return match and not self:IsIgnoredPlayerName(match) and match or nil
end

function QuestTogether:HandleQuestShareSystemMessage(message)
	if not self.isEnabled or self.isLoggingOut or not self:CanAccessValue(message)
		or type(message) ~= "string" or #message > 1024 then
		return false
	end
	local getter = self.API.GetQuestShareResultFormats
	if type(getter) ~= "function" then
		return false
	end
	local ok, formats = pcall(getter)
	if not ok or type(formats) ~= "table" or not self:CanAccessTable(formats) then
		return false
	end
	local foundName, foundCode
	local examined = 0
	for code, format in pairs(formats) do
		examined = examined + 1
		if examined > 32 then
			return false
		end
		if self:CanAccessValue(format) and type(format) == "string" and #format <= 512 then
			local pattern = ResultPattern(format)
			local captured = pattern and message:match(pattern)
			local name = captured and self:FindQuestShareResultPlayer(captured)
			if name then
				if foundName and (foundName ~= name or foundCode ~= code) then
					return false
				end
				foundName, foundCode = name, code
			end
		end
	end
	if not foundName then
		return false
	end
	local text = self:NormalizeQuestDisplayTitleText(message)
	if text == "" then
		return false
	end
	local now, retained = self.API.GetTime(), 0
	local results = rawget(self, "questShareNativeResults") or {}
	self.questShareNativeResults = results
	for name, result in pairs(results) do
		if now < result.at or now >= result.at + RESULT_LIFETIME or not self:IsGroupedSender(name)
			or self:IsIgnoredPlayerName(name) then
			results[name] = nil
		else
			retained = retained + 1
		end
	end
	if retained >= 40 and not results[foundName] then
		return false
	end
	results[foundName] = { text = text, code = foundCode, at = now }
	if rawget(self, "partyQuestCompareSession") then
		self:QueuePartyQuestCompareRender()
	end
	return true
end

function QuestTogether:GetLatestQuestShareResultText(name)
	local results = rawget(self, "questShareNativeResults")
	local result = results and results[name]
	if not result then
		return nil
	end
	local now = self.API.GetTime()
	if not self.isEnabled or self.isLoggingOut or now < result.at or now >= result.at + RESULT_LIFETIME
		or not self:IsGroupedSender(name) or self:IsIgnoredPlayerName(name) then
		results[name] = nil
		return nil
	end
	return string.format(L("Latest share result: %s"), result.text)
end
