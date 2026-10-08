local L = _G.QuestTogether.Translate
--[[
QuestTogether Announcement Communication Layer

This file handles lightweight announcement events over a shared addon channel.
Local quest events are always published. Each receiving client applies its own
display preferences when deciding whether to render bubbles or print chat logs.
]]

local QuestTogether = _G.QuestTogether

local ANNOUNCEMENT_WIRE_VERSION = 3
local ANNOUNCEMENT_COMMAND = "ANN"
-- Same payload and command length as ANN; older clients safely ignore this
-- emote-only event instead of displaying it as a quest announcement.
local LEVEL_UP_COMMAND = "LVL"
local PING_REQUEST_VERSION = 1
local PING_REQUEST_COMMAND = "PING"
local PING_RESPONSE_VERSION = 2
local PING_RESPONSE_COMMAND = "PONG"
local QUEST_COMPARE_REQUEST_VERSION = 1
local QUEST_COMPARE_REQUEST_COMMAND = "QCMP"
local QUEST_COMPARE_ENTRY_VERSION = 1
local QUEST_COMPARE_ENTRY_COMMAND = "QCQE"
local QUEST_COMPARE_DONE_VERSION = 1
local QUEST_COMPARE_DONE_COMMAND = "QCDN"
local ANNOUNCEMENT_MAX_TEXT_LENGTH = 220
local ADDON_MESSAGE_MAX_BYTES = 255
-- Live Forever channel replies can arrive several minutes after the request.
local PING_REQUEST_TIMEOUT_SECONDS = 300
local PING_MAX_PENDING_REQUESTS = 8
local PING_MAX_RESPONDERS = 4096
local QUEST_COMPARE_TIMEOUT_SECONDS = 180
local QUEST_COMPARE_LARGE_TIMEOUT_SECONDS = 600
local QUEST_COMPARE_CACHE_LIFETIME_SECONDS = 660
local QUEST_COMPARE_SEND_INTERVAL_SECONDS = 0.1
local QUEST_COMPARE_RETRY_INTERVAL_SECONDS = 1
local QUEST_COMPARE_RESPONSE_LIFETIME_SECONDS = 450
local QUEST_COMPARE_MAX_SEND_ATTEMPTS = 5
local QUEST_COMPARE_MAX_QUEUED_RESPONSES = 4
local QUEST_COMPARE_MAX_QUEUED_PACKETS = 128
local QUEST_COMPARE_MAX_ENTRIES = 100
local ANNOUNCEMENT_CHANNEL_FILTER_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_CHANNEL_NOTICE",
	"CHAT_MSG_CHANNEL_NOTICE_USER",
}
local GROUP_ANNOUNCEMENT_DISTRIBUTIONS = {
	PARTY = true,
	RAID = true,
	INSTANCE_CHAT = true,
}
local COMM_DUPLICATE_WINDOW_SECONDS = 0.75
local COMM_REQUEST_DUPLICATE_WINDOW_SECONDS = 10
-- Receiving an addon message grants no authority to choose an arbitrary local
-- emote. Snapshot our shipped selection list so local and remote celebrations
-- share one source without allowing later table mutations to expand acceptance.
local REMOTE_CELEBRATION_EMOTES = {}
for _, token in ipairs(QuestTogether.completionEmotes) do
	REMOTE_CELEBRATION_EMOTES[token] = true
end
local raw_issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil

local function IsSecretValue(value)
	if not raw_issecretvalue then
		return false
	end
	return raw_issecretvalue(value) and true or false
end

local function SafeDebugString(value)
	if QuestTogether and QuestTogether.SafeToString then
		return QuestTogether:SafeToString(value, "<secret>")
	end

	if IsSecretValue(value) then
		return "<secret>"
	end

	local valueType = type(value)
	if valueType == "string" or valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return tostring(value)
	end

	local ok, stringValue = pcall(tostring, value)
	if ok then
		return stringValue
	end
	return "<secret>"
end

local function SafeAddonString(addon, value, fallback)
	if addon and addon.SafeToString then
		return addon:SafeToString(value, fallback or "")
	end

	if IsSecretValue(value) then
		return fallback or ""
	end

	local valueType = type(value)
	if valueType == "string" or valueType == "number" or valueType == "boolean" or valueType == "nil" then
		return tostring(value)
	end

	local ok, textValue = pcall(tostring, value)
	if ok then
		return textValue
	end
	return fallback or ""
end

local function SafePrimitiveString(addon, value, fallback)
	if addon and addon.CanAccessValue and not addon:CanAccessValue(value) then
		return fallback or ""
	end

	local valueType = type(value)
	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end

	return fallback or ""
end

local function SafeTrimAddonString(addon, value, fallback)
	if addon and addon.SafeTrimString then
		return addon:SafeTrimString(value, fallback or "")
	end
	return SafeAddonString(addon, value, fallback or "")
end

local function SafeChannelNumber(addon, value)
	if addon and addon.SafeToNumber then
		return addon:SafeToNumber(value)
	end

	if IsSecretValue(value) then
		return nil
	end

	local numberValue = tonumber(value)
	if type(numberValue) ~= "number" then
		return nil
	end

	return numberValue
end

local function MatchesAnnouncementChannelName(addon, value)
	value = SafeTrimAddonString(addon, value, "")
	if value == "" then
		return false
	end

	local channelName = SafeAddonString(addon, addon.announcementChannelName or "", "")
	if channelName == "" then
		return false
	end

	if value == channelName then
		return true
	end

	local base = string.match(value, "^%d+%.%s+(.+)$") or value
	base = string.lower(base)
	return base == string.lower(channelName)
end

