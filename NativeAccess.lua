-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether

local raw_tostring = tostring
local raw_string_match = string.match
local raw_string_find = string.find
local raw_issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil
local raw_canaccessvalue = type(canaccessvalue) == "function" and canaccessvalue or nil
local raw_canaccesstable = type(canaccesstable) == "function" and canaccesstable or nil

local Access = {}
QuestTogether.NativeAccess = Access
local function CanAccessForeignValue(rawValue)
	if raw_canaccessvalue then
		local ok, canAccess = pcall(raw_canaccessvalue, rawValue)
		if not ok or not canAccess then
			return false
		end
	end
	if QuestTogether and QuestTogether.IsSecretValue and QuestTogether:IsSecretValue(rawValue) then
		return false
	end
	return true
end

local function CanAccessForeignTable(rawTable)
	if type(rawTable) ~= "table" then
		return false
	end
	if raw_canaccesstable then
		local ok, canAccess = pcall(raw_canaccesstable, rawTable)
		if not ok or not canAccess then
			return false
		end
	end
	return CanAccessForeignValue(rawTable)
end

Access.Value, Access.Table = CanAccessForeignValue, CanAccessForeignTable
function QuestTogether:IsSecretValue(value)
	if not raw_issecretvalue then
		return false
	end

	local ok, isSecret = pcall(raw_issecretvalue, value)
	return not ok or (isSecret and true or false)
end

function QuestTogether:CanAccessValue(value)
	return Access.Value(value)
end

function QuestTogether:CanAccessTable(tableValue)
	return Access.Table(tableValue)
end

local function ReadForeignFrameMethod(frame, memberName)
	local ok, method = pcall(function()
		return frame[memberName]
	end)
	if not ok or not CanAccessForeignValue(method) then
		return nil, false
	end
	return method, true
end

function QuestTogether:IsForbiddenFrame(frame)
	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false
	end
	if not CanAccessForeignValue(frame) or (frameType == "table" and not CanAccessForeignTable(frame)) then
		return true
	end
	local method, readable = ReadForeignFrameMethod(frame, "IsForbidden")
	if not readable then
		return true
	end
	if type(method) ~= "function" then
		return false
	end

	local ok, forbidden = pcall(method, frame)
	return not ok or not CanAccessForeignValue(forbidden) or forbidden == true
end

function QuestTogether:IsProtectedFrame(frame)
	if not self:CanAccessValue(frame) then
		return true, false
	end

	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false, false
	end
	if self:IsForbiddenFrame(frame) then
		return true, false
	end
	local method, readable = ReadForeignFrameMethod(frame, "IsProtected")
	if not readable then
		return true, false
	end
	if type(method) ~= "function" then
		return false, false
	end

	local ok, isProtected, isProtectedExplicitly = pcall(method, frame)
	if not ok or not CanAccessForeignValue(isProtected) or not CanAccessForeignValue(isProtectedExplicitly) then
		return true, false
	end
	return isProtected and true or false, isProtectedExplicitly and true or false
end

function QuestTogether:CanAccessForeignFrame(frame, requireShown)
	local frameType = type(frame)
	if not frame or (frameType ~= "table" and frameType ~= "userdata") then
		return false
	end
	if not CanAccessForeignValue(frame) then
		return false
	end
	if self:IsForbiddenFrame(frame) then
		return false
	end

	if requireShown then
		local method, readable = ReadForeignFrameMethod(frame, "IsShown")
		if not readable or type(method) ~= "function" then
			return false
		end
		local okShown, isShown = pcall(method, frame)
		if not okShown or not CanAccessForeignValue(isShown) or not isShown then
			return false
		end
	end

	return true
end

function QuestTogether:GetAccessibleFrameMember(frame, memberName)
	if not self:CanAccessForeignFrame(frame) or type(memberName) ~= "string" or memberName == "" then
		return nil, false
	end

	local ok, value = pcall(function()
		return frame[memberName]
	end)
	if not ok or not self:CanAccessValue(value) then
		return nil, false
	end
	return value, true
end

function QuestTogether:TryAddMessageToChatFrame(chatFrame, message)
	if not self:CanAccessForeignFrame(chatFrame) or type(chatFrame.AddMessage) ~= "function" then
		return false
	end

	local ok = pcall(chatFrame.AddMessage, chatFrame, self:SafeToString(message, ""))
	return ok and true or false
end