local function SplitByDelimiter(text, delimiter)
	local pieces = {}
	local safeText = SafeAddonString(QuestTogether, text, "")
	local safeDelimiter = SafeAddonString(QuestTogether, delimiter, "")
	if safeText == "" or safeDelimiter == "" then
		return pieces
	end

	local startIndex = 1
	while true do
		local okFind, delimiterIndex = pcall(string.find, safeText, safeDelimiter, startIndex, true)
		if not okFind then
			return pieces
		end
		if not delimiterIndex then
			local okTail, tailValue = pcall(string.sub, safeText, startIndex)
			if okTail and type(tailValue) == "string" then
				pieces[#pieces + 1] = tailValue
			end
			break
		end
		local okPart, partValue = pcall(string.sub, safeText, startIndex, delimiterIndex - 1)
		if okPart and type(partValue) == "string" then
			pieces[#pieces + 1] = partValue
		end
		startIndex = delimiterIndex + #safeDelimiter
	end

	return pieces
end

local function SafeNumber(addon, value)
	if addon and addon.SafeToNumber then
		return addon:SafeToNumber(value)
	end

	if IsSecretValue(value) then
		return nil
	end

	local numberValue = tonumber(value)
	if type(numberValue) ~= "number" then
		return nil
	end

	return numberValue
end

-- Lua's substring limit is measured in bytes. Preserve complete UTF-8 code
-- points when shortening local text or fitting escaped text into a wire packet.
local function TruncateUtf8(text, maxBytes)
	if #text <= maxBytes then
		return text
	end
	local nextIndex = math.max(0, maxBytes) + 1
	while nextIndex > 1 do
		local byte = string.byte(text, nextIndex)
		if not byte or byte < 128 or byte >= 192 then
			break
		end
		nextIndex = nextIndex - 1
	end
	return string.sub(text, 1, nextIndex - 1)
end

local function FitPayloadText(addon, fields, textIndex, command, optionalGroups)
	local originalText = addon:UnescapePayload(fields[textIndex])
	-- Retain a useful amount of text before spending the packet on optional
	-- decoration/location metadata. Identity and quest IDs are never shortened.
	if optionalGroups then
		fields[textIndex] = addon:EscapePayload(TruncateUtf8(originalText, 64))
		for _, group in ipairs(optionalGroups) do
			if #table.concat(fields, ",") + #command + 1 <= ADDON_MESSAGE_MAX_BYTES then break end
			for _, index in ipairs(group) do fields[index] = "" end
		end
		fields[textIndex] = addon:EscapePayload(originalText)
	end
	local payload = table.concat(fields, ",")
	while #payload + #command + 1 > ADDON_MESSAGE_MAX_BYTES and originalText ~= "" do
		originalText = TruncateUtf8(originalText, #originalText - 1)
		fields[textIndex] = addon:EscapePayload(originalText)
		payload = table.concat(fields, ",")
	end
	return payload
end

function QuestTogether:EscapePayload(value)
	local text = SafePrimitiveString(self, value, "")
	-- UTF-8 and spaces are legal addon-message bytes, and old receivers already
	-- accept them. Escape only framing/escape bytes and control characters.
	local ok, escaped = pcall(string.gsub, text, "([%%,|%z\1-\31\127])", function(character)
		local okByte, byteValue = pcall(string.byte, character)
		if not okByte or not byteValue then
			return ""
		end
		return string.format("%%%02X", byteValue)
	end)
	if not ok then
		return ""
	end
	return escaped
end

function QuestTogether:UnescapePayload(value)
	local text = SafePrimitiveString(self, value, "")
	local ok, unescaped = pcall(string.gsub, text, "%%(%x%x)", function(hex)
		local safeHex = SafeAddonString(self, hex or "", "")
		local okFirst, firstChar = pcall(string.sub, safeHex, 1, 1)
		local okSecond, secondChar = pcall(string.sub, safeHex, 2, 2)
		if not okFirst or not okSecond then
			return ""
		end
		local firstNibble = nil
		local secondNibble = nil
		if firstChar ~= "" then
			local firstByte = string.byte(string.upper(firstChar))
			if firstByte >= string.byte("0") and firstByte <= string.byte("9") then
				firstNibble = firstByte - string.byte("0")
			elseif firstByte >= string.byte("A") and firstByte <= string.byte("F") then
				firstNibble = firstByte - string.byte("A") + 10
			end
		end
		if secondChar ~= "" then
			local secondByte = string.byte(string.upper(secondChar))
			if secondByte >= string.byte("0") and secondByte <= string.byte("9") then
				secondNibble = secondByte - string.byte("0")
			elseif secondByte >= string.byte("A") and secondByte <= string.byte("F") then
				secondNibble = secondByte - string.byte("A") + 10
			end
		end
		if firstNibble == nil or secondNibble == nil then
			return ""
		end
		return string.char((firstNibble * 16) + secondNibble)
	end)
	if not ok then
		return ""
	end
	return unescaped
end

function QuestTogether:SerializeWireMessage(command, payload)
	return SafeAddonString(self, command or "", "") .. "|" .. SafeAddonString(self, payload or "", "")
end

function QuestTogether:DeserializeWireMessage(message)
	local safeMessage = SafeAddonString(self, message, "")
	if safeMessage == "" then
		return nil, nil
	end

	local ok, command, payload = pcall(string.match, safeMessage, "^([^|]+)|?(.*)$")
	if not ok then
		return nil, nil
	end
	if not command or command == "" then
		return nil, nil
	end

	return command, payload
end

function QuestTogether:SanitizeAnnouncementText(text)
	local sanitized = SafeTrimAddonString(self, text, "")
	return TruncateUtf8(sanitized, ANNOUNCEMENT_MAX_TEXT_LENGTH)
end

function QuestTogether:GetAnnouncementServerTime()
	local getter = self.API and self.API.GetServerTime
	if type(getter) ~= "function" then return nil end
	local ok, value = pcall(getter)
	local now = ok and SafeNumber(self, value) or nil
	return now and now >= 1000000000 and now < 100000000000 and now == math.floor(now) and now or nil
end

function QuestTogether:SanitizeAnnouncementExtraData(extraData)
	local sanitized = {}
	if type(extraData) ~= "table" or not self:CanAccessTable(extraData) then
		return sanitized
	end

	local iconAsset = SafePrimitiveString(self, extraData.iconAsset, "")
	local iconKind = SafePrimitiveString(self, extraData.iconKind, "")
	local emoteToken = SafePrimitiveString(self, extraData.emoteToken, "")
	local facts = SafePrimitiveString(self, extraData.eventFacts, "")
	if self.DecodeAnnouncementFacts and self:DecodeAnnouncementFacts(facts) then sanitized.eventFacts = facts end
	if iconAsset ~= "" then
		sanitized.iconAsset = iconAsset
	end
	if iconKind ~= "" then
		sanitized.iconKind = iconKind
	end
	if emoteToken ~= "" then
		sanitized.emoteToken = emoteToken
	end

	return sanitized
end

function QuestTogether:SanitizeAnnouncementEventData(eventData)
	if type(eventData) ~= "table" or not self:CanAccessTable(eventData) then
		return nil
	end

	local eventType = SafePrimitiveString(self, eventData.eventType, "")
	local senderName = SafePrimitiveString(self, eventData.senderName, "")
	local text = self:SanitizeAnnouncementText(eventData.text)
	if eventType == "" or senderName == "" or text == "" then
		return nil
	end

	local sanitizedExtraData = self:SanitizeAnnouncementExtraData(eventData)
	local normalizedQuestId = self.NormalizeQuestID and self:NormalizeQuestID(eventData.questId) or nil
	local numericCoordX = self.SafeToNumber and self:SafeToNumber(eventData.coordX) or nil
	local numericCoordY = self.SafeToNumber and self:SafeToNumber(eventData.coordY) or nil
	local numericMapID = SafeNumber(self, eventData.mapID)
	if numericMapID and (numericMapID <= 0 or numericMapID ~= math.floor(numericMapID)) then
		numericMapID = nil
	end
	local eventId = SafePrimitiveString(self, eventData.eventId, "")
	if #eventId > 64 or not eventId:match("^%d+%-%d+%-%d+$") then eventId = "" end
	local normalizedWarMode = nil
	local occurredAt = SafeNumber(self, eventData.occurredAt)
	if occurredAt and (occurredAt < 1000000000 or occurredAt >= 100000000000 or occurredAt ~= math.floor(occurredAt)) then occurredAt = nil end
	if self.NormalizeAnnouncementWarModeValue then
		normalizedWarMode = self:NormalizeAnnouncementWarModeValue(eventData.warMode)
	end

	return {
		version = SafeNumber(self, eventData.version) or ANNOUNCEMENT_WIRE_VERSION,
		occurredAt = occurredAt,
		eventId = eventId,
		eventType = SafePrimitiveString(self, eventType, ""),
		senderGUID = SafePrimitiveString(self, eventData.senderGUID, ""),
		classFile = SafePrimitiveString(self, eventData.classFile, ""),
		senderName = senderName,
		text = text,
		questId = normalizedQuestId and SafePrimitiveString(self, normalizedQuestId, "") or "",
		iconAsset = sanitizedExtraData.iconAsset or "",
		iconKind = sanitizedExtraData.iconKind or "",
		zoneName = SafePrimitiveString(self, eventData.zoneName, ""),
		coordX = numericCoordX and string.format("%.1f", numericCoordX) or "",
		coordY = numericCoordY and string.format("%.1f", numericCoordY) or "",
		warMode = normalizedWarMode == nil and "" or (normalizedWarMode and "1" or "0"),
		emoteToken = sanitizedExtraData.emoteToken or "",
		eventFacts = sanitizedExtraData.eventFacts or "",
		mapID = numericMapID and SafePrimitiveString(self, numericMapID, "") or "",
	}
end

function QuestTogether:EncodePingRequestPayload(requestData)
	local fields = {
		SafeAddonString(self, PING_REQUEST_VERSION),
		self:EscapePayload(requestData.requestId or ""),
		self:EscapePayload(requestData.requesterName or ""),
	}

	if requestData.supportsDirectComms then fields[4] = "direct1" end
	if requestData.supportsPagedPong then fields[4], fields[5] = "direct1", "pages1" end
	if requestData.developerRequest then
		fields[6], fields[7] = "dev1", tostring(requestData.issuedAt)
		fields[8], fields[9], fields[10] = requestData.debugRequest and "debug" or "snapshot",
			self:EscapePayload(requestData.targetName or ""), requestData.signature
		-- Keep pages1 for old peers; the trailing extension opts targeted reports
		-- into larger bounded replies without changing the signed request text.
		if requestData.supportsLargePong and requestData.debugRequest then fields[11] = "2" end
	end
	return table.concat(fields, ",")
end

function QuestTogether:DecodePingRequestPayload(payload)
	payload = SafePrimitiveString(self, payload, "")
	if payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= PING_REQUEST_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local requesterName = self:UnescapePayload(fields[3] or "")
	if requestId == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		requesterName = requesterName,
		supportsDirectComms = fields[4] == "direct1",
		supportsPagedPong = fields[4] == "direct1" and fields[5] == "pages1",
		supportsLargePong = fields[4] == "direct1" and fields[5] == "pages1" and fields[11] == "2",
		developerRequest = fields[6] == "dev1",
		issuedAt = SafeNumber(self, fields[7]),
		debugRequest = fields[8] == "debug",
		targetName = fields[9] and fields[9] ~= "" and self:UnescapePayload(fields[9]) or nil,
		signature = fields[10],
	}
end

function QuestTogether:EncodePingResponsePayload(responseData, preserveAll)
	local fields = {
		SafeAddonString(self, PING_RESPONSE_VERSION),
		self:EscapePayload(responseData.requestId or ""),
		self:EscapePayload(responseData.senderName or ""),
		self:EscapePayload(responseData.realmName or ""),
		self:EscapePayload(responseData.raceName or ""),
		self:EscapePayload(responseData.classFile or ""),
		self:EscapePayload(responseData.className or ""),
		self:EscapePayload(responseData.level or ""),
		self:EscapePayload(responseData.zoneName or ""),
		self:EscapePayload(responseData.coordX or ""),
		self:EscapePayload(responseData.coordY or ""),
		self:EscapePayload(responseData.warMode or ""),
		self:EscapePayload(responseData.mapID or ""),
		self:EscapePayload(responseData.addonVersion or ""),
	}
	if preserveAll then
		if responseData.developer then
			fields[15], fields[16], fields[17] = "dev1", responseData.locationShared and "1" or "0", responseData.lookingForQuestPartners and "1" or "0"
			fields[18], fields[19] = self:EscapePayload(responseData.faction or ""), self:EscapePayload(responseData.diagnosticText or "")
			fields[20], fields[21] = self:EscapePayload(responseData.partyPayload or ""), tostring(responseData.sampledAt or "")
		end
		return table.concat(fields, ",")
	end

	-- All descriptive fields are optional to old receivers. Drop whole labels,
	-- not fragments of a player's name or a localized place/race/class name.
	for _, group in ipairs({ { 5, 7 }, { 4 }, { 9 }, { 14 }, { 10, 11, 12, 13 }, { 6, 8 } }) do
		if #table.concat(fields, ",") + #PING_RESPONSE_COMMAND + 1 <= ADDON_MESSAGE_MAX_BYTES then break end
		for _, index in ipairs(group) do fields[index] = "" end
	end
	return table.concat(fields, ",")
end

function QuestTogether:DecodePingResponsePayload(payload)
	payload = SafePrimitiveString(self, payload, "")
	if payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= 1 and version ~= PING_RESPONSE_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local senderName = self:UnescapePayload(fields[3] or "")
	local realmName = self:UnescapePayload(fields[4] or "")
	local raceName = self:UnescapePayload(fields[5] or "")
	local classFile = self:UnescapePayload(fields[6] or "")
	local className = self:UnescapePayload(fields[7] or "")
	local level = self:UnescapePayload(fields[8] or "")
	local zoneName = self:UnescapePayload(fields[9] or "")
	local coordX = self:UnescapePayload(fields[10] or "")
	local coordY = self:UnescapePayload(fields[11] or "")
	local warMode = self:UnescapePayload(fields[12] or "")
	local mapID = self:UnescapePayload(fields[13] or "")
	local addonVersion = self:UnescapePayload(fields[14] or "")
	if requestId == "" or senderName == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		senderName = senderName,
		realmName = realmName,
		raceName = raceName,
		classFile = classFile,
		className = className,
		level = level,
		zoneName = zoneName,
		coordX = coordX,
		coordY = coordY,
		warMode = warMode,
		mapID = mapID,
		addonVersion = addonVersion,
		developer = fields[15] == "dev1",
		locationShared = fields[16] == "1",
		lookingForQuestPartners = fields[17] == "1",
		faction = self:UnescapePayload(fields[18] or ""),
		diagnosticText = self:UnescapePayload(fields[19] or ""),
		partyPayload = self:UnescapePayload(fields[20] or ""),
		sampledAt = SafeNumber(self, fields[21]),
	}
end

function QuestTogether:EncodeQuestCompareRequestPayload(requestData)
	local fields = {
		SafeAddonString(self, QUEST_COMPARE_REQUEST_VERSION),
		self:EscapePayload(requestData.requestId or ""),
		self:EscapePayload(requestData.requesterName or ""),
		self:EscapePayload(requestData.targetName or ""),
	}
	if requestData.objectiveQuestId then fields[5] = tostring(requestData.objectiveQuestId) end
	if requestData.supportsSnapshotIdentity then fields[5], fields[6] = fields[5] or "", "snap1" end
	if requestData.supportsRevision and requestData.supportsSnapshotIdentity and not requestData.objectiveQuestId then
		fields[5], fields[6], fields[7], fields[8] = fields[5] or "", "snap1", "rev1", requestData.knownRevision or ""
		if #table.concat(fields, ",") > 250 then fields[8] = "" end
		if #table.concat(fields, ",") > 250 then fields[7], fields[8] = nil, nil end
	end

	return table.concat(fields, ",")
end

function QuestTogether:DecodeQuestCompareRequestPayload(payload)
	payload = SafePrimitiveString(self, payload, "")
	if payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= QUEST_COMPARE_REQUEST_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local requesterName = self:UnescapePayload(fields[3] or "")
	local targetName = self:UnescapePayload(fields[4] or "")
	local objectiveQuestId = fields[5] and fields[5] ~= "" and SafeNumber(self, fields[5]) or nil
	if fields[5] and fields[5] ~= "" and (not objectiveQuestId or objectiveQuestId < 1 or objectiveQuestId > 1000000000 or objectiveQuestId ~= math.floor(objectiveQuestId)) then return nil end
	if requestId == "" or targetName == "" then
		return nil
	end

	return {
		version = version,
		requestId = requestId,
		requesterName = requesterName,
		targetName = targetName,
		objectiveQuestId = objectiveQuestId,
		supportsSnapshotIdentity = fields[6] == "snap1",
		supportsRevision = fields[6] == "snap1" and fields[7] == "rev1" and not objectiveQuestId,
		knownRevision = fields[8] and #fields[8] <= 64 and fields[8]:match("^[%d%-]+$") and fields[8] or nil,
	}
end

local function ValidCompareSnapshotID(value)
	return type(value) == "string" and #value > 0 and #value <= 64 and not value:find("[^%d%-]")
end

function QuestTogether:EncodeQuestCompareEntryPayload(entryData)
	-- Empty means unavailable. Keep the existing 1/0 representation for known
	-- values so both historical entry layouts remain readable.
	local pushable = ""
	if self:CanAccessValue(entryData.isPushable) and type(entryData.isPushable) == "boolean" then
		pushable = entryData.isPushable and "1" or "0"
	end
	local fields = {
		SafeAddonString(self, QUEST_COMPARE_ENTRY_VERSION),
		self:EscapePayload(entryData.requestId or ""),
		self:EscapePayload(entryData.senderName or ""),
		self:EscapePayload(entryData.classFile or ""),
		self:EscapePayload(entryData.questId or ""),
		self:EscapePayload(entryData.questTitle or ""),
		self:EscapePayload(entryData.isComplete and "1" or "0"),
		pushable,
	}
	if entryData.objectiveCount ~= nil then fields[9] = tostring(entryData.objectiveCount) end
	if entryData.snapshotId then fields[9], fields[10] = fields[9] or "", entryData.snapshotId end

	return FitPayloadText(self, fields, 6, QUEST_COMPARE_ENTRY_COMMAND)
end

function QuestTogether:DecodeQuestCompareEntryPayload(payload)
	payload = SafePrimitiveString(self, payload, "")
	if payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= QUEST_COMPARE_ENTRY_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local senderName = self:UnescapePayload(fields[3] or "")
	local classFile = ""
	local questId = ""
	local questTitle = ""
	local isComplete = false
	local pushableToken

	if fields[8] ~= nil then
		classFile = self:UnescapePayload(fields[4] or "")
		questId = self:UnescapePayload(fields[5] or "")
		questTitle = self:UnescapePayload(fields[6] or "")
		isComplete = self:UnescapePayload(fields[7] or "") == "1"
		pushableToken = self:UnescapePayload(fields[8] or "")
	else
		questId = self:UnescapePayload(fields[4] or "")
		questTitle = self:UnescapePayload(fields[5] or "")
		isComplete = self:UnescapePayload(fields[6] or "") == "1"
		pushableToken = self:UnescapePayload(fields[7] or "")
	end
	local isPushable
	if pushableToken == "1" then
		isPushable = true
	elseif pushableToken == "0" then
		isPushable = false
	end
	if requestId == "" or senderName == "" or questId == "" then
		return nil
	end
	local objectiveCount = fields[9] and fields[9] ~= "" and SafeNumber(self, fields[9]) or nil
	if fields[9] and fields[9] ~= "" and (not objectiveCount or objectiveCount < 0 or objectiveCount > 20 or objectiveCount ~= math.floor(objectiveCount)) then return nil end

	if fields[10] and not ValidCompareSnapshotID(fields[10]) then return nil end
	return {
		version = version,
		requestId = requestId,
		senderName = senderName,
		classFile = classFile,
		questId = questId,
		questTitle = questTitle,
		isComplete = isComplete,
		isPushable = isPushable,
		objectiveCount = objectiveCount,
		snapshotId = fields[10],
	}
end

-- Objective replies are scoped to a requested quest. One bounded packet per
-- objective avoids truncating an entire list or adding unsolicited log traffic.
function QuestTogether:EncodeQuestCompareObjectivePayload(requestId, row, snapshotId)
	local fields = { "1", self:EscapePayload(requestId), tostring(row.questId), tostring(row.objectiveIndex),
		self:EscapePayload(row.text), self:EscapePayload(row.kind), row.finished == true and "1" or row.finished == false and "0" or "",
		row.current ~= nil and tostring(row.current) or "", row.required ~= nil and tostring(row.required) or "" }
	if snapshotId then fields[10] = snapshotId end
	return FitPayloadText(self, fields, 5, "QCOB")
end

function QuestTogether:DecodeQuestCompareObjectivePayload(payload)
	local f = SplitByDelimiter(SafePrimitiveString(self, payload, ""), ",")
	if (#f ~= 9 and #f ~= 10) or f[1] ~= "1" or f[2] == ""
		or (f[10] and not ValidCompareSnapshotID(f[10])) then return nil end
	local id, index = SafeNumber(self, f[3]), SafeNumber(self, f[4])
	if not id or id < 1 or id > 1000000000 or id ~= math.floor(id) or not index or index < 1 or index > 20 or index ~= math.floor(index) then return nil end
	if f[7] ~= "" and f[7] ~= "0" and f[7] ~= "1" then return nil end
	local current, required = SafeNumber(self, f[8]), SafeNumber(self, f[9])
	for i = 8, 9 do
		local n = SafeNumber(self, f[i])
		if f[i] ~= "" and (not n or n < 0 or n > 1000000000 or n ~= math.floor(n)) then return nil end
	end
	local kind = self:UnescapePayload(f[6])
	if #kind > 32 or kind:find("[^%a]") then return nil end
	local finished
	if f[7] ~= "" then finished = f[7] == "1" end
	local text = self:CleanQuestCompareObjectiveText(self:UnescapePayload(f[5]))
	if text == "" then return nil end
	return { requestId = self:UnescapePayload(f[2]), questId = id, objectiveIndex = index,
		text = text, kind = kind,
		finished = finished, current = current, required = required, snapshotId = f[10] }
end

-- Callers keep one logical handle across retries. Only its current wire ID
-- accepts packets; cancellation of that handle also invalidates retry aliases.
function QuestTogether:GetPendingQuestCompare(requestId)
	local pending = self.pendingQuestCompareRequests and self.pendingQuestCompareRequests[requestId]
	if not pending or (pending.logicalRequestId and self.pendingQuestCompareRequests[pending.logicalRequestId] ~= pending)
		or (pending.wireRequestId and pending.wireRequestId ~= requestId) or pending.restartPending then return nil end
	return pending
end

function QuestTogether:AcceptQuestCompareSnapshot(pending, snapshotId)
	local identity = snapshotId or false -- Explicit legacy identity; never mix negotiated and old packets.
	if pending.snapshotId ~= nil and pending.snapshotId ~= identity then
		if pending.restart then pending.restart() end
		return false
	end
	pending.snapshotId = identity
	return true
end

function QuestTogether:ClearPendingQuestCompare(requestId, pending)
	if self.pendingQuestCompareRequests[requestId] == pending then self.pendingQuestCompareRequests[requestId] = nil end
	if pending.logicalRequestId and self.pendingQuestCompareRequests[pending.logicalRequestId] == pending then
		self.pendingQuestCompareRequests[pending.logicalRequestId] = nil
	end
	if pending.wireRequestId and self.pendingQuestCompareRequests[pending.wireRequestId] == pending then
		self.pendingQuestCompareRequests[pending.wireRequestId] = nil
	end
end

function QuestTogether:HandleQuestCompareObjective(row, sender)
	local pending = self:GetPendingQuestCompare(row.requestId)
	if not pending or pending.targetName ~= self:NormalizeMemberName(sender) or pending.objectiveQuestId ~= row.questId then return false end
	if not self:AcceptQuestCompareSnapshot(pending, row.snapshotId) then return false end
	pending.objectives = pending.objectives or {}
	if pending.objectives[row.objectiveIndex] then return false end
	pending.objectives[row.objectiveIndex] = row
	pending.lastProgressAt, pending.receivedData = self.API.GetTime(), true
	self:TryCompleteQuestCompare(row.requestId)
	return true
end

function QuestTogether:EncodeQuestCompareDonePayload(doneData)
	local fields = {
		SafeAddonString(self, QUEST_COMPARE_DONE_VERSION),
		self:EscapePayload(doneData.requestId or ""),
		self:EscapePayload(doneData.senderName or ""),
		self:EscapePayload(doneData.classFile or ""),
		self:EscapePayload(doneData.count or ""),
		doneData.supportsShareRequests and "share1" or "",
		doneData.supportsObjectives and "obj1" or "",
	}

	if doneData.snapshotId then fields[8] = doneData.snapshotId end
	if doneData.revision and doneData.snapshotId then
		fields[9], fields[10] = doneData.revision, doneData.unchanged and "same1" or ""
	end
	return table.concat(fields, ",")
end

function QuestTogether:DecodeQuestCompareDonePayload(payload)
	payload = SafePrimitiveString(self, payload, "")
	if payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= QUEST_COMPARE_DONE_VERSION then
		return nil
	end

	local requestId = self:UnescapePayload(fields[2] or "")
	local senderName = self:UnescapePayload(fields[3] or "")
	local classFile = ""
	local count = ""
	if fields[5] ~= nil then
		classFile = self:UnescapePayload(fields[4] or "")
		count = self:UnescapePayload(fields[5] or "")
	else
		count = self:UnescapePayload(fields[4] or "")
	end
	if requestId == "" or senderName == "" then
		return nil
	end

	local numericCount = SafeNumber(self, count)
	if not numericCount or numericCount < 0 or numericCount ~= math.floor(numericCount) then
		return nil
	end
	if fields[8] and not ValidCompareSnapshotID(fields[8]) then return nil end
	if fields[9] and (not fields[8] or not ValidCompareSnapshotID(fields[9])) then return nil end
	if fields[10] and fields[10] ~= "" and fields[10] ~= "same1" then return nil end
	return {
		version = version,
		requestId = requestId,
		senderName = senderName,
		classFile = classFile,
		count = numericCount,
		supportsShareRequests = fields[6] == "share1",
		supportsObjectives = fields[7] == "obj1",
		snapshotId = fields[8],
		revision = fields[9],
		unchanged = fields[10] == "same1",
	}
end

function QuestTogether:EncodeAnnouncementPayload(eventData)
	local fields = {
		SafeAddonString(self, ANNOUNCEMENT_WIRE_VERSION),
		self:EscapePayload(eventData.eventType or ""),
		self:EscapePayload(eventData.senderGUID or ""),
		self:EscapePayload(eventData.classFile or ""),
		self:EscapePayload(eventData.senderName or ""),
		self:EscapePayload(eventData.text or ""),
		self:EscapePayload(eventData.questId or ""),
		self:EscapePayload(eventData.iconAsset or ""),
		self:EscapePayload(eventData.iconKind or ""),
		self:EscapePayload(eventData.zoneName or ""),
		self:EscapePayload(eventData.coordX or ""),
		self:EscapePayload(eventData.coordY or ""),
		self:EscapePayload(eventData.warMode or ""),
		self:EscapePayload(eventData.emoteToken or ""),
		-- Append optional fields: v1-v3 receivers continue reading their original
		-- slots, and new receivers can still use zone labels from older packets.
		self:EscapePayload(eventData.mapID or ""),
		self:EscapePayload(eventData.eventFacts or ""),
		self:EscapePayload(eventData.occurredAt or ""),
	}

	if eventData.eventId and eventData.eventId ~= "" then fields[18] = self:EscapePayload(eventData.eventId) end

	-- Numeric location is useful even when a long localized display label cannot
	-- fit. Keep the coordinate system, coordinates and war mode together.
	return FitPayloadText(self, fields, 6, ANNOUNCEMENT_COMMAND, { { 8, 9 }, { 10 }, { 3 }, { 4 }, { 17 }, { 16 }, { 11, 12, 13, 15 } })
end

function QuestTogether:DecodeAnnouncementPayload(payload)
	payload = SafePrimitiveString(self, payload, "")
	if payload == "" then
		return nil
	end

	local fields = SplitByDelimiter(payload, ",")
	local version = SafeNumber(self, fields[1] or "")
	if version ~= 1 and version ~= 2 and version ~= ANNOUNCEMENT_WIRE_VERSION then
		return nil
	end

	local eventType = self:UnescapePayload(fields[2] or "")
	local senderGUID = self:UnescapePayload(fields[3] or "")
	local classFile = self:UnescapePayload(fields[4] or "")
	local senderName = self:UnescapePayload(fields[5] or "")
	local text = self:UnescapePayload(fields[6] or "")
	local questId = self:UnescapePayload(fields[7] or "")
	local iconAsset = self:UnescapePayload(fields[8] or "")
	local iconKind = self:UnescapePayload(fields[9] or "")
	local zoneName = self:UnescapePayload(fields[10] or "")
	local coordX = self:UnescapePayload(fields[11] or "")
	local coordY = self:UnescapePayload(fields[12] or "")
	local warMode = self:UnescapePayload(fields[13] or "")
	local emoteToken = self:UnescapePayload(fields[14] or "")
	local mapID = self:UnescapePayload(fields[15] or "")
	local eventFacts = self:UnescapePayload(fields[16] or "")
	local occurredAt = self:UnescapePayload(fields[17] or "")
	local eventId = self:UnescapePayload(fields[18] or "")

	if eventType == "" or senderName == "" or text == "" then
		return nil
	end

	return self:SanitizeAnnouncementEventData({
		version = version,
		eventType = eventType,
		occurredAt = occurredAt,
		eventId = eventId,
		senderGUID = senderGUID,
		classFile = classFile,
		senderName = senderName,
		text = text,
		questId = questId,
		iconAsset = iconAsset,
		iconKind = iconKind,
		zoneName = zoneName,
		coordX = coordX,
		coordY = coordY,
		warMode = warMode,
		emoteToken = emoteToken,
		mapID = mapID,
		eventFacts = eventFacts,
	})
end

function QuestTogether:GetAnnouncementChannelLocalID(channelName)
	if not self.API or not self.API.GetChannelName then
		return nil
	end

	local localID = self.API.GetChannelName(channelName or self.announcementChannelName)
	local numericLocalID = SafeChannelNumber(self, localID)
	if numericLocalID and numericLocalID > 0 then
		return numericLocalID
	end

	return nil
end

function QuestTogether:GetAnnouncementChannelTarget(channelName)
	channelName = channelName or self.announcementChannelName
	local localID = self:GetAnnouncementChannelLocalID(channelName)
	if type(localID) == "number" and localID > 0 then
		return localID
	end

	return channelName
end

function QuestTogether:GetGroupAnnouncementDistribution()
	if self.API and self.API.IsInInstanceGroup and self.API.IsInInstanceGroup() then
		return "INSTANCE_CHAT"
	end
	if self.API and self.API.IsInRaid and self.API.IsInRaid() then
		return "RAID"
	end
	if self.API and self.API.IsInParty and self.API.IsInParty() then
		return "PARTY"
	end
	return nil
end

function QuestTogether:GetAnnouncementWireRoutes()
	local groupedDistribution = self:GetGroupAnnouncementDistribution()
	local routes = {}
	if groupedDistribution then
		routes[#routes + 1] = {
			distribution = groupedDistribution,
			target = nil,
			requiresChannelJoin = false,
		}
	end
	routes[#routes + 1] = {
		distribution = "CHANNEL",
		target = self:GetAnnouncementChannelTarget(),
		requiresChannelJoin = true,
	}
	return routes
end

function QuestTogether:GetCommsDiagnostics()
	local runtime = self:GetRuntimeWorkStateStore()
	runtime.commsDiagnostics = runtime.commsDiagnostics or {}
	return runtime.commsDiagnostics
end

-- Fixed command buckets keep unknown traffic from growing diagnostic state.
local TRAFFIC_COMMANDS = { QTNAV = true, QTN2 = true, ANN = true, LVL = true, LOC = true, QTPR = true, QTVR = true,
	QTLF = true, QTLQ = true, QJST = true, QJON = true, QTPG = true, QPGR = true, QPGM = true, QCMP = true, QCQE = true,
	QCDN = true, QCOB = true, QTB1 = true, QTDQ = true, QTCI = true, QTHQ = true, QTHD = true, QTPH = true, QTSR = true, QTSP = true, QTSX = true, QSHR = true, PING = true, PONG = true, PONP = true }
function QuestTogether:RecordCommsTraffic(kind, message, result)
	local diagnostics = self:GetCommsDiagnostics()
	local now = SafeNumber(self, self.API.GetTime and self.API.GetTime())
	diagnostics.trafficStartedAt = diagnostics.trafficStartedAt or now
	diagnostics.trafficObservedAt = now
	diagnostics.traffic = diagnostics.traffic or {}
	local command = message:match("^([^|]+)|")
	command = TRAFFIC_COMMANDS[command] and command or "OTHER"
	local bucket = diagnostics.traffic[command] or {}
	diagnostics.traffic[command] = bucket
	bucket[kind] = (bucket[kind] or 0) + 1
	bucket[kind .. "Bytes"] = (bucket[kind .. "Bytes"] or 0) + #message
	if result == 3 or result == 8 then bucket.throttled = (bucket.throttled or 0) + 1 end
end

function QuestTogether:RecordAnnouncementLatency(eventData)
	local now = self:GetAnnouncementServerTime()
	local age = now and eventData.occurredAt and now - eventData.occurredAt or nil
	local diagnostics = self:GetCommsDiagnostics()
	-- These are sender-reported, second-resolution timestamps, not trusted
	-- network telemetry. Future or implausibly old values remain unknown.
	if age and age >= 0 and age <= 86400 then
		diagnostics.announcementAgeSamples = (diagnostics.announcementAgeSamples or 0) + 1
		diagnostics.announcementAgeTotal = (diagnostics.announcementAgeTotal or 0) + age
		diagnostics.announcementAgeMax = math.max(diagnostics.announcementAgeMax or 0, age)
		diagnostics.announcementAgeLast = age
	else
		age = nil
		diagnostics.announcementAgeUnknown = (diagnostics.announcementAgeUnknown or 0) + 1
	end
	self:Debugf("comms", "announcement age sender=%s event=%s reportedAgeSeconds=%s",
		eventData.senderName, eventData.eventType, age and tostring(age) or "unknown")
end

function QuestTogether:RecordCommsDiagnostic(kind, detail)
	local diagnostics = self:GetCommsDiagnostics()
	diagnostics[kind] = (diagnostics[kind] or 0) + 1
	if kind == "failedRoutes" or kind == "invalidMessages" then
		diagnostics.lastFailure = detail
	end
	-- Keep every display decision: these are needed to explain a user's bubble.
	-- Sample transport chatter, while retaining its exact aggregate counters.
	local count = diagnostics[kind]
	if kind == "acceptedAnnouncements" or kind == "suppressedAnnouncements" or count <= 5 or count % 100 == 0 then
		self:Debugf("comms", "%s count=%d %s", kind, count, detail or "")
	end
end

-- One-recipient controls use whispers only after capability discovery or a
-- valid direct exchange. Older peers retain their established group/channel path.
local DIRECT_COMMANDS = { QCMP = true, QCQE = true, QCOB = true, QCDN = true, QJON = true,
	QPGR = true, QPGM = true, QSHR = true, PONG = true, PONP = true, PING = true }

function QuestTogether:RememberDirectCommPeer(sender, supported, lifetime)
	local name = self:NormalizeMemberName(sender)
	if not name or #name > 120 or name:find("[%c|,]") or self:IsSelfSender(name) or self:IsIgnoredPlayerName(name) then return end
	local state = rawget(self, "directCommPeers")
	if not state then state = {}; self.directCommPeers = state end
	if not supported then state[name] = nil; return end
	local now = self.API.GetTime()
	local existing = state[name]
	state[name] = { at = now, expires = now + (lifetime or 600) }
	-- Refreshes do not grow the cache; bound/prune only on new admission.
	if existing then return end
	local count, oldest, at = 0
	for key, peer in pairs(state) do
		if now < peer.at or now >= peer.expires then state[key] = nil
		else
			count = count + 1
			if not at or peer.at < at then oldest, at = key, peer.at end
		end
	end
	if count > 512 then state[oldest] = nil end
end

function QuestTogether:SupportsDirectComms(sender)
	local name = self:NormalizeMemberName(sender)
	local state = rawget(self, "directCommPeers")
	local peer = state and name and state[name]
	local now = self.API.GetTime()
	if peer and now >= peer.at and now < peer.expires and not self:IsIgnoredPlayerName(name) then return true end
	if state and name then state[name] = nil end
	return false
end

function QuestTogether:GetTargetedCommRoutes(target, legacyRoutes)
	target = self:NormalizeMemberName(target)
	if not target or self:IsSelfSender(target) or self:IsIgnoredPlayerName(target) then return {} end
	local group = self:IsGroupedSender(target) and self:GetGroupAnnouncementDistribution()
	local fallback = legacyRoutes or (group and { { distribution = group } })
		or { { distribution = "CHANNEL", channelName = self.announcementChannelName, requiresChannelJoin = true } }
	if self:SupportsDirectComms(target) then
		local groupOnly = fallback[1] and (fallback[1].requiresGroup or GROUP_ANNOUNCEMENT_DISTRIBUTIONS[fallback[1].distribution]) or false
		return { { distribution = "WHISPER", target = target, requiresGroup = groupOnly } }
	end
	return fallback
end

local COMM_SEND_POLICIES = {}
function QuestTogether:RegisterCommSendPolicy(command, builder)
	COMM_SEND_POLICIES[command] = builder
end

-- Privacy cleanup follows packet content, not the preference at enqueue time.
-- Interactive comparison/roster controls never carry a position and must survive
-- an unrelated location opt-out. Fail closed for malformed location-bearing wire.
local function PublishesLocation(addon, wire)
	local command, payload = addon:DeserializeWireMessage(wire)
	local data
	if command == "ANN" or command == "LVL" then
		data = addon:DecodeAnnouncementPayload(payload)
	elseif command == "PONG" then
		data = addon:DecodePingResponsePayload(payload)
	elseif command == "LOC" then
		data = addon:DecodePlayerLocationPayload(payload)
		return not data or data.mask ~= 0
	elseif command == "QTB1" then
		return true -- Packed snapshots are replaced atomically on consent changes.
	else
		return false
	end
	if not data then return true end
	for _, key in ipairs({ "mapID", "zoneName", "coordX", "coordY" }) do
		if data[key] ~= nil and data[key] ~= "" then return true end
	end
	return false
end

local BULK_COMMANDS = { QCQE=true, QCOB=true, QCDN=true, PONP=true }
function QuestTogether:BuildCommSendOptions(wire, route, supplied)
	local command = wire:match("^([^|]+)|")
	local options = {}
	local policy = COMM_SEND_POLICIES[command]
	if policy then policy(self, wire, route, options) end
	local featureCurrent = options.isCurrent
	for key, value in pairs(supplied or {}) do options[key] = value end
	local callerCurrent, fingerprint = supplied and supplied.isCurrent, self.partyRosterFingerprint
	options.priority = options.priority or (BULK_COMMANDS[command] and "bulk")
		or ((command == "ANN" or command == "LVL") and "event") or "control"
	if options.publishesLocation == nil then options.publishesLocation = PublishesLocation(self, wire) end
	options.isCurrent = function()
		if featureCurrent and not featureCurrent() then return false end
		if callerCurrent and not callerCurrent() then return false end
		if route.distribution == "WHISPER" then
			return not self:IsIgnoredPlayerName(route.target) and (not route.requiresGroup or
				(self:IsGroupedSender(route.target) and fingerprint == self.partyRosterFingerprint))
		elseif route.distribution == "CHANNEL" then
			local geo = rawget(self, "geographicCommsState")
			if options.key == "zone-discovery" and (not geo or route.channelName ~= geo.currentChannel) then return false end
			return route.channelName == self.announcementChannelName or
				(geo and geo.subscriptions[route.channelName] ~= nil) or false
		end
		return route.distribution == self:GetGroupAnnouncementDistribution() and fingerprint == self.partyRosterFingerprint
	end
	return options
end

function QuestTogether:SendWireMessageToAnnouncementRoutes(wireMessage, debugContext, selectedRoutes, direct, completion)
	wireMessage = SafePrimitiveString(self, wireMessage, "")
	if wireMessage == "" or not self.isEnabled or (self.isLoggingOut and not direct) then return false, "cancelled" end
	if #wireMessage > ADDON_MESSAGE_MAX_BYTES or wireMessage:find("\0", 1, true) then
		self:RecordCommsDiagnostic("invalidMessages", "send rejected bytes=" .. #wireMessage)
		return false, "invalid"
	end
	-- A bulk sender advances once per native delivery. Its completion descriptor
	-- therefore requires one explicit route, never an implicit broadcast/fanout.
	if completion and (type(selectedRoutes) ~= "table" or #selectedRoutes ~= 1) then return false, "invalid" end
	local command, geo = wireMessage:match("^([^|]+)|"), rawget(self, "geographicCommsState")
	if geo and not direct and not selectedRoutes then
		local staged = self:StageGeographicState(wireMessage)
		if staged ~= nil then return staged, staged and "staged" or "failed" end
		if command == "ANN" or command == "LVL" then selectedRoutes = self:GetGeographicAnnouncementRoutes() end
	end
	local admitted, status, seen = false, nil, {}
	for _, original in ipairs(selectedRoutes or self:GetAnnouncementWireRoutes()) do
		local route = {}
		for key, value in pairs(original) do route[key] = value end
		if route.requiresChannelJoin and not route.channelName then route.channelName = self.announcementChannelName end
		local key = route.distribution .. ":" .. tostring(route.channelName or route.target or "")
		if not seen[key] then
			seen[key] = true
			local ok, result
			if self:GetTransportState() and not direct then
				ok, result = self:QueueTransportWire(wireMessage, debugContext, route, self:BuildCommSendOptions(wireMessage, route, completion))
			else
				ok, result = self:SendTransportNow(wireMessage, debugContext, route, direct and "departure" or nil)
			end
			admitted, status = admitted or ok, ok and result or status or result
		end
	end
	return admitted, status
end

function QuestTogether:ShouldSuppressDuplicateCommMessage(sender, message, duplicateWindow)
	local nowSeconds = self.API and self.API.GetTime and self.API.GetTime() or 0
	duplicateWindow = duplicateWindow or COMM_DUPLICATE_WINDOW_SECONDS
	self.recentCommMessageSignatures = self.recentCommMessageSignatures or {}

	local signatures = self.recentCommMessageSignatures
	local signature = (self:NormalizeMemberName(sender) or "") .. "|" .. SafeAddonString(self, message or "", "")
	local seenAt = signatures[signature]
	if seenAt and nowSeconds >= seenAt and nowSeconds - seenAt <= duplicateWindow then return true end
	-- A fixed ring bounds both storage and per-message work during busy-zone
	-- bursts. Replacing the signature table (reset/tests) resets the ring too.
	local index = rawget(self, "recentCommSignatureIndex")
	if not index or index.signatures ~= signatures then
		index = { signatures = signatures, ring = {}, cursor = 0 }
		self.recentCommSignatureIndex = index
	end
	index.cursor = index.cursor % 4096 + 1
	local old = index.ring[index.cursor]
	if old and signatures[old.key] == old.at then signatures[old.key] = nil end
	index.ring[index.cursor] = { key = signature, at = nowSeconds }
	signatures[signature] = nowSeconds
	return false
end

function QuestTogether:IsQueuedCommRequestCurrent(wire)
	if wire:sub(1, 5) ~= "QCMP|" then return true end
	local request = self:DecodeQuestCompareRequestPayload(wire:sub(6))
	local pending = request and self:GetPendingQuestCompare(request.requestId)
	return pending ~= nil and not self:IsIgnoredPlayerName(pending.targetName)
		and pending.targetName == self:NormalizeMemberName(request.targetName)
end

QuestTogether:RegisterCommSendPolicy("QCMP", function(addon, wire, _, options)
	options.isCurrent = function() return addon:IsQueuedCommRequestCurrent(wire) end
end)

function QuestTogether:AnnouncementChannelChatFilter(_, _, ...)
	-- Only channel metadata identifies this channel. Scanning message text and
	-- player names both hides unrelated conversations and touches secret data.
	return MatchesAnnouncementChannelName(self, select(4, ...)) or MatchesAnnouncementChannelName(self, select(9, ...))
		or self:IsGeographicChannelName(select(4, ...)) or self:IsGeographicChannelName(select(9, ...))
end

function QuestTogether:RegisterAnnouncementChannelChatFilters()
	if self.announcementChannelChatFiltersRegistered then
		return
	end
	if not self.API or not self.API.AddMessageEventFilter then
		return
	end

	self.announcementChannelChatFilterFunc = self.announcementChannelChatFilterFunc
		or function(...)
			return QuestTogether:AnnouncementChannelChatFilter(...)
		end

	for _, eventName in ipairs(ANNOUNCEMENT_CHANNEL_FILTER_EVENTS) do
		self.API.AddMessageEventFilter(eventName, self.announcementChannelChatFilterFunc)
	end
	self.announcementChannelChatFiltersRegistered = true
end

function QuestTogether:UnregisterAnnouncementChannelChatFilters()
	if not self.announcementChannelChatFiltersRegistered then
		return
	end
	if not self.API or not self.API.RemoveMessageEventFilter or not self.announcementChannelChatFilterFunc then
		self.announcementChannelChatFiltersRegistered = nil
		return
	end

	for _, eventName in ipairs(ANNOUNCEMENT_CHANNEL_FILTER_EVENTS) do
		self.API.RemoveMessageEventFilter(eventName, self.announcementChannelChatFilterFunc)
	end
	self.announcementChannelChatFiltersRegistered = nil
end

function QuestTogether:HideAnnouncementChannelFromChatWindows(channelName)
	if
		not self.API
		or not self.API.GetNumChatWindows
		or not self.API.GetChatFrameByID
		or not self.API.RemoveChatWindowChannel
	then
		return
	end

	local maxWindows = SafeNumber(self, self.API.GetNumChatWindows()) or 0
	for chatFrameID = 1, maxWindows do
		local chatFrame = self.API.GetChatFrameByID(chatFrameID)
		if chatFrame then
			-- Some chat frames reject channel removal in edge states; keep cleanup best-effort.
			for _, name in ipairs(channelName and { channelName } or { self.announcementChannelName }) do
				pcall(self.API.RemoveChatWindowChannel, chatFrame, name)
			end
		end
	end
end

function QuestTogether:EnsureAnnouncementChannelJoined(channelName)
	if not channelName then
		return self:EnsureAnnouncementChannelJoined(self.announcementChannelName)
	end
	local cacheKey = channelName == self.announcementChannelName and "announcementChannelLocalID" or nil
	if not cacheKey and not self:IsGeographicChannelName(channelName) then return false end
	if not self.isEnabled then
		self:Debug("Skipping channel join because addon is disabled", "comms")
		return false
	end

	-- Existing permanent channels survive /reload too; they need our filters
	-- even when no JoinPermanentChannel call is necessary.
	self:RegisterAnnouncementChannelChatFilters()
	local currentLocalID = self:GetAnnouncementChannelLocalID(channelName)
	if currentLocalID then
		if cacheKey then self[cacheKey] = currentLocalID end
		local bindings = rawget(self, "announcementChannelBindings") or {}
		self.announcementChannelBindings = bindings
		if bindings[channelName] ~= currentLocalID and not self:IsRuntimeRestricted() then
			self:HideAnnouncementChannelFromChatWindows(channelName)
			bindings[channelName] = currentLocalID
		end
		return true
	end
	if cacheKey then self[cacheKey] = nil end
	if self.announcementChannelBindings then self.announcementChannelBindings[channelName] = nil end

	if not self.API or not self.API.JoinPermanentChannel then
		self:Debug("JoinPermanentChannel API unavailable", "comms")
		return false
	end

	local chatFrameId = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.GetID and DEFAULT_CHAT_FRAME:GetID()) or 1
	self:Debugf(
		"comms",
		"Joining announcement channel name=%s chatFrameId=%s",
		SafeAddonString(self, channelName),
		SafeAddonString(self, chatFrameId)
	)
	self.API.JoinPermanentChannel(channelName, nil, chatFrameId, 1)

	currentLocalID = self:GetAnnouncementChannelLocalID(channelName)
	if currentLocalID then
		if cacheKey then self[cacheKey] = currentLocalID end
		if self.HideAnnouncementChannelFromChatWindows then
			self:HideAnnouncementChannelFromChatWindows(channelName)
			self.announcementChannelBindings = self.announcementChannelBindings or {}
			self.announcementChannelBindings[channelName] = currentLocalID
		end
		self:Debugf("comms", "Joined announcement channel localID=%s", SafeAddonString(self, currentLocalID))
		return true
	end

	self:Debug("Unable to join announcement channel " .. SafeAddonString(self, channelName), "comms")
	return false
end

-- Stable partition using the public channel-order API, never ChatTypeInfo or
-- Blizzard frame fields. Non-QT channels retain their relative ordering.
function QuestTogether:MoveAnnouncementChannelsToEnd()
	if not self.isEnabled or self:IsRuntimeRestricted() or self:IsRuntimeRestrictionTypeActive("chat") then return false end
	local api = self.API or {}
	if not api.GetChatChannelList or not api.SwapChatChannelIndices then return false end
	local ok, list = pcall(api.GetChatChannelList)
	if not ok or not self:CanAccessTable(list) or #list > 90 or #list % 3 ~= 0 then return false end
	local channels, seen = {}, {}
	for i = 1, #list, 3 do
		local id, name = SafeChannelNumber(self, list[i]), SafeTrimAddonString(self, list[i + 1], "")
		if not id or id < 1 or id > 30 or id ~= math.floor(id) or name == "" or seen[id] then return false end
		seen[id] = true
		channels[#channels + 1] = { id = id, name = name, qt = MatchesAnnouncementChannelName(self, name) or self:IsGeographicChannelName(name) }
	end
	table.sort(channels, function(a, b) return a.id < b.id end)
	for i = 2, #channels do
		local j = i
		while j > 1 and not channels[j].qt and channels[j - 1].qt do
			if self:IsRuntimeRestricted() then return false end
			local swapped, result = pcall(api.SwapChatChannelIndices, channels[j - 1].id, channels[j].id)
			-- Native channel indices can change; never retain a stale receive fallback.
			self.announcementChannelLocalID = nil
			if not swapped or result ~= true then return false end
			channels[j - 1].qt, channels[j].qt = channels[j].qt, channels[j - 1].qt
			channels[j - 1].name, channels[j].name = channels[j].name, channels[j - 1].name
			j = j - 1
		end
	end
	-- Keep the human chat channel before the machine-only zone subscriptions.
	local firstQT, current
	for _, channel in ipairs(channels) do
		if channel.qt and not firstQT then firstQT = channel.id end
		if channel.name == self.announcementChannelName then current = channel.id end
	end
	if firstQT and current and current ~= firstQT then
		local swapped, result = pcall(api.SwapChatChannelIndices, current, firstQT)
		self.announcementChannelLocalID = nil
		if not swapped or result ~= true then return false end
	end
	self.announcementChannelLocalID = self:GetAnnouncementChannelLocalID()
	return true
end

function QuestTogether:ScheduleAnnouncementChannelOrder()
	if not self.isEnabled or not self.API.GetChatChannelList or not self.API.SwapChatChannelIndices
		or not self.API.Delay or rawget(self, "channelOrderWork") then return end
	local work = {}
	self.channelOrderWork = work
	self.API.Delay(0.2, function()
		if rawget(self, "channelOrderWork") ~= work then return end
		self:MoveAnnouncementChannelsToEnd()
		self.channelOrderWork = nil
	end)
end

function QuestTogether:CHANNEL_COUNT_UPDATE()
	local state = rawget(self, "geographicCommsState")
	if state then state.reconciledChannels = nil end
	self:ScheduleAnnouncementChannelOrder()
end
function QuestTogether:CHANNEL_UI_UPDATE() self:ScheduleAnnouncementChannelOrder() end

function QuestTogether:LeaveAnnouncementChannel()
	if self.API and self.API.LeaveChannelByName then
		self:Debugf(
			"comms",
			"Leaving announcement channel name=%s",
			SafeAddonString(self, self.announcementChannelName)
		)
		-- Channel leave can fail if Blizzard already removed it; no need to hard fail disable.
		pcall(self.API.LeaveChannelByName, self.announcementChannelName)
	end
	self.announcementChannelLocalID = nil
	self:ResetCommsState()
	if self.UnregisterAnnouncementChannelChatFilters then
		self:UnregisterAnnouncementChannelChatFilters()
	end
end

function QuestTogether:ResetCommsState()
	if self.ResetRuntimeCoordinator then self:ResetRuntimeCoordinator() end
	self:ResetTransport()
	self:ClosePartyChatReminderPreview()
	self:ResetPartyChatReminder()
	if self.ResetGeographicComms then self:ResetGeographicComms() end
	self.channelOrderWork = nil
	self.announcementChannelBindings = nil
	self.localizedQuestTitles = nil
	if self.ResetPartyJoin then self:ResetPartyJoin() end
	if self.ResetPartyVisuals then self:ResetPartyVisuals() end
	if self.ResetQTPlayerPresence then self:ResetQTPlayerPresence() end
	if self.ResetPlayerLocations then self:ResetPlayerLocations() end
	if self.ResetPartyQuestCompare then self:ResetPartyQuestCompare() end
	self.pendingPingRequests = {}
	self.pendingQuestCompareRequests = {}
	self.recentCommMessageSignatures = {}
	self.recentCommSignatureIndex = nil
	-- Pending timer closures retain the old state only; they cannot send after
	-- disable/re-enable or remove work from a replacement queue.
	self.questCompareResponseQueue = nil
	self.questCompareResponseCache = nil
	self.questCompareLocalRevision = nil
	self.pingPageQueue = nil
	self.pingReplyState = nil
	if self.ResetDeveloperDiagnostics then self:ResetDeveloperDiagnostics() end
	self.directCommPeers = nil
	if self.ResetPlayerDetails then self:ResetPlayerDetails() end
	if self.ResetPeerSnapshots then self:ResetPeerSnapshots() end
end

function QuestTogether:GetPlayerPingMetadata()
	local fullName = self:GetPlayerFullName() or self:GetPlayerName() or "Unknown"
	local realmName = ""
	if not self:UsesRegionalPlayerNames() then
		local unitRealm
		if self.API.UnitFullName then
			local _
			_, unitRealm = self.API.UnitFullName("player")
		end
		realmName = SafeTrimAddonString(self, unitRealm, "")
		if realmName == "" and self.API.GetRealmName then realmName = self.API.GetRealmName() end
	end
	local className, classFile
	if self.API.UnitClass then
		className, classFile = self.API.UnitClass("player")
	end
	local raceName = nil
	if self.API.UnitRace then
		raceName = self.API.UnitRace("player")
	end
	local level = self.API.UnitLevel and self.API.UnitLevel("player") or ""
	local locationInfo = (not self.CanPublishPlayerLocation or self:CanPublishPlayerLocation())
		and not self:IsRuntimeRestricted() and self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or {}
	local numericCoordX = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordX) or nil
	local numericCoordY = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordY) or nil
	local warMode
	if locationInfo and self:SupportsWarMode() == true then
		warMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	end

	return {
		senderName = SafeAddonString(self, fullName or "", ""),
		realmName = SafeAddonString(self, realmName or "", ""),
		raceName = SafeAddonString(self, raceName or "", ""),
		classFile = SafeAddonString(self, classFile or "", ""),
		className = SafeAddonString(self, className or "", ""),
		addonVersion = SafeAddonString(self, self:GetAddonVersion() or "", ""),
		level = level and SafeAddonString(self, level, "") or "",
		zoneName = locationInfo and SafeAddonString(self, locationInfo.zoneName or "", "") or "",
		coordX = numericCoordX and string.format("%.1f", numericCoordX) or "",
		coordY = numericCoordY and string.format("%.1f", numericCoordY) or "",
		warMode = warMode == nil and "" or (warMode and "1" or "0"),
		mapID = locationInfo and SafeAddonString(self, locationInfo.mapID or "", "") or "",
	}
end

function QuestTogether:BuildChannelRequestId(prefix)
	local requestPrefix = SafeAddonString(self, prefix or "req", "req")
	self.channelRequestSequence = (self.channelRequestSequence or 0) + 1
	return string.format(
		"%s-%s-%d-%d-%d",
		requestPrefix,
		SafeAddonString(self, self:GetPlayerName() or "player", "player"),
		math.floor((self.API.GetTime and self.API.GetTime() or 0) * 1000),
		self.API.Random and self.API.Random(1000, 9999) or 1000,
		self.channelRequestSequence
	)
end

function QuestTogether:BuildLocalAnnouncementEvent(eventType, text, questId, extraData)
	local senderName = self:GetPlayerFullName() or self:GetPlayerName()
	local senderGUID = ""
	if self.API.UnitGUID then
		local okGuid, guidValue = pcall(self.API.UnitGUID, "player")
		if okGuid and not self:IsSecretValue(guidValue) then
			senderGUID = SafeAddonString(self, guidValue or "", "")
		end
	end
	local sanitizedText = self:SanitizeAnnouncementText(text)
	local iconAsset, iconKind = self:GetAnnouncementIconInfo(eventType, questId)
	local sanitizedExtraData = self:SanitizeAnnouncementExtraData(extraData)
	if sanitizedExtraData.iconAsset then
		iconAsset = sanitizedExtraData.iconAsset
		iconKind = sanitizedExtraData.iconKind or iconKind
	end
	local locationInfo = (not self.CanPublishPlayerLocation or self:CanPublishPlayerLocation())
		and self.GetPlayerAnnouncementLocationInfo and self:GetPlayerAnnouncementLocationInfo() or nil
	local numericCoordX = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordX) or nil
	local numericCoordY = locationInfo and self.SafeToNumber and self:SafeToNumber(locationInfo.coordY) or nil
	local warMode
	if locationInfo and self:SupportsWarMode() == true then
		warMode = self:NormalizeAnnouncementWarModeValue(locationInfo.warMode)
	end
	if sanitizedText == "" then
		return nil
	end

	return self:SanitizeAnnouncementEventData({
		version = ANNOUNCEMENT_WIRE_VERSION,
		occurredAt = self:GetAnnouncementServerTime(),
		eventType = SafeAddonString(self, eventType or "", ""),
		senderGUID = SafeAddonString(self, senderGUID or "", ""),
		classFile = SafeAddonString(self, self:GetPlayerClassFile() or "", ""),
		senderName = SafeAddonString(self, senderName or "", ""),
		text = sanitizedText,
		questId = questId and SafeAddonString(self, questId, "") or "",
		iconAsset = SafeAddonString(self, iconAsset or "", ""),
		iconKind = SafeAddonString(self, iconKind or "", ""),
		zoneName = locationInfo and SafeAddonString(self, locationInfo.zoneName or "", "") or "",
		coordX = numericCoordX and string.format("%.1f", numericCoordX) or "",
		coordY = numericCoordY and string.format("%.1f", numericCoordY) or "",
		warMode = warMode == nil and "" or (warMode and "1" or "0"),
		emoteToken = sanitizedExtraData.emoteToken or "",
		eventFacts = sanitizedExtraData.eventFacts or (self.BuildAnnouncementFacts and self:BuildAnnouncementFacts(eventType)) or "",
		mapID = locationInfo and locationInfo.mapID or nil,
	})
end

function QuestTogether:BuildAnnouncementEventForUnit(unitToken, eventType, text)
	if type(unitToken) ~= "string" or unitToken == "" then
		return nil
	end

	local sanitizedText = self:SanitizeAnnouncementText(text)
	if sanitizedText == "" then
		return nil
	end

	local senderName = self:GetUnitFullName(unitToken)
	if not senderName then
		return nil
	end

	local _, classFile = self.API.UnitClass(unitToken)
	local senderGUID = ""
	if self.API.UnitGUID then
		local okGuid, guidValue = pcall(self.API.UnitGUID, unitToken)
		if okGuid and not self:IsSecretValue(guidValue) then
			senderGUID = SafeAddonString(self, guidValue or "", "")
		end
	end
	return self:SanitizeAnnouncementEventData({
		version = ANNOUNCEMENT_WIRE_VERSION,
		eventType = SafeAddonString(self, eventType or "", ""),
		senderGUID = SafeAddonString(self, senderGUID or "", ""),
		classFile = SafeAddonString(self, classFile or "", ""),
		senderName = senderName,
		text = sanitizedText,
		questId = "",
		iconAsset = "",
		iconKind = "",
		zoneName = "",
		coordX = "",
		coordY = "",
		warMode = "",
		emoteToken = "",
	})
end

function QuestTogether:BuildPingResponse(requestId)
	if type(requestId) ~= "string" or requestId == "" then
		return nil
	end

	local payload = self:GetPlayerPingMetadata()
	payload.requestId = requestId
	return payload
end

function QuestTogether:BuildQuestCompareEntries()
	if self.IsWorkBlocked and self:IsWorkBlocked("quest_snapshot_refresh") then return nil, "restricted" end
	local entries = {}
	local numQuestLogEntries = SafeNumber(self, self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries())
	if not numQuestLogEntries or numQuestLogEntries < 0 or numQuestLogEntries ~= math.floor(numQuestLogEntries) then return nil end
	-- Bound reads as well as retained packets. Headers count as rows, so leave
	-- ample room above the maximum number of shareable quest entries.
	if numQuestLogEntries > QUEST_COMPARE_MAX_ENTRIES * 5 then return nil, "limit" end
	local seenQuestIds = {}

	for questLogIndex = 1, numQuestLogEntries do
		local questInfo = self.API.GetQuestLogInfo and self.API.GetQuestLogInfo(questLogIndex)
		if type(questInfo) ~= "table" or not self:CanAccessTable(questInfo) then return nil end
		if not self:CanAccessValue(questInfo.isHeader) or not self:CanAccessValue(questInfo.isHidden) then return nil end
		local questId = self:NormalizeQuestID(questInfo.questID)
		if not questInfo.isHeader and not questId then return nil end
		if not questInfo.isHeader and not questInfo.isHidden then
			local questTitle = self:SafeTrimString(questInfo.title, "")
			if questTitle == "" then return nil end
			-- Duplicate IDs can indicate rows shifted during the scan. A receiver
			-- deduplicates IDs, so advertising duplicates would never complete.
			if seenQuestIds[questId] then return nil end
			seenQuestIds[questId] = true
			if #entries >= QUEST_COMPARE_MAX_ENTRIES then return nil, "limit" end
			local shareableLabel = self:GetQuestShareableStatusLabel(questId)
			local isPushable
			if shareableLabel == "Yes" then
				isPushable = true
			elseif shareableLabel == "No" then
				isPushable = false
			end
			-- Blizzard's quest tracker uses QuestMixin:IsComplete(), backed by
			-- C_QuestLog.IsComplete. GetInfo/legacy title flags can disagree (for
			-- example delivery quests), so keep their flag only as a fallback.
			local complete = self:CanAccessValue(questInfo.isComplete) and questInfo.isComplete == true or false
			if type(self.API.IsQuestComplete) == "function" then
				local ok, value = pcall(self.API.IsQuestComplete, questId)
				if ok and self:CanAccessValue(value) and type(value) == "boolean" then complete = value end
			end
			entries[#entries + 1] = {
				questId = SafeAddonString(self, questId, ""),
				questTitle = questTitle,
				isComplete = complete,
				isPushable = isPushable,
			}
		end
	end
	local finalCount = SafeNumber(self, self.API.GetNumQuestLogEntries and self.API.GetNumQuestLogEntries())
	if finalCount ~= numQuestLogEntries then return nil end

	return entries
end

function QuestTogether:SendQuestCompareEntry(requestId, entryData, selectedRoutes, completion, snapshotId)
	if type(requestId) ~= "string" or requestId == "" or type(entryData) ~= "table" then
		return false
	end
	if entryData.objectiveIndex then
		return self:SendWireMessageToAnnouncementRoutes("QCOB|" .. self:EncodeQuestCompareObjectivePayload(requestId, entryData, snapshotId),
			"quest compare objective", selectedRoutes, false, completion)
	end

	local wireMessage = self:SerializeWireMessage(
		QUEST_COMPARE_ENTRY_COMMAND,
		self:EncodeQuestCompareEntryPayload({
			requestId = requestId,
			senderName = self:GetPlayerFullName() or self:GetPlayerName() or "",
			classFile = self:GetPlayerClassFile() or "",
			questId = entryData.questId or "",
			questTitle = entryData.questTitle or "",
			isComplete = entryData.isComplete and true or false,
			isPushable = entryData.isPushable,
			objectiveCount = entryData.objectiveCount,
			snapshotId = snapshotId,
		})
	)
	return self:SendWireMessageToAnnouncementRoutes(
		wireMessage,
		"quest compare entry requestId=" .. SafeAddonString(self, requestId, ""),
		selectedRoutes, false, completion
	)
end

function QuestTogether:SendQuestCompareDone(requestId, count, selectedRoutes, completion, snapshotId, revision, unchanged)
	if type(requestId) ~= "string" or requestId == "" then
		return false
	end

	local wireMessage = self:SerializeWireMessage(
		QUEST_COMPARE_DONE_COMMAND,
		self:EncodeQuestCompareDonePayload({
			requestId = requestId,
			senderName = self:GetPlayerFullName() or self:GetPlayerName() or "",
			classFile = self:GetPlayerClassFile() or "",
			count = SafeNumber(self, count) or 0,
			supportsShareRequests = true,
			supportsObjectives = true,
			snapshotId = snapshotId,
			revision = revision, unchanged = unchanged,
		})
	)
	if #wireMessage > ADDON_MESSAGE_MAX_BYTES and revision and not unchanged then
		return self:SendQuestCompareDone(requestId, count, selectedRoutes, completion, snapshotId)
	end
	return self:SendWireMessageToAnnouncementRoutes(
		wireMessage,
		"quest compare done requestId=" .. SafeAddonString(self, requestId, ""),
		selectedRoutes, false, completion
	)
end

-- A content revision is a session-scoped identity, not a request identity.
-- Fresh requests validate the current primitive snapshot; equal content reuses
-- one immutable array without retransmitting its entries.
function QuestTogether:BuildRevisionedQuestCompareEntries(objectiveQuestId)
	local entries, reason = self:BuildQuestCompareResponseEntries(objectiveQuestId)
	if not entries or objectiveQuestId then return entries, reason end
	local fields = {}
	for _, entry in ipairs(entries) do
		fields[#fields + 1] = table.concat({ tostring(entry.questId), self:EscapePayload(entry.questTitle or ""),
			entry.isComplete and "1" or "0", entry.isPushable == nil and "?" or (entry.isPushable and "1" or "0") }, ",")
	end
	table.sort(fields)
	local fingerprint = table.concat(fields, ";")
	local previous, now = rawget(self, "questCompareLocalRevision"), self.API.GetTime()
	local generation = rawget(self, "commsWorldGeneration") or 0
	if previous and previous.generation == generation and now >= previous.createdAt and previous.fingerprint == fingerprint then
		return previous.entries
	end
	self.questCompareRevisionSequence = (rawget(self, "questCompareRevisionSequence") or 0) + 1
	local revision = string.format("%d-%d-%d-%d", self:GetAnnouncementServerTime() or 0,
		math.floor(now * 1000), self.API.Random(1, 1000000000), self.questCompareRevisionSequence)
	local copy = {}
	for index, entry in ipairs(entries) do
		copy[index] = { questId = entry.questId, questTitle = entry.questTitle,
			isComplete = entry.isComplete, isPushable = entry.isPushable }
	end
	copy.revision = revision
	self.questCompareLocalRevision = { entries = copy, fingerprint = fingerprint, createdAt = now, generation = generation }
	return copy