function QuestTogether:SafeToNumber(value)
	if not self:CanAccessValue(value) then
		return nil
	end

	local valueType = type(value)
	if valueType == "number" then
		-- Reject NaN/inf to keep downstream math safe and deterministic.
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return value
	end

	if valueType ~= "string" then
		return nil
	end

	local trimmedValue = self:SafeTrimString(value, "")
	if trimmedValue == "" then
		return nil
	end

	local numericValue = tonumber(trimmedValue)
	if type(numericValue) ~= "number" then
		return nil
	end

	if numericValue ~= numericValue or numericValue == math.huge or numericValue == -math.huge then
		return nil
	end

	return numericValue
end

function QuestTogether:NormalizeQuestID(questId)
	local numericQuestId = self:SafeToNumber(questId)
	if not numericQuestId or numericQuestId <= 0 then
		return nil
	end

	return math.floor(numericQuestId + 0.5)
end

function QuestTogether:SafeToString(value, fallback)
	if not self:CanAccessValue(value) then
		if fallback ~= nil then
			return fallback
		end
		return "<secret>"
	end

	local valueType = type(value)
	if valueType == "string" then
		return value
	end
	if valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return raw_tostring(value)
	end

	-- String coercion is intentionally shielded so debug/log paths never trigger taint errors.
	local ok, stringValue = pcall(raw_tostring, value)
	if ok then
		return stringValue
	end

	if fallback ~= nil then
		return fallback
	end
	return "<secret>"
end

function QuestTogether:SafeTrimString(value, fallback)
	local fallbackValue = fallback or ""
	if type(value) ~= "string" or not self:CanAccessValue(value) then
		return fallbackValue
	end

	local trimmedValue = string.match(value, "^%s*(.-)%s*$")
	if type(trimmedValue) ~= "string" or not self:CanAccessValue(trimmedValue) then
		return fallbackValue
	end
	return trimmedValue
end

function QuestTogether:SafeStripWhitespace(value, fallback)
	local fallbackValue = fallback or ""
	if type(value) ~= "string" or not self:CanAccessValue(value) then
		return fallbackValue
	end

	local stripped = string.gsub(value, "%s+", "")
	if type(stripped) ~= "string" or not self:CanAccessValue(stripped) then
		return fallbackValue
	end
	return stripped
end

-- Deep copy helper used for defaults merging and tests.
function QuestTogether:DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, nestedValue in pairs(value) do
		copy[key] = self:DeepCopy(nestedValue)
	end
	return copy
end

local function SafeText(value, fallback)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, fallback ~= nil and fallback or "<secret>")
	end

	local ok, textValue = pcall(raw_tostring, value)
	if ok then
		return textValue
	end

	if fallback ~= nil then
		return fallback
	end
	return "<secret>"
end

local function SafeMatch(text, pattern)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, first, second, third, fourth = pcall(raw_string_match, safeText, pattern)
	if not ok then
		return nil
	end

	return first, second, third, fourth
end

local function SafeFind(text, pattern, init, plain)
	local safeText = SafeText(text, "")
	if safeText == "" then
		return nil
	end

	local ok, firstIndex, secondIndex = pcall(raw_string_find, safeText, pattern, init, plain)
	if not ok then
		return nil
	end

	return firstIndex, secondIndex
end

local tostring = SafeText

Access.Text, Access.Match, Access.Find = SafeText, SafeMatch, SafeFind

-- Reading a member proves neither mutation permission nor a secure delegate.
function Access.Read(object, key)
	if not Access.Value(object) then
		return nil, false
	end
	local kind = type(object)
	if kind ~= "table" and kind ~= "userdata" then
		return nil, false
	end
	if kind == "table" and not Access.Table(object) then
		return nil, false
	end
	local ok, value = pcall(function()
		return object[key]
	end)
	if not ok or not Access.Value(value) then
		return nil, false
	end
	return value, true
end
function Access.Methods(object, names)
	for _, name in ipairs(names) do
		if type(Access.Read(object, name)) ~= "function" then
			return false
		end
	end
	return true
end
function Access.Trusted(object, name)
	local method = Access.Read(object, name)
	if type(method) ~= "function" or type(issecurevariable) ~= "function" then
		return nil
	end
	local ok, secure = pcall(issecurevariable, object, name)
	return ok and Access.Value(secure) and secure == true and method or nil
end

-- Merge defaults into destination recursively without deleting existing values.
function QuestTogether:ApplyDefaults(destination, defaults)
	for key, defaultValue in pairs(defaults) do
		if destination[key] == nil then
			destination[key] = self:DeepCopy(defaultValue)
		elseif type(destination[key]) == "table" and type(defaultValue) == "table" then
			self:ApplyDefaults(destination[key], defaultValue)
		end
	end
end

function Access.Call(object, name, ...)
	local getter = Access.Read(object, name)
	if type(getter) ~= "function" then
		return nil
	end
	local ok, value = pcall(getter, ...)
	if ok and Access.Value(value) then
		return value
	end
end