end

local function RevisionFits(addon, requestId, count, snapshotId, revision)
	return #addon:EncodeQuestCompareDonePayload({ requestId = requestId, senderName = addon:GetPlayerFullName(),
		classFile = addon:GetPlayerClassFile(), count = count, supportsShareRequests = true, supportsObjectives = true,
		snapshotId = snapshotId, revision = revision, unchanged = true }) <= ADDON_MESSAGE_MAX_BYTES - 5
end
local function UpdateCompareRevision(addon, job)
	job.revision = job.supportsRevision and job.entries and job.entries.revision or nil
	if job.revision and not RevisionFits(addon, job.requestId, #job.entries, job.snapshotId, job.revision) then job.revision = nil end
	job.unchanged = job.revision ~= nil and job.knownRevision == job.revision
	if job.unchanged then job.nextEntry = #job.entries + 1 end
end

-- Retrying one correlation must replay the same log, even if quests change
-- after the first transmission. At most four snapshots (100 entries each) are
-- retained independently of the 128-packet active send budget.
function QuestTogether:GetQuestCompareResponseCache(requester, requestId, entries)
	local now = self.API.GetTime()
	local cache = rawget(self, "questCompareResponseCache")
	if not cache then cache={}; self.questCompareResponseCache=cache end
	for key, record in pairs(cache) do
		if now < record.createdAt or now >= record.expiresAt then cache[key]=nil end
	end
	local key = (requester or "") .. "|" .. requestId
	local record = cache[key]
	if record then return record.entries, not record.entries and "retired" or nil, record.snapshotId end
	if not entries then return nil end
	local active = {}
	for _, job in ipairs(self.questCompareResponseQueue and self.questCompareResponseQueue.jobs or {}) do
		if job.requesterName ~= requester then active[(job.requesterName or "").."|"..job.requestId]=true end
	end
	local count, snapshots, oldest, at, oldestRecord, recordAt = 0,0
	for id, item in pairs(cache) do
		count=count+1
		if not active[id] and (not recordAt or item.createdAt<recordAt) then oldestRecord,recordAt=id,item.createdAt end
		if item.entries then
			snapshots=snapshots+1
			if not active[id] and (not at or item.createdAt<at) then oldest,at=id,item.createdAt end
		end
	end
	if snapshots>=QUEST_COMPARE_MAX_QUEUED_RESPONSES then
		if not oldest then return nil,"capacity" end
		-- Retain a small tombstone so an evicted correlation is never rebuilt
		-- from a different log and merged with the receiver's original entries.
		cache[oldest].entries=nil
	end
	if count>=64 and oldestRecord then cache[oldestRecord]=nil end
	self.questCompareSnapshotSequence = (rawget(self, "questCompareSnapshotSequence") or 0) + 1
	local snapshotId = string.format("%d-%d-%d-%d", self:GetAnnouncementServerTime() or 0,
		math.floor(now * 1000), self.API.Random(1, 1000000000), self.questCompareSnapshotSequence)
	cache[key]={entries=entries,snapshotId=snapshotId,createdAt=now,expiresAt=now+QUEST_COMPARE_CACHE_LIFETIME_SECONDS}
	return entries, nil, snapshotId
end

function QuestTogether:DrainQuestCompareResponses()
	local queue = self.questCompareResponseQueue
	if not queue then return end
	self:PumpBulkTransfer(queue, {
		field = "questCompareResponseQueue", interval = QUEST_COMPARE_SEND_INTERVAL_SECONDS,
		retryInterval = QUEST_COMPARE_RETRY_INTERVAL_SECONDS,
		isCurrent = function(job)
			local distribution = job.routes[1].distribution
			if job.requesterName and self:IsIgnoredPlayerName(job.requesterName) then return false end
			if (GROUP_ANNOUNCEMENT_DISTRIBUTIONS[distribution] or job.routes[1].requiresGroup)
				and job.requesterName and not self:IsGroupedSender(job.requesterName) then return false end
			if GROUP_ANNOUNCEMENT_DISTRIBUTIONS[distribution] and job.requesterName then
				job.routes[1].distribution = self:GetGroupAnnouncementDistribution() or distribution
			end
			return true
		end,
		prepare = function(job)
			local now, finished = self.API.GetTime(), false
			if not job.entries then

				if now >= job.snapshotRetryAt then
					local entries, reason = self:GetQuestCompareResponseCache(job.requesterName, job.requestId)
					if not entries and reason~="retired" then entries,reason=self:BuildRevisionedQuestCompareEntries(job.objectiveQuestId) end
					-- Combat/map/encounter deferrals have not attempted a quest read.
					-- Keep the job until its deadline without spending read retries.
					if reason ~= "restricted" then job.snapshotAttempts = job.snapshotAttempts + 1 end
					job.snapshotRetryAt = now + QUEST_COMPARE_RETRY_INTERVAL_SECONDS
					-- Later jobs have not sent any entries. Keep their immutable cache,
					-- but return their packet reservations when a deferred head becomes
					-- readable; otherwise those reservations can prevent its own start.
					if entries and #entries <= QUEST_COMPARE_MAX_ENTRIES and queue.packets + #entries > QUEST_COMPARE_MAX_QUEUED_PACKETS then
						for index = #queue.jobs, 2, -1 do
							local waiting = queue.jobs[index]
							if waiting.entries then
								queue.packets = queue.packets - waiting.remaining + 1
								waiting.entries, waiting.remaining = nil, 1
							end
							if queue.packets + #entries <= QUEST_COMPARE_MAX_QUEUED_PACKETS then break end
						end
					end
					if reason == "limit" or reason == "retired" or (entries and #entries > QUEST_COMPARE_MAX_ENTRIES) then
						finished = true
					elseif entries then
						local unused
						job.entries, unused, job.snapshotId = self:GetQuestCompareResponseCache(job.requesterName, job.requestId, entries)
						UpdateCompareRevision(self, job)
						if not job.unchanged and not job.objectiveQuestId and ((job.supportsSnapshotIdentity and self:GetTransportState()) or #entries > 40) then self:SendQuestCompareDone(job.requestId, #entries, job.routes, nil, job.supportsSnapshotIdentity and job.snapshotId, job.revision) end
						local extra = job.unchanged and 0 or #entries
						queue.packets = queue.packets + extra
						job.remaining = extra + 1

					elseif job.snapshotAttempts >= QUEST_COMPARE_MAX_SEND_ATTEMPTS then
						finished = true
					end
				end
			end
			return job.entries ~= nil, finished and "snapshot unavailable" or nil
		end,
		send = function(job, completion)
			local entry = job.entries[job.nextEntry]
			if entry then
				return self:SendQuestCompareEntry(job.requestId, entry, job.routes, completion, job.supportsSnapshotIdentity and job.snapshotId)
			end
			return self:SendQuestCompareDone(job.requestId, job.objectiveQuestId and (#job.entries > 0 and 1 or 0) or #job.entries,
				job.routes, completion, job.supportsSnapshotIdentity and job.snapshotId, job.revision, job.unchanged)
		end,
		accept = function(job)
			local finished = job.entries[job.nextEntry] == nil
			queue.packets, job.remaining = queue.packets - 1, job.remaining - 1
			job.nextEntry = job.nextEntry + 1
			return finished
		end,
		release = function(job, reason)
			queue.packets = queue.packets - job.remaining
			if reason then self:RecordCommsDiagnostic("failedComparisons", "response failed requestId=" .. job.requestId) end
		end,
	})
end

function QuestTogether:HandleQuestCompareRequest(requestData)
	if not self.isEnabled or type(requestData) ~= "table" or type(requestData.requestId) ~= "string" or requestData.requestId == "" then
		return false
	end

	local targetName = self:NormalizeMemberName(requestData.targetName) or requestData.targetName
	if self:IsIgnoredPlayerName(requestData.requesterName) then return false end
	local playerName = self:GetPlayerFullName() or self:GetPlayerName() or ""
	local normalizedPlayerName = self:NormalizeMemberName(playerName) or playerName
	if targetName ~= normalizedPlayerName then
		return false
	end

	local queue = self.questCompareResponseQueue
	if not queue then
		queue = { jobs = {}, packets = 0 }
		self.questCompareResponseQueue = queue
	end
	-- OnCommReceived replaces payload identity with the authenticated transport
	-- sender. A new request from that player supersedes their unfinished reply;
	-- missing identities cannot establish ownership of another queued job.
	local requesterName = self:NormalizeMemberName(requestData.requesterName)
	local superseded, supersededPackets = {}, 0
	for index, job in ipairs(queue.jobs) do
		if job.requestId == requestData.requestId and job.requesterName == requesterName then
			local entries = self:GetQuestCompareResponseCache(requesterName, job.requestId)
			if not job.unchanged and not job.objectiveQuestId and entries and ((job.supportsSnapshotIdentity and self:GetTransportState()) or #entries > 40) then self:SendQuestCompareDone(job.requestId, #entries, job.routes, nil, job.supportsSnapshotIdentity and job.snapshotId, job.revision) end
			return true
		end
		if requesterName and job.requesterName == requesterName then
			superseded[#superseded + 1] = index
			supersededPackets = supersededPackets + job.remaining
		end
	end
	if #queue.jobs - #superseded >= QUEST_COMPARE_MAX_QUEUED_RESPONSES then return false end
	local entries, reason, snapshotId = self:GetQuestCompareResponseCache(requesterName, requestData.requestId)
	if reason=="retired" then
		if not requestData.supportsSnapshotIdentity then return false end
		-- Only negotiated receivers can detect a rebuilt generation. Their
		-- changed token forces a fresh correlation before any rows are committed.
		self.questCompareResponseCache[(requesterName or "") .. "|" .. requestData.requestId] = nil
		reason = nil
	end
	if not entries then entries,reason=self:BuildRevisionedQuestCompareEntries(requestData.objectiveQuestId) end
	local snapshotCount = entries and #entries
	if reason == "limit" or (entries and #entries > QUEST_COMPARE_MAX_ENTRIES)
		then
		self:RecordCommsDiagnostic("failedComparisons", "response queue full")
		return false
	end
	if entries then entries,reason,snapshotId=self:GetQuestCompareResponseCache(requesterName,requestData.requestId,entries) end
	local revision = requestData.supportsRevision and entries and entries.revision
	if revision and not RevisionFits(self, requestData.requestId, #entries, snapshotId, revision) then revision = nil end
	local unchanged = revision ~= nil and requestData.knownRevision == revision
	local packetCount = entries and not unchanged and #entries + 1 or 1
	local waitingForCapacity = queue.packets - supersededPackets + packetCount > QUEST_COMPARE_MAX_QUEUED_PACKETS
	if waitingForCapacity then entries, reason, packetCount = nil, "capacity", 1 end
	-- Admit atomically, preserving unrelated callers' order and the existing
	-- cooldown timer. Its callback drains current jobs, never a captured old job.
	for index = #superseded, 1, -1 do
		table.remove(queue.jobs, superseded[index])
	end
	queue.packets = queue.packets - supersededPackets
	-- Prefer the requester alone; older peers retain the proven incoming route.
	-- Cross-realm party replies never depend on a realm-local channel.
	local distribution = requestData.replyDistribution
	if distribution == "WHISPER" and not requesterName then return false end
	if distribution ~= "CHANNEL" and distribution ~= "WHISPER" and not GROUP_ANNOUNCEMENT_DISTRIBUTIONS[distribution] then
		distribution = self:GetGroupAnnouncementDistribution() or "CHANNEL"
	end
	queue.jobs[#queue.jobs + 1] = {
		requestId = requestData.requestId,
		requesterName = requesterName,
		objectiveQuestId = requestData.objectiveQuestId,
		supportsSnapshotIdentity = requestData.supportsSnapshotIdentity == true,
		supportsRevision = requestData.supportsRevision == true and (not entries or revision ~= nil),
		knownRevision = requestData.knownRevision,
		revision = revision,
		unchanged = unchanged == true,
		snapshotId = snapshotId,
		entries = entries,
		nextEntry = unchanged and entries and #entries + 1 or 1,
		remaining = packetCount,
		attempts = 0,
		snapshotAttempts = (entries or reason == "restricted" or reason == "capacity") and 0 or 1,
		snapshotRetryAt = self.API.GetTime() + QUEST_COMPARE_RETRY_INTERVAL_SECONDS,
		expiresAt = self.API.GetTime() + QUEST_COMPARE_RESPONSE_LIFETIME_SECONDS,
		routes = distribution == "WHISPER" and { { distribution = "WHISPER", target = requesterName, requiresGroup = self:IsGroupedSender(requesterName) } }
			or (requesterName and self:GetTargetedCommRoutes(requesterName, { { distribution = distribution, requiresChannelJoin = distribution == "CHANNEL" } })
			or { { distribution = distribution, requiresChannelJoin = distribution == "CHANNEL" } }),
	}
	queue.packets = queue.packets + packetCount
	-- Count-before-entries is already part of the reordered-delivery protocol.
	-- Announce large jobs immediately so waiting callers can extend their own
	-- deadline, even when three other full logs are ahead of them in the queue.
	if not unchanged and not requestData.objectiveQuestId and snapshotCount and ((requestData.supportsSnapshotIdentity and self:GetTransportState()) or snapshotCount > 40) then
		self:SendQuestCompareDone(requestData.requestId, snapshotCount, queue.jobs[#queue.jobs].routes, nil, requestData.supportsSnapshotIdentity and snapshotId, revision)
	end
	self:DrainQuestCompareResponses()
	return true
end

function QuestTogether:HandleQuestCompareEntry(entryData)
	if type(entryData) ~= "table" or type(entryData.requestId) ~= "string" or entryData.requestId == "" then
		return false
	end

	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	local pending = self:GetPendingQuestCompare(entryData.requestId)
	if type(pending) ~= "table" then
		return false
	end

	local senderName = self:NormalizeMemberName(entryData.senderName) or entryData.senderName
	if pending.targetName ~= senderName then
		return false
	end
	local questId = self:NormalizeQuestID(entryData.questId)
	if not questId or (pending.objectiveQuestId and questId ~= pending.objectiveQuestId) then
		return false
	end
	if not self:AcceptQuestCompareSnapshot(pending, entryData.snapshotId) then return false end
	pending.entriesByQuestId = pending.entriesByQuestId or {}
	if pending.entriesByQuestId[questId] or (pending.count or 0) >= QUEST_COMPARE_MAX_ENTRIES then
		return false
	end
	pending.entriesByQuestId[questId] = entryData
	pending.entryOrder = pending.entryOrder or {}
	pending.entryOrder[#pending.entryOrder + 1] = questId
	pending.lastProgressAt, pending.receivedData = self.API.GetTime(), true

	if type(entryData.classFile) == "string" and entryData.classFile ~= "" then
		pending.classFile = entryData.classFile
	end
	pending.count = (pending.count or 0) + 1
	if pending.count > 40 then pending.largeResponse = true end
	self:TryCompleteQuestCompare(entryData.requestId)
	return true
end

function QuestTogether:TryCompleteQuestCompare(requestId)
	local pending = self:GetPendingQuestCompare(requestId)
	if not pending or pending.expectedCount == nil or (pending.count or 0) ~= pending.expectedCount then
		return false
	end
	if pending.objectiveQuestId and pending.expectedCount > 0 then
		local entry = pending.entriesByQuestId[pending.objectiveQuestId]
		if not entry then return false end
		if entry.objectiveCount then
			local objectives = {}
			for index = 1, entry.objectiveCount do
				if not pending.objectives or not pending.objectives[index] then return false end
				objectives[index] = pending.objectives[index]
			end
			entry.objectives = objectives
		end
	end
	self:ClearPendingQuestCompare(requestId, pending)
	-- Partial generations remain private. Publish only after entries, objectives,
	-- and the completion marker agree, including after a legacy fresh-ID retry.
	for _, questId in ipairs(pending.entryOrder or {}) do
		local entry = pending.entriesByQuestId[questId]
		if pending.receiver then pending.receiver.onEntry(entry)
		elseif self.PrintQuestCompareMessage then self:PrintQuestCompareMessage(pending.targetName, entry, pending.classFile) end
	end
	if pending.receiver then
		pending.receiver.onDone(pending.supportsShareRequests == true, pending.supportsObjectives == true, pending.classFile, pending.revision)
	elseif self.PrintQuestCompareDone then
		self:PrintQuestCompareDone(pending.targetName, pending.count or 0, pending.classFile)
	end
	return true
end

function QuestTogether:HandleQuestCompareDone(doneData)
	if type(doneData) ~= "table" or type(doneData.requestId) ~= "string" or doneData.requestId == "" then
		return false
	end

	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	local pending = self:GetPendingQuestCompare(doneData.requestId)
	if type(pending) ~= "table" then
		return false
	end

	local senderName = self:NormalizeMemberName(doneData.senderName) or doneData.senderName
	if pending.targetName ~= senderName then
		return false
	end
	local expectedCount = SafeNumber(self, doneData.count)
	if not expectedCount or expectedCount < 0 or expectedCount > (pending.objectiveQuestId and 1 or QUEST_COMPARE_MAX_ENTRIES) or expectedCount ~= math.floor(expectedCount) then
		return false
	end

	if type(doneData.classFile) == "string" and doneData.classFile ~= "" then
		pending.classFile = doneData.classFile
	end
	if not self:AcceptQuestCompareSnapshot(pending, doneData.snapshotId) then return false end
	if doneData.unchanged then
		-- Only the exact requested baseline may satisfy an unchanged certificate.
		-- Never infer completeness from a revision alone or reuse partial rows.
		if pending.objectiveQuestId or not pending.knownRevision or doneData.revision ~= pending.knownRevision
			or not pending.previousEntries or #pending.previousOrder ~= expectedCount or (pending.count or 0) ~= 0 then return false end
		pending.entriesByQuestId, pending.entryOrder = pending.previousEntries, pending.previousOrder
		pending.count = expectedCount
	end
	pending.revision = doneData.revision
	-- The completion marker can arrive on one route before entries from the
	-- other. Retain the request until the advertised unique entries arrive.
	if pending.expectedCount == nil then pending.lastProgressAt = self.API.GetTime() end
	pending.expectedCount = expectedCount
	if expectedCount > 40 then pending.largeResponse = true end
	pending.supportsShareRequests = doneData.supportsShareRequests == true
	pending.supportsObjectives = doneData.supportsObjectives == true
	self:TryCompleteQuestCompare(doneData.requestId)
	return true
end

function QuestTogether:RequestQuestCompare(speakerName, receiver)
	local targetName = self:NormalizeMemberName(speakerName) or SafeAddonString(self, speakerName or "", "")
	if targetName == "" then
		return false
	end

	if not receiver and self.PrintQuestCompareStart then
		self:PrintQuestCompareStart(targetName, self:GetGroupedSenderClassFile(targetName))
	end

	local playerName = self:GetPlayerFullName() or self:GetPlayerName() or ""
	local normalizedPlayerName = self:NormalizeMemberName(playerName) or playerName
	if targetName == normalizedPlayerName then
		local localEntries = self:BuildQuestCompareEntries()
		if not localEntries then
			self:PrintConsoleAnnouncement(L("Quest comparison unavailable while the quest log is updating."), targetName)
			return false
		end
		for _, entryData in ipairs(localEntries) do
			if self.PrintQuestCompareMessage then
				self:PrintQuestCompareMessage(targetName, entryData, self:GetPlayerClassFile())
			end
		end
		if self.PrintQuestCompareDone then
			self:PrintQuestCompareDone(targetName, #localEntries, self:GetPlayerClassFile())
		end
		return true
	end

	if not self.isEnabled then
		return false
	end

	local requestId = self:BuildChannelRequestId("qcmp")
	self.pendingQuestCompareRequests = self.pendingQuestCompareRequests or {}
	local pendingRequest = {
		startedAt = self.API.GetTime(), lastProgressAt = self.API.GetTime(),
		logicalRequestId = requestId, wireRequestId = requestId,
		targetName = targetName,
		classFile = self:GetGroupedSenderClassFile(targetName),
		receiver = receiver,
		objectiveQuestId = receiver and receiver.objectiveQuestId,
		count = 0, entriesByQuestId = {}, entryOrder = {},
	}
	self.pendingQuestCompareRequests[requestId] = pendingRequest
	if receiver and ValidCompareSnapshotID(receiver.knownRevision) and type(receiver.previousEntries) == "table" and not receiver.objectiveQuestId then
		local entries, order = {}, {}
		for id, entry in pairs(receiver.previousEntries) do
			if type(entry) == "table" and self:NormalizeQuestID(entry.questId) == self:NormalizeQuestID(id) then
				local copy = {}; for key, value in pairs(entry) do copy[key] = value end
				local questID = self:NormalizeQuestID(id)
				entries[questID], order[#order + 1] = copy, questID
			end
		end
		if #order <= QUEST_COMPARE_MAX_ENTRIES then
			pendingRequest.knownRevision, pendingRequest.previousEntries, pendingRequest.previousOrder = receiver.knownRevision, entries, order
		end
	end
	local generation = rawget(self,"commsWorldGeneration") or 0
	local function Current()
		return (rawget(self,"commsWorldGeneration") or 0) == generation and self.isEnabled and not self.isLoggingOut
			and self.pendingQuestCompareRequests[requestId] == pendingRequest and not self:IsIgnoredPlayerName(targetName)
	end
	local function Fail()
		self:ClearPendingQuestCompare(requestId, pendingRequest)
		if receiver then receiver.onTimeout()
		elseif self.isEnabled and self.PrintConsoleAnnouncement then
			self:PrintConsoleAnnouncement(string.format(L("Quest comparison timed out (%d quests received)."), pendingRequest.count or 0),
				pendingRequest.targetName, pendingRequest.classFile, "QUEST_PROGRESS")
		end
	end
	local function Retire()
		if self.pendingQuestCompareRequests[requestId] == pendingRequest and self.isEnabled
			and not self:IsIgnoredPlayerName(targetName) and (rawget(self,"commsWorldGeneration") or 0) ~= generation then
			-- The consumer is still current across a loading screen. Settle it so
			-- PQL can refresh again instead of retaining Loading without a request.
			Fail()
		else self:ClearPendingQuestCompare(requestId, pendingRequest) end
	end
	local function Timeout()
		if self.pendingQuestCompareRequests[requestId] ~= pendingRequest then
			self:ClearPendingQuestCompare(requestId, pendingRequest)
			return
		end
		local remaining = pendingRequest.startedAt + QUEST_COMPARE_LARGE_TIMEOUT_SECONDS - self.API.GetTime()
		if (pendingRequest.largeResponse or pendingRequest.legacyRecovery) and remaining > 0 then
			self.API.Delay(remaining, Timeout); return
		end
		-- Fresh-ID retries must retransmit an entire old-client log. Give an
		-- actively arriving final transfer a short grace, never an unbounded wait.
		local grace = remaining + 60
		if pendingRequest.legacyRecovery and pendingRequest.receivedData and grace > 0
			and self.API.GetTime() - pendingRequest.lastProgressAt < 30 then
			self.API.Delay(math.min(30, grace), Timeout); return
		end
		Fail()
	end
	self.API.Delay(QUEST_COMPARE_TIMEOUT_SECONDS, Timeout)
	local function Send(fresh)
		if fresh then
			if pendingRequest.snapshotId == false then pendingRequest.legacyRecovery = true end
			local previous = pendingRequest.wireRequestId
			if previous ~= requestId then self.pendingQuestCompareRequests[previous] = nil end
			pendingRequest.wireRequestId = self:BuildChannelRequestId("qcmp")
			pendingRequest.entriesByQuestId, pendingRequest.entryOrder, pendingRequest.objectives = {}, {}, nil
			pendingRequest.count, pendingRequest.expectedCount, pendingRequest.snapshotId = 0, nil, nil
			pendingRequest.receivedData = nil
			pendingRequest.supportsShareRequests, pendingRequest.supportsObjectives = nil, nil
			pendingRequest.lastProgressAt = self.API.GetTime()
			self.pendingQuestCompareRequests[pendingRequest.wireRequestId] = pendingRequest
		end
		local wireMessage = self:SerializeWireMessage(QUEST_COMPARE_REQUEST_COMMAND, self:EncodeQuestCompareRequestPayload({
			requestId = pendingRequest.wireRequestId, requesterName = playerName, targetName = targetName,
			objectiveQuestId = receiver and receiver.objectiveQuestId, supportsSnapshotIdentity = true,
			supportsRevision = not (receiver and receiver.objectiveQuestId), knownRevision = pendingRequest.knownRevision,
		}))
		return self:SendWireMessageToAnnouncementRoutes(wireMessage, "quest compare request requestId=" .. pendingRequest.wireRequestId,
			self:GetTargetedCommRoutes(targetName, receiver and receiver.routes))
	end
	-- A responder can lose its immutable cache on zoning/reload. Move to a new
	-- wire correlation; old packets cannot repopulate the replacement buffer.
	local restarts = 0
	pendingRequest.restart = function()
		if pendingRequest.restartPending then return end
		pendingRequest.restartPending = true
		self.API.Delay(0.1, function()
			if not Current() then Retire(); return end
			pendingRequest.restartPending = nil
			restarts = restarts + 1
			if restarts > 4 or not Send(true) then Fail() end
		end)
	end
	if not Send(false) then self:ClearPendingQuestCompare(requestId, pendingRequest); return false end
	local retries = 0
	local function Recover()
		if not Current() then Retire(); return end
		if pendingRequest.restartPending then self.API.Delay(30, Recover); return end
		local modern = type(pendingRequest.snapshotId) == "string"
		-- Legacy responders cannot prove snapshot identity. Wait for actual
		-- progress to stop, then retry from scratch with a new wire request ID.
		-- Modern immutable responses may safely merge retransmitted packets.
		local silence = not pendingRequest.receivedData and (pendingRequest.largeResponse and 240 or 120) or 30
		if not modern and self.API.GetTime() - pendingRequest.lastProgressAt < silence then
			self.API.Delay(30, Recover); return
		end
		if retries >= ((pendingRequest.largeResponse or pendingRequest.legacyRecovery) and 20 or 4) then
			if not pendingRequest.largeResponse and not pendingRequest.legacyRecovery then self.API.Delay(30, Recover) end
			return
		end
		retries = retries + 1
		Send(not modern)
		self.API.Delay(30, Recover)
	end
	self.API.Delay(30, Recover)
	return true, requestId
end

function QuestTogether:IsAnnouncementChannelEvent(channel, localID, name)
	channel = SafePrimitiveString(self, channel, "")
	name = SafePrimitiveString(self, name, "")
	if GROUP_ANNOUNCEMENT_DISTRIBUTIONS[channel] then
		return true
	end

	if channel ~= "CHANNEL" then
		return false
	end

	if name ~= "" then
		return MatchesAnnouncementChannelName(self, name) or self:IsGeographicChannelName(name)
	end

	local expectedLocalID = SafeChannelNumber(self, self.announcementChannelLocalID)
	local incomingLocalID = SafeChannelNumber(self, localID)
	return incomingLocalID ~= nil and incomingLocalID > 0
		and (expectedLocalID == incomingLocalID or self:IsGeographicChannelEvent(channel, incomingLocalID))
end

function QuestTogether:SendAnnouncementEvent(eventType, text, questId, extraData)
	if not self.isEnabled then
		return false
	end

	local eventData = self:BuildLocalAnnouncementEvent(eventType, text, questId, extraData)
	if not eventData then
		self:Debugf(
			"comms",
			"Failed to build local announcement event eventType=%s",
			SafeAddonString(self, eventType, "")
		)
		return false
	end

	return self:SendAnnouncementWireEvent(eventData)
end

function QuestTogether:GetSafeRemoteCompletionEmote(emoteToken)
	if not self:CanAccessValue(emoteToken) or type(emoteToken) ~= "string" then
		return nil
	end
	local token = string.lower(self:SafeTrimString(emoteToken, ""))
	if REMOTE_CELEBRATION_EMOTES[token] then
		return token
	end
	return nil
end

function QuestTogether:PlayRemoteCelebrationEmote(eventData, nearbyUnitToken, senderName)
	if type(eventData) ~= "table" or not self.isEnabled or self:IsRuntimeRestricted()
		or self:IsRuntimeRestrictionTypeActive("chat") then
		return false
	end
	local optionKey = eventData.eventType == "PLAYER_LEVEL_UP" and "emoteOnNearbyPlayerLevelUp"
		or "emoteOnNearbyPlayerQuestCompletion"
	if not self:GetOption(optionKey) then
		return false
	end

	-- Revalidate immediately before the action: aliases and plates can be
	-- recycled, and coordinate proximity says nothing about another layer.
	local api = self.API or {}
	if not self:CanAccessValue(nearbyUnitToken) or type(nearbyUnitToken) ~= "string"
		or not api.CanTargetUnitForEmote or not api.DoEmote then return false end
	local ok, targetable = pcall(api.CanTargetUnitForEmote, nearbyUnitToken)
	if not ok or not self:CanAccessValue(targetable) or targetable ~= true then return false end
	local matched, matches = pcall(self.DoesUnitTokenMatchSender, self, nearbyUnitToken, eventData.senderGUID, senderName)
	if not matched or not self:CanAccessValue(matches) or matches ~= true then return false end

	local token = self:GetSafeRemoteCompletionEmote(eventData.emoteToken)
	if not token then
		return false
	end

	self.API.DoEmote(token, nearbyUnitToken)
	return true
end

function QuestTogether:SendAnnouncementWireEvent(eventData)
	if not self.isEnabled or type(eventData) ~= "table" then
		return false
	end
	eventData = self:SanitizeAnnouncementEventData(eventData)
	if not eventData then
		return false
	end
	if self.CanPublishPlayerLocation and not self:CanPublishPlayerLocation() then
		eventData.coordX, eventData.coordY, eventData.mapID, eventData.zoneName = "", "", nil, ""
	end

	local geographic = rawget(self, "geographicCommsState")
	if geographic and eventData.eventId == "" then
		geographic.eventSequence = (geographic.eventSequence or 0) + 1
		eventData.eventId = geographic.session .. "-" .. geographic.eventSequence
	end
	local payload = self:EncodeAnnouncementPayload(eventData)
	-- Metadata itself can exhaust the packet. Do not report a successful send
	-- for an announcement that the receiver must reject for having no text.
	if not self:DecodeAnnouncementPayload(payload) then
		self:RecordCommsDiagnostic("invalidMessages", "announcement metadata leaves no room for text")
		return false
	end
	local command = eventData.eventType == "PLAYER_LEVEL_UP" and LEVEL_UP_COMMAND or ANNOUNCEMENT_COMMAND
	local wireMessage = self:SerializeWireMessage(command, payload)
	return self:SendWireMessageToAnnouncementRoutes(
		wireMessage,
		"announcement eventType="
			.. SafeAddonString(self, eventData.eventType, "")
			.. " sender="
			.. SafeAddonString(self, eventData.senderName, "")
	)
end

function QuestTogether:SendPingRequest(target, debugRequest)
	if rawget(self, "isLocalDeveloper") ~= true then return false, L("Ping is unavailable.") end
	if not self.isEnabled then
		return false, L("QuestTogether is disabled.")
	end

	local requestId = self:BuildChannelRequestId("ping")
	local requesterName = self:GetPlayerFullName() or self:GetPlayerName() or ""
	local requestData = self:PrepareDeveloperPingRequest({ requestId=requestId, requesterName=requesterName,
		supportsDirectComms=true, supportsPagedPong=true, supportsLargePong=debugRequest == true }, target, debugRequest)
	if not requestData then return false, L("Ping is unavailable.") end
	requestId = requestData.requestId
	self.pendingPingRequests = self.pendingPingRequests or {}
	local now = SafeNumber(self, self.API.GetTime and self.API.GetTime()) or 0
	local pendingRequest = { responders = {}, remoteReplies = 0, responderCount = 0, startedAt = now, expiresAt = now + PING_REQUEST_TIMEOUT_SECONDS,
		targetName=requestData.targetName, developerRequest=requestData.developerRequest, debugRequest=requestData.debugRequest,
		supportsLargePong=requestData.supportsLargePong }
	self.pendingPingRequests[requestId] = pendingRequest
	local function ExpireRequest()
		if self.pendingPingRequests and self.pendingPingRequests[requestId] == pendingRequest then
			local current = SafeNumber(self, self.API.GetTime and self.API.GetTime())
			if current and current >= pendingRequest.startedAt and current < pendingRequest.expiresAt then
				-- The first negotiated large-report page can extend this one
				-- request. Keep the original timer fenced to its request object.
				self.API.Delay(pendingRequest.expiresAt - current, ExpireRequest)
				return
			end
			self:Debugf("comms", "ping complete id=%s remoteReplies=%d", requestId, pendingRequest.remoteReplies)
			if pendingRequest.debugRequest and pendingRequest.remoteReplies == 0 then self:Print(L("Diagnostics unavailable.")) end
			self.pendingPingRequests[requestId] = nil
		end
	end
	self.API.Delay(PING_REQUEST_TIMEOUT_SECONDS, ExpireRequest)

	local wireMessage = self:SerializeWireMessage(PING_REQUEST_COMMAND, self:EncodePingRequestPayload(requestData))
	local routes = requestData.targetName and { { distribution="WHISPER", target=requestData.targetName } }
		or { { distribution="CHANNEL",channelName=self.announcementChannelName,requiresChannelJoin=true } }
	if
		not self:SendWireMessageToAnnouncementRoutes(
			wireMessage,
			"ping request id=" .. SafeAddonString(self, requestId, ""), routes
		)
	then
		self.pendingPingRequests[requestId] = nil
		return false, L("Unable to send ping request over any QuestTogether comm route.")
	end
	local retained = {}
	for id, request in pairs(self.pendingPingRequests) do
		if id ~= requestId then
			retained[#retained + 1] = { id = id, startedAt = type(request) == "table" and request.startedAt or 0 }
		end
	end
	table.sort(retained, function(a, b)
		if a.startedAt == b.startedAt then return a.id < b.id end
		return a.startedAt < b.startedAt
	end)
	for index = 1, #retained - PING_MAX_PENDING_REQUESTS + 1 do
		self.pendingPingRequests[retained[index].id] = nil
	end

	local localResponse = self:BuildPingResponse(requestId)
	if not target and localResponse and self.HandlePingResponse then
		self:HandlePingResponse(localResponse)
	end

	return true, requestId
end

function QuestTogether:SendPingResponse(requestId, selectedRoutes, supportsPages, developerRequest)
	local responseData = self:BuildPingResponse(requestId)
	if not responseData then
		return false
	end
	if developerRequest and not self:AddDeveloperPingMetadata(responseData, developerRequest) then return false end

	local payload = self:EncodePingResponsePayload(responseData, supportsPages)
	local pageVersion = developerRequest and developerRequest.debugRequest and developerRequest.supportsLargePong and 2 or 1
	if developerRequest and developerRequest.debugRequest and not self:BuildPongPages(requestId, payload, pageVersion) then
		-- Even an older requester must receive an explicit failure rather than
		-- wait five minutes for a response that was never queued. Keep metadata.
		responseData.diagnosticText = "diagnostics.status=report_too_large\n"
			.. "diagnostics.encodedBytes=" .. #payload .. "\n"
			.. "diagnostics.detail=Report exceeds the negotiated transfer limit. Update both clients and retry."
		payload = self:EncodePingResponsePayload(responseData, true)
	end
	if supportsPages and #payload + #PING_RESPONSE_COMMAND + 1 > ADDON_MESSAGE_MAX_BYTES then
		return self:SendPagedPong(requestId, payload, selectedRoutes, developerRequest ~= nil, pageVersion)
	end
	-- Developer snapshots share the same paced, revocable path, even at one page.
	if developerRequest then return self:SendPagedPong(requestId, payload, selectedRoutes, true, pageVersion) end
	local wireMessage = self:SerializeWireMessage(PING_RESPONSE_COMMAND, payload)
	return self:SendWireMessageToAnnouncementRoutes(
		wireMessage,
		"ping response id=" .. SafeAddonString(self, requestId, ""),
		selectedRoutes
	)
end

function QuestTogether:HandlePingRequest(requestData, channel, localID, channelName)
	if type(requestData) ~= "table" or type(requestData.requestId) ~= "string" or requestData.requestId == "" then
		return false
	end
	if requestData.developerRequest and not requestData.developerVerified then
		return self:QueueDeveloperPingVerification(requestData, requestData.requesterName, function(verified)
			self:HandlePingRequest(verified, channel, localID, channelName)
		end)
	end
	self:Debugf("comms", "ping request received id=%s sender=%s", requestData.requestId, requestData.requesterName or "")
	local routes
	if GROUP_ANNOUNCEMENT_DISTRIBUTIONS[channel] then
		routes = { { distribution = channel } }
	elseif channel == "CHANNEL" then
		local incomingName = SafeTrimAddonString(self, channelName, "")
		incomingName = string.lower(string.match(incomingName, "^%d+%.%s+(.+)$") or incomingName)
		local incomingID = SafeChannelNumber(self, localID)
		local names = { self.announcementChannelName }
		local geographic = rawget(self, "geographicCommsState")
		for name in pairs(geographic and geographic.subscriptions or {}) do names[#names + 1] = name end
		for _, name in ipairs(names) do
			if incomingName == string.lower(name)
				or (incomingName == "" and incomingID and incomingID == self:GetAnnouncementChannelLocalID(name)) then
				routes = { { distribution = "CHANNEL", channelName = name, requiresChannelJoin = true } }
				break
			end
		end
		if not routes then return false end
	elseif channel == "WHISPER" and requestData.developerVerified then
		routes = { { distribution="WHISPER",target=requestData.requesterName } }
	elseif channel ~= nil then
		return false
	end
	-- The discovery request is broadcast; its report belongs only to its requester.
	-- Preserve the proven incoming route for older receivers.
	if requestData.requesterName then
		if requestData.supportsDirectComms then self:RememberDirectCommPeer(requestData.requesterName, true) end
		routes = self:GetTargetedCommRoutes(requestData.requesterName, routes)
	end
	if requestData.supportsDirectComms then routes = { { distribution="WHISPER",target=requestData.requesterName } } end
	local developerRequest = requestData.developerVerified and requestData or nil
	if self:GetTransportState() then return self:SchedulePingReply(requestData.requestId, routes, requestData.supportsPagedPong, developerRequest) end
	return self:SendPingResponse(requestData.requestId, routes, requestData.supportsPagedPong, developerRequest)
end

function QuestTogether:HandlePingResponse(responseData)
	if type(responseData) ~= "table" or type(responseData.requestId) ~= "string" or responseData.requestId == "" then
		return false
	end

	self.pendingPingRequests = self.pendingPingRequests or {}
	local pending = self.pendingPingRequests[responseData.requestId]
	if not pending then
		self:Debugf("comms", "ping reply unmatched id=%s sender=%s", responseData.requestId, responseData.senderName or "")
		return false
	end
	local now = SafeNumber(self, self.API.GetTime and self.API.GetTime())
	if type(pending) == "table" and pending.expiresAt
		and (not now or now < pending.startedAt or now >= pending.expiresAt) then
		self.pendingPingRequests[responseData.requestId] = nil
		self:Debugf("comms", "ping reply expired id=%s sender=%s", responseData.requestId, responseData.senderName or "")
		return false
	end
	local senderName = self:NormalizeMemberName(responseData.senderName)
	if not senderName then
		return false
	end
	if type(pending) == "table" and pending.targetName and pending.targetName ~= senderName then return false end
	if type(pending) ~= "table" then
		pending = { responders = {} }
		self.pendingPingRequests[responseData.requestId] = pending
	end
	pending.responders = pending.responders or {}
	if pending.responders[senderName] then
		self:Debugf("comms", "ping reply duplicate id=%s sender=%s", responseData.requestId, senderName)
		return false
	end
	if (pending.responderCount or 0) >= PING_MAX_RESPONDERS then return false end
	pending.responders[senderName] = true
	pending.responderCount = (pending.responderCount or 0) + 1
	if not self:IsSelfSender(senderName) then pending.remoteReplies = (pending.remoteReplies or 0) + 1 end
	self:Debugf("comms", "ping reply accepted id=%s sender=%s elapsed=%.3f", responseData.requestId, senderName,
		now and pending.startedAt and now - pending.startedAt or 0)

	if self.PrintPingResponse then
		self:PrintPingResponse(responseData)
	end
	self:AcceptDeveloperPingResponse(responseData, pending)
	-- A completed, correlated response is a presence witness at its sample
	-- time, not its arrival time. Legacy replies have only the request's lower
	-- bound, so a reply queued before departure cannot resurrect that player.
	local sampledAt = pending.startedAt
	local stamp, serverNow = SafeNumber(self, responseData.sampledAt), self:GetAnnouncementServerTime()
	if stamp and serverNow and now then
		local age = serverNow - stamp
		if age >= -30 and age < self:GetGeographicSnapshotLifetime() then sampledAt = now - math.max(0, age) end
	end
	if sampledAt and self.RecordPeerPresenceFromSnapshot then
		self:RecordPeerPresenceFromSnapshot(senderName, sampledAt)
	else
		self:RecordQTPlayerPresence(senderName, true)
	end
	return true
end

function QuestTogether:SendBubbleAnnouncementTest(text, senderName)
	if not self.isEnabled then
		return false, L("QuestTogether is disabled.")
	end

	local eventData = nil
	if self.API.UnitExists and self.API.UnitExists("target") then
		if not self.API.UnitIsPlayer or not self.API.UnitIsPlayer("target") then
			return false, L("Your target must be a player.")
		end

		eventData = self:BuildAnnouncementEventForUnit("target", "QUEST_PROGRESS", text)
		if not eventData then
			return false, L("Unable to build a test announcement from your target.")
		end
	else
		local trimmedSenderName = SafeTrimAddonString(self, senderName or "", "")
		if trimmedSenderName == "" then
			return false, L("Target a nearby player or provide a visible player name.")
		end
		if not self.FindVisiblePlayerNameplateForSender then
			return false, L("Visible player lookup is unavailable.")
		end

		local nameplate = self:FindVisiblePlayerNameplateForSender("", trimmedSenderName)
		local unitToken = nameplate and nameplate.GetUnit and nameplate:GetUnit() or nil
		if not unitToken or unitToken == "" then
			return false, L("No visible nearby player matched that name.")
		end

		eventData = self:BuildAnnouncementEventForUnit(unitToken, "QUEST_PROGRESS", text)
		if not eventData then
			return false, L("Unable to build a test announcement for that player.")
		end
	end

	-- This is a local preview of the selected player. A network packet claiming
	-- that identity cannot pass the receiver's authoritative transport check.
	if not self:HandleAnnouncementEvent(eventData, false) then
		return false, L("The local preview was suppressed by your announcement settings.")
	end

	return true, eventData.senderName
end

function QuestTogether:ShouldShowAnnouncementsForRemoteSender(senderName, hasNearbyNameplate)
	if self:IsIgnoredPlayerName(senderName) then return false end
	local isGrouped = self:IsGroupedSender(senderName)
	local scope = self:GetOption("showProgressFor")

	if scope == "party_only" then
		return isGrouped
	end

	return isGrouped or hasNearbyNameplate
end

function QuestTogether:ShouldPlayRemoteEmoteForAnnouncement(eventData)
	if type(eventData) ~= "table" then
		return false
	end

	return eventData.eventType == "QUEST_COMPLETED"
		or eventData.eventType == "WORLD_QUEST_COMPLETED"
		or eventData.eventType == "BONUS_OBJECTIVE_COMPLETED"
		or eventData.eventType == "PLAYER_LEVEL_UP"
end

function QuestTogether:HandleAnnouncementEvent(eventData, isLocal)
	eventData = self:SanitizeAnnouncementEventData(eventData)
	if type(eventData) ~= "table" then
		self:Debug("Rejected announcement event because payload was invalid", "comms")
		return false
	end
	local allowedByOption = self:ShouldDisplayAnnouncementType(eventData.eventType)
	if not allowedByOption then
		self:RecordCommsDiagnostic(
			"suppressedAnnouncements",
			"option event=" .. eventData.eventType .. " quest=" .. eventData.questId
		)
		return false
	end

	local senderName = self:NormalizeMemberName(eventData.senderName) or eventData.senderName
	if not isLocal and self:IsIgnoredPlayerName(senderName) then return false end
	local classFile = eventData.classFile
	local isGrouped = false
	if (not classFile or classFile == "") and not isLocal then
		classFile = self:GetGroupedSenderClassFile(senderName)
	end

	local nearbyNameplate = nil
	local hasNearbyNameplate = false
	local nearbyUnitToken = nil
	local nearbyByLocation = false
	local hasNearbySignal = false
	if not isLocal and self.FindVisiblePlayerNameplateForSender then
		nearbyNameplate = self:FindVisiblePlayerNameplateForSender(eventData.senderGUID, senderName)
		hasNearbyNameplate = nearbyNameplate ~= nil
	end
	if not isLocal and not hasNearbyNameplate and self.FindNearbyPlayerUnitTokenForSender then
		nearbyUnitToken = self:FindNearbyPlayerUnitTokenForSender(eventData.senderGUID, senderName)
	end
	if
		not isLocal
		and not hasNearbyNameplate
		and nearbyUnitToken == nil
		and self.IsAnnouncementSenderNearbyByLocation
	then
		nearbyByLocation = self:IsAnnouncementSenderNearbyByLocation(
			eventData, eventData.eventType == "LOOKING_FOR_QUEST_PARTNERS"
		)
	end
	hasNearbySignal = hasNearbyNameplate or nearbyUnitToken ~= nil or nearbyByLocation
	isGrouped = self:IsGroupedSender(senderName)
	local forceAllChatLogs = not isLocal and self:GetOption("showChatLogs") and self:GetOption("devLogAllAnnouncements")
	local allowRemoteDisplay = isLocal or self:ShouldShowAnnouncementsForRemoteSender(senderName, hasNearbySignal)

	if not allowRemoteDisplay and not forceAllChatLogs then
		self:RecordCommsDiagnostic(
			"suppressedAnnouncements",
			"scope sender=" .. senderName .. " event=" .. eventData.eventType .. " quest=" .. eventData.questId
		)
		return false
	end

	-- This is an addon-owned sanitized copy. Keep the wire/party-chat text intact.
	local originalText = eventData.text
	if not isLocal and (self:GetOption("showChatLogs") or self:GetOption("showChatBubbles"))
		and self.LocalizeAnnouncementEvent then
		eventData.text = self:LocalizeAnnouncementEvent(eventData)
	end
	local isLevelUp = eventData.eventType == "PLAYER_LEVEL_UP"
	if not isLevelUp and self:GetOption("showChatLogs") then
		local shouldPrint = isLocal or isGrouped or hasNearbySignal or forceAllChatLogs
		if shouldPrint then
			self:PrintConsoleAnnouncement(
				eventData.text,
				senderName,
				classFile,
				eventData.eventType,
				eventData.iconAsset,
				eventData.iconKind,
				eventData
			)
		end
	end

	if
		not isLocal
		and allowRemoteDisplay
		and hasNearbySignal
		and self:ShouldPlayRemoteEmoteForAnnouncement(eventData)
	then
		local emoteTarget = nearbyUnitToken
		if not emoteTarget and hasNearbyNameplate and nearbyNameplate then
			local getUnit = self:GetAccessibleFrameMember(nearbyNameplate, "GetUnit")
			if type(getUnit) == "function" then
				local ok, unit = pcall(getUnit, nearbyNameplate)
				if ok and self:CanAccessValue(unit) and type(unit) == "string" then emoteTarget = unit end
			end
		end
		self:PlayRemoteCelebrationEmote(eventData, emoteTarget, senderName)
	end

	if not isLevelUp and self:GetOption("showChatBubbles") then
		if isLocal then
			if not self:GetOption("hideMyOwnChatBubbles") and self.ShowAnnouncementBubbleOnUnitNameplate then
				self:ShowAnnouncementBubbleOnUnitNameplate(
					"player",
					eventData.text,
					eventData.eventType,
					eventData.iconAsset,
					eventData.iconKind
				)
			end
		elseif allowRemoteDisplay and hasNearbyNameplate and self.ShowAnnouncementBubbleOnNameplate then
			self:ShowAnnouncementBubbleOnNameplate(
				nearbyNameplate,
				eventData.text,
				eventData.eventType,
				eventData.iconAsset,
				eventData.iconKind,
				senderName
			)
		end
	end
	self:RecordCommsDiagnostic(
		"acceptedAnnouncements",
		string.format(
			"local=%s sender=%s event=%s quest=%s bubbles=%s hideOwn=%s text=%s",
			tostring(isLocal == true),
			senderName,
			eventData.eventType,
			eventData.questId,
			tostring(self:GetOption("showChatBubbles")),
			tostring(self:GetOption("hideMyOwnChatBubbles")),
			string.sub(originalText, 1, 220)
		)
	)

	return true
end

-- Shared by forwarding and its reminder; unreadable group data is not proof
-- of a non-QT member. Always read current native identities.
function QuestTogether:GetNonQTPartyMembers()
	local api = self.API or {}
	local function ReadBoolean(query, ...)
		if type(query) ~= "function" then return nil end
		local ok, value = pcall(query, ...)
		if ok and self:CanAccessValue(value) and type(value) == "boolean" then return value end
	end
	local raid = ReadBoolean(api.IsInRaid)
	if raid == nil then return nil end
	if raid then return {} end
	local instance = ReadBoolean(api.IsInInstanceGroup)
	if instance == nil then return nil end
	if not instance then
		local party = ReadBoolean(api.IsInParty)
		if party == nil then return nil end
		if not party then return {} end
	end
	local missingQT = {}
	for index = 1, 4 do
		local unit = "party" .. index
		local exists = ReadBoolean(api.UnitExists, unit)
		if exists == nil then return nil end
		if exists then
			local ok, name = pcall(self.GetUnitFullName, self, unit)
			if not ok or not self:CanAccessValue(name) or type(name) ~= "string" or name == ""
				or #name > 120 or name:find("[%c|]") then
				return nil
			end
			if not self:IsKnownQTPlayer(name) then missingQT[#missingQT + 1] = name end
		end
	end
	table.sort(missingQT)
	return missingQT, instance and "INSTANCE_CHAT" or "PARTY"
end

-- Only local publication reaches this path; received events are never relayed.
function QuestTogether:AnnounceToNonQTParty(eventData)
	if not self.isEnabled or not self:GetOption("announceToNonQTParty")
		or self.suppressLocalAnnouncementDisplayDuringTests
		or not self:ShouldDisplayAnnouncementType(eventData.eventType) then return false end
	if self:IsRuntimeRestrictionTypeActive("chat") then return false end
	local api = self.API or {}
	if type(api.SendPartyChatMessage) ~= "function" then return false end
	local members, distribution = self:GetNonQTPartyMembers()
	if not members or #members == 0 or not self:UpdatePartyChatReminder(members) then return false end
	-- Plain text only: custom QT links/textures are not usable by non-QT clients.
	local text = SafeTrimAddonString(self, eventData.text, "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
	text = text:gsub("[%c]", " ")
	text = self:SafeTrimString(text, "")
	if text == "" then return false end
	local prefix = "[QT] "
	local ok, sent = pcall(api.SendPartyChatMessage, prefix .. TruncateUtf8(text, 255 - #prefix), distribution)
	return ok and sent == true
end

function QuestTogether:PublishAnnouncementEvent(eventType, text, questId, extraData)
	if self.API.UnitIsDeadOrGhost and self.API.UnitIsDeadOrGhost("player") then
		return false
	end

	local eventData = self:BuildLocalAnnouncementEvent(eventType, text, questId, extraData)
	if not eventData then
		self:Debugf(
			"comms",
			"PublishAnnouncementEvent dropped eventType=%s due to empty payload",
			SafeAddonString(self, eventType, "")
		)
		return false
	end

	self:SendAnnouncementWireEvent(eventData)
	self:AnnounceToNonQTParty(eventData)
	if self.suppressLocalAnnouncementDisplayDuringTests then
		return true
	end
	self:HandleAnnouncementEvent(eventData, true)
	return true
end

function QuestTogether:SendQTChannelChat(message)
	if not self.isEnabled or self:IsRuntimeRestrictionTypeActive("chat") then return false end
	message = SafeTrimAddonString(self, message, "")
	message = TruncateUtf8(message:gsub("[%c]", " "), 255)
	if message == "" or not self.API.SendChannelChatMessage then return false end
	if not self:EnsureAnnouncementChannelJoined(self.announcementChannelName) then return false end
	local id = self:GetAnnouncementChannelLocalID()
	if not id then return false end
	local ok, sent = pcall(self.API.SendChannelChatMessage, message, id)
	return ok and sent == true
end

function QuestTogether:ShouldShowQTChannelChatFromSender(name)
	if self:GetOption("qtChatScope") ~= "zone_only" or self:IsSelfSender(name) then return true end
	if self:IsRuntimeRestricted() then return false end
	local api = self.API or {}
	if not api.GetBestMapForUnit then return false end
	local ok, localMapID = pcall(api.GetBestMapForUnit, "player")
	localMapID = ok and self:SafeToNumber(localMapID) or nil
	local remoteMapID = self:GetRecentPlayerLocationMapID(name)
	return localMapID ~= nil and remoteMapID ~= nil and localMapID == remoteMapID
end

-- Handle once per event, never from the per-chat-frame suppression filter.
-- Human channel chat is not addon protocol traffic or evidence of QT presence.
function QuestTogether:CHAT_MSG_CHANNEL(_, message, sender, _, channelName, _, _, _, _, channelBaseName, _, _, senderGUID)
	if not self.isEnabled or self:GetOption("showQTChat") == false
		or self:IsRuntimeRestrictionTypeActive("chat") then return false end
	if not MatchesAnnouncementChannelName(self, channelBaseName)
		and not MatchesAnnouncementChannelName(self, channelName) then return false end
	local name = SafeTrimAddonString(self, sender, "")
	if name == "" then return false end
	name = self:NormalizeMemberName(name)
	if not name or self:IsIgnoredPlayerName(name) or not self:ShouldShowQTChannelChatFromSender(name) then return false end
	local text = SafePrimitiveString(self, message, "")
	-- Preserve link labels as plain text, without accepting user-supplied UI markup.
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
	text = TruncateUtf8(self:SafeTrimString(text:gsub("[%c]", " "), ""), 255)
	if text == "" then return false end
	local icon = "Interface\\AddOns\\QuestTogether\\Media\\ChatBubbleIcon"
	if self:GetOption("showChatLogs") then
		self:PrintConsoleAnnouncement(text, name, nil, "QT_CHAT", icon, "texture")
	end
	if self:GetOption("showChatBubbles") then
		if self:IsSelfSender(name) then
			if not self:GetOption("hideMyOwnChatBubbles") then
				self:ShowAnnouncementBubbleOnUnitNameplate("player", text, "QT_CHAT", icon, "texture")
			end
		else
			local plate = self:FindVisiblePlayerNameplateForSender(SafePrimitiveString(self, senderGUID, ""), name)
			if plate then self:ShowAnnouncementBubbleOnNameplate(plate, text, "QT_CHAT", icon, "texture", name) end
		end
	end
	return true
end

function QuestTogether:CHAT_MSG_ADDON(_, prefix, message, channel, sender, _, _, localID, name)
	self:OnCommReceived(prefix, message, channel, sender, localID, name)
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender, localID, name)
	if not self.isEnabled or SafePrimitiveString(self, prefix, "") ~= self.commPrefix then
		return
	end
	local safeMessage = SafePrimitiveString(self, message, "")
	if safeMessage == "" or #safeMessage > ADDON_MESSAGE_MAX_BYTES or safeMessage:find("\0", 1, true) then return end
	local safeTransportSender = SafeTrimAddonString(self, sender, "")
	local transportSenderName = safeTransportSender ~= "" and self:NormalizeMemberName(safeTransportSender) or nil
	if not transportSenderName then
		self:Debug("Rejected comm payload without an accessible transport sender", "comms")
		return
	end
	if safeMessage:sub(1, 5) == "PING|" or safeMessage:sub(1, 5) == "PONG|" then
		self:Debugf("comms", "ping packet command=%s sender=%s route=%s localID=%s channel=%s self=%s allowedRoute=%s",
			safeMessage:sub(1, 4), transportSenderName, SafePrimitiveString(self, channel, ""), SafeDebugString(localID),
			SafePrimitiveString(self, name, ""), tostring(self:IsSelfSender(safeTransportSender)),
			tostring(self:IsAnnouncementChannelEvent(channel, localID, name)))
	end
	if self:IsSelfSender(safeTransportSender) then
		return
	end
	if self.IsIgnoredPlayerName and self:IsIgnoredPlayerName(transportSenderName) then
		return
	end
	local isWhisper = SafePrimitiveString(self, channel, "") == "WHISPER"
	if isWhisper then
		local command, payload = self:DeserializeWireMessage(safeMessage)
		if command == "QTPH" then
			if self:HandlePlayerPhaseMessage(payload, transportSenderName) then
				self:RecordCommsTraffic("received", safeMessage)
			end
			return
		end
		if command == "QTHQ" or command == "QTHD" then
			if self:HandlePlayerDetailsMessage(command, payload, transportSenderName) then
				self:RecordCommsTraffic("received", safeMessage)
			end
			return
		end
		if command == "QTSR" or command == "QTSP" or command == "QTSX" then
			if self:HandleNearbyStreamMessage(command, payload, transportSenderName) then
				self:RecordCommsTraffic("received", safeMessage)
			end
			return
		end
		-- Direct traffic is a strict control allowlist, never an alternate path
		-- for announcements, chat, presence snapshots or location broadcasts.
		if not DIRECT_COMMANDS[command] then return end
	elseif not self:IsAnnouncementChannelEvent(channel, localID, name) then
		return
	end
	self:RecordCommsDiagnostic(
		"receivedMessages",
		string.format(
			"sender=%s route=%s bytes=%d",
			transportSenderName,
			SafePrimitiveString(self, channel, ""),
			#safeMessage
		)
	)
	self:RecordCommsTraffic("received", safeMessage)

	local command, payload = self:DeserializeWireMessage(safeMessage)
	if not command then
		self:Debug("Failed to deserialize incoming comm payload", "comms")
		return
	end
	-- Discovery has a shared response cooldown. Validate its narrow route before
	-- any dedup bookkeeping so a copy on another channel cannot suppress it.
	if command == "QTNAV" or command == "QTN2" then
		self:HandlePartyNavigationMessage(payload, transportSenderName, channel, command == "QTN2")
		return
	end
	if command == "QTDQ" then
		self:HandleGeographicDiscovery(payload, transportSenderName, channel, localID, name)
		return
	end
	local duplicateWindow = (command == PING_REQUEST_COMMAND or command == QUEST_COMPARE_REQUEST_COMMAND)
			and COMM_REQUEST_DUPLICATE_WINDOW_SECONDS
		or COMM_DUPLICATE_WINDOW_SECONDS
	local decodedAnnouncement
	local signatureMessage = safeMessage
	if command == ANNOUNCEMENT_COMMAND or command == LEVEL_UP_COMMAND then
		decodedAnnouncement = self:DecodeAnnouncementPayload(payload)
		if decodedAnnouncement and decodedAnnouncement.eventId ~= "" then
			signatureMessage = command .. "|" .. decodedAnnouncement.eventId
			duplicateWindow = 300
		end
	end
	-- Legacy presence packets have no sequence. Every transition must apply,
	-- including rapid departures/rejoins with otherwise identical content.
	if command ~= "QTPR" and self:ShouldSuppressDuplicateCommMessage(safeTransportSender, signatureMessage, duplicateWindow) then
		self:RecordCommsTraffic("duplicate", safeMessage)
		self:RecordCommsDiagnostic("duplicateMessages", "sender=" .. transportSenderName .. " command=" .. command)
		return
	end

	if command == "QTB1" then
		self:HandleGeographicSnapshot(payload, transportSenderName)
		return
	end
	if self:IsGeographicChannelEvent(channel, localID, name)
		and command ~= "ANN" and command ~= "LVL" and command ~= "PING" and command ~= "PONG" then return end
	if command == ANNOUNCEMENT_COMMAND or command == LEVEL_UP_COMMAND then
		local eventData = decodedAnnouncement
		if not eventData or (command == LEVEL_UP_COMMAND and eventData.eventType ~= "PLAYER_LEVEL_UP") then
			self:Debug("Failed to decode announcement payload", "comms")
			return
		end

		-- CHAT_MSG_ADDON supplies the authoritative sender. Never let a payload
		-- choose which visible player's nameplate receives the announcement.
		eventData.senderName = transportSenderName
		self:RecordAnnouncementLatency(eventData)
		if self.RecordQTPlayerPresence then self:RecordQTPlayerPresence(transportSenderName, true) end

		self:HandleAnnouncementEvent(eventData, false)
		return
	end

	if command == PING_REQUEST_COMMAND then
		local requestData = self:DecodePingRequestPayload(payload)
		if not requestData then
			self:Debug("Failed to decode ping request payload", "comms")
			return
		end
		requestData.requesterName = transportSenderName or requestData.requesterName
		self:RecordQTPlayerPresence(transportSenderName, true)
		self:HandlePingRequest(requestData, channel, localID, name)
		return
	end

	if command == PING_RESPONSE_COMMAND then
		local responseData = self:DecodePingResponsePayload(payload)
		if not responseData then
			self:Debug("Failed to decode ping response payload", "comms")
			return
		end
		responseData.senderName = transportSenderName
		-- Legacy replies also identify installed peers; ordered departure guards
		-- prevent this unsequenced observation from reviving a departed player.
		if self.RecordQTPlayerPresence then self:RecordQTPlayerPresence(transportSenderName, true) end
		self:ObserveAddonVersion(responseData.addonVersion)
		self:RememberPlayerAddonVersion(transportSenderName, responseData.addonVersion)
		if self:HandlePingResponse(responseData) and isWhisper then self:RememberDirectCommPeer(transportSenderName, true) end
		return
	end
	if command == "PONP" and isWhisper then
		self:HandlePongPage(payload, transportSenderName)
		return
	end

	if command == "QTPG" then self:HandlePartyVisualMetadata(payload, transportSenderName); return end
	if command == "QPGR" then self:HandlePartyVisualRosterRequest(payload, transportSenderName, isWhisper); return end
	if command == "QPGM" then
		if self:HandlePartyVisualRosterMember(payload, transportSenderName) and isWhisper then self:RememberDirectCommPeer(transportSenderName, true) end
		return
	end
	if command == "QJST" and self.HandlePartyJoinMetadata then
		self:HandlePartyJoinMetadata(payload, transportSenderName)
		return
	end
	if command == "QJON" and self.HandlePartyJoinMessage then
		self:HandlePartyJoinMessage(payload, transportSenderName, isWhisper)
		return
	end
	if command == "QTVR" then
		self:HandleAddonVersionMessage(payload, transportSenderName)
		return
	end
	if command == "QTLQ" then
		self:HandleQuestPartnerQuestMessage(payload, transportSenderName)
		return
	end
	if command == "QTLF" and self.HandleQuestPartnerStatusMessage then
		self:HandleQuestPartnerStatusMessage(payload, transportSenderName)
		return
	end
	if command == "QSHR" and self.HandlePartyQuestShareMessage then
		self:HandlePartyQuestShareMessage(payload, transportSenderName, channel)
		return
	end
 if command == "QTPR" and self.HandleQTPlayerPresenceMessage then
  self:HandleQTPlayerPresenceMessage(payload, transportSenderName)
  return
 end
	if command == "LOC" and self.HandlePlayerLocationMessage then
		self:HandlePlayerLocationMessage(payload, transportSenderName)
		return
	end

	if command == QUEST_COMPARE_REQUEST_COMMAND then
		local requestData = self:DecodeQuestCompareRequestPayload(payload)
		if not requestData then
			self:Debug("Failed to decode quest compare request payload", "comms")
			return
		end
		requestData.requesterName = transportSenderName or requestData.requesterName
		requestData.replyDistribution = SafePrimitiveString(self, channel, "")
		self:RecordQTPlayerPresence(transportSenderName, true)
		if self:HandleQuestCompareRequest(requestData) and isWhisper then self:RememberDirectCommPeer(transportSenderName, true) end
		return
	end

	if command == QUEST_COMPARE_ENTRY_COMMAND then
		local entryData = self:DecodeQuestCompareEntryPayload(payload)
		if not entryData then
			self:Debug("Failed to decode quest compare entry payload", "comms")
			return
		end
		entryData.senderName = transportSenderName
		self:RecordQTPlayerPresence(transportSenderName, true)
		if self:HandleQuestCompareEntry(entryData) and isWhisper then self:RememberDirectCommPeer(transportSenderName, true) end
		return
	end

	if command == "QCOB" then
		local objective = self:DecodeQuestCompareObjectivePayload(payload)
		if objective then self:HandleQuestCompareObjective(objective, transportSenderName) end
		return
	end

	if command == QUEST_COMPARE_DONE_COMMAND then
		local doneData = self:DecodeQuestCompareDonePayload(payload)
		if not doneData then
			self:Debug("Failed to decode quest compare done payload", "comms")
			return
		end
		doneData.senderName = transportSenderName
		self:RecordQTPlayerPresence(transportSenderName, true)
		if self:HandleQuestCompareDone(doneData) and isWhisper then self:RememberDirectCommPeer(transportSenderName, true) end
		return
	end
end
