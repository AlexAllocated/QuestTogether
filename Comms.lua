local L = _G.QuestTogether.Translate
--[[
QuestTogether Announcement Communication Layer

This file handles lightweight announcement events over a shared addon channel.
Local quest events are always published. Each receiving client applies its own
display preferences when deciding whether to render bubbles or print chat logs.
]]

local QuestTogether = _G.QuestTogether

local ANNOUNCEMENT_WIRE_VERSION = 2
local ANNOUNCEMENT_MAX_TEXT_LENGTH = 220
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

function QuestTogether:SanitizeAnnouncementText(text)
	local sanitized = SafeTrimAddonString(self, text, "")
	return TruncateUtf8(sanitized, ANNOUNCEMENT_MAX_TEXT_LENGTH)
end

function QuestTogether:GetAnnouncementServerTime()
	local getter = self.API and self.API.GetServerTime
	if type(getter) ~= "function" then
		return nil
	end
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
	if self.DecodeAnnouncementFacts and self:DecodeAnnouncementFacts(facts) then
		sanitized.eventFacts = facts
	end
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
	if #eventId > 64 or not eventId:match("^%d+%-%d+%-%d+$") then
		eventId = ""
	end
	local normalizedWarMode = nil
	local occurredAt = SafeNumber(self, eventData.occurredAt)
	if
		occurredAt and (occurredAt < 1000000000 or occurredAt >= 100000000000 or occurredAt ~= math.floor(occurredAt))
	then
		occurredAt = nil
	end
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
function QuestTogether:RecordCommsTraffic(kind, message, result)
	local diagnostics = self:GetCommsDiagnostics()
	local now = SafeNumber(self, self.API.GetTime and self.API.GetTime())
	diagnostics.trafficStartedAt = diagnostics.trafficStartedAt or now
	diagnostics.trafficObservedAt = now
	diagnostics.traffic = diagnostics.traffic or {}
	local command = message:match("^2|([^|]+)|")
	command = self:GetCommOperation(command) and command or "OTHER"
	local bucket = diagnostics.traffic[command] or {}
	diagnostics.traffic[command] = bucket
	bucket[kind] = (bucket[kind] or 0) + 1
	bucket[kind .. "Bytes"] = (bucket[kind .. "Bytes"] or 0) + #message
	if result == 3 or result == 8 then
		bucket.throttled = (bucket.throttled or 0) + 1
	end
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
	self:Debugf(
		"comms",
		"announcement age sender=%s event=%s reportedAgeSeconds=%s",
		eventData.senderName,
		eventData.eventType,
		age and tostring(age) or "unknown"
	)
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

function QuestTogether:AnnouncementChannelChatFilter(_, _, ...)
	-- Only channel metadata identifies this channel. Scanning message text and
	-- player names both hides unrelated conversations and touches secret data.
	return MatchesAnnouncementChannelName(self, select(4, ...))
		or MatchesAnnouncementChannelName(self, select(9, ...))
		or self:IsGeographicChannelName(select(4, ...))
		or self:IsGeographicChannelName(select(9, ...))
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
	if not cacheKey and not self:IsGeographicChannelName(channelName) then
		return false
	end
	if not self.isEnabled then
		self:Debug("Skipping channel join because addon is disabled", "comms")
		return false
	end

	-- Existing permanent channels survive /reload too; they need our filters
	-- even when no JoinPermanentChannel call is necessary.
	self:RegisterAnnouncementChannelChatFilters()
	local currentLocalID = self:GetAnnouncementChannelLocalID(channelName)
	if currentLocalID then
		if cacheKey then
			self[cacheKey] = currentLocalID
		end
		local bindings = rawget(self, "announcementChannelBindings") or {}
		self.announcementChannelBindings = bindings
		if bindings[channelName] ~= currentLocalID and not self:IsRuntimeRestricted() then
			self:HideAnnouncementChannelFromChatWindows(channelName)
			bindings[channelName] = currentLocalID
		end
		return true
	end
	if cacheKey then
		self[cacheKey] = nil
	end
	if self.announcementChannelBindings then
		self.announcementChannelBindings[channelName] = nil
	end

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
		if cacheKey then
			self[cacheKey] = currentLocalID
		end
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
	if not self.isEnabled or self:IsRuntimeRestricted() or self:IsRuntimeRestrictionTypeActive("chat") then
		return false
	end
	local api = self.API or {}
	if not api.GetChatChannelList or not api.SwapChatChannelIndices then
		return false
	end
	local ok, list = pcall(api.GetChatChannelList)
	if not ok or not self:CanAccessTable(list) or #list > 90 or #list % 3 ~= 0 then
		return false
	end
	local channels, seen = {}, {}
	for i = 1, #list, 3 do
		local id, name = SafeChannelNumber(self, list[i]), SafeTrimAddonString(self, list[i + 1], "")
		if not id or id < 1 or id > 30 or id ~= math.floor(id) or name == "" or seen[id] then
			return false
		end
		seen[id] = true
		channels[#channels + 1] = {
			id = id,
			name = name,
			qt = MatchesAnnouncementChannelName(self, name) or self:IsGeographicChannelName(name),
		}
	end
	table.sort(channels, function(a, b)
		return a.id < b.id
	end)
	for i = 2, #channels do
		local j = i
		while j > 1 and not channels[j].qt and channels[j - 1].qt do
			if self:IsRuntimeRestricted() then
				return false
			end
			local swapped, result = pcall(api.SwapChatChannelIndices, channels[j - 1].id, channels[j].id)
			-- Native channel indices can change; never retain a stale receive fallback.
			self.announcementChannelLocalID = nil
			if not swapped or result ~= true then
				return false
			end
			channels[j - 1].qt, channels[j].qt = channels[j].qt, channels[j - 1].qt
			channels[j - 1].name, channels[j].name = channels[j].name, channels[j - 1].name
			j = j - 1
		end
	end
	-- Keep the human chat channel before the machine-only zone subscriptions.
	local firstQT, current
	for _, channel in ipairs(channels) do
		if channel.qt and not firstQT then
			firstQT = channel.id
		end
		if channel.name == self.announcementChannelName then
			current = channel.id
		end
	end
	if firstQT and current and current ~= firstQT then
		local swapped, result = pcall(api.SwapChatChannelIndices, current, firstQT)
		self.announcementChannelLocalID = nil
		if not swapped or result ~= true then
			return false
		end
	end
	self.announcementChannelLocalID = self:GetAnnouncementChannelLocalID()
	return true
end

function QuestTogether:ScheduleAnnouncementChannelOrder()
	if
		not self.isEnabled
		or not self.API.GetChatChannelList
		or not self.API.SwapChatChannelIndices
		or not self.API.Delay
		or rawget(self, "channelOrderWork")
	then
		return
	end
	local work = {}
	self.channelOrderWork = work
	self.API.Delay(0.2, function()
		if rawget(self, "channelOrderWork") ~= work then
			return
		end
		self:MoveAnnouncementChannelsToEnd()
		self.channelOrderWork = nil
	end)
end

function QuestTogether:CHANNEL_COUNT_UPDATE()
	local state = rawget(self, "geographicCommsState")
	if state then
		state.reconciledChannels = nil
	end
	self:ScheduleAnnouncementChannelOrder()
end
function QuestTogether:CHANNEL_UI_UPDATE()
	self:ScheduleAnnouncementChannelOrder()
end

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
	if self.ResetRuntimeCoordinator then
		self:ResetRuntimeCoordinator()
	end
	self:EndCommunicationSession()
	self.communicationState = nil
	self:ResetTransport()
	self:ClosePartyChatReminderPreview()
	self:ResetPartyChatReminder()
	if self.ResetGeographicComms then
		self:ResetGeographicComms()
	end
	self.channelOrderWork = nil
	self.announcementChannelBindings = nil
	self:ResetLocalizedQuestTitles()
	if self.ResetPartyJoin then
		self:ResetPartyJoin()
	end
	if self.ResetPartyVisuals then
		self:ResetPartyVisuals()
	end
	if self.ResetQTPlayerPresence then
		self:ResetQTPlayerPresence()
	end
	if self.ResetPlayerLocations then
		self:ResetPlayerLocations()
	end
	if self.ResetPartyQuestCompare then
		self:ResetPartyQuestCompare()
	end
	self.pendingPingRequests = {}
	self.pendingQuestCompareRequests = {}
	self.recentCommMessageSignatures = {}
	self.recentCommSignatureIndex = nil
	-- Pending timer closures retain the old state only; they cannot send after
	-- disable/re-enable or remove work from a replacement queue.
	self.questComparePendingResponses = nil
	self.questCompareResponseCache = nil
	self.questCompareLocalRevision = nil
	self.pingReplyState = nil
	if self.ResetDeveloperDiagnostics then
		self:ResetDeveloperDiagnostics()
	end
	if self.ResetPlayerDetails then
		self:ResetPlayerDetails()
	end
	if self.ResetPeerSnapshots then
		self:ResetPeerSnapshots()
	end
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
		if realmName == "" and self.API.GetRealmName then
			realmName = self.API.GetRealmName()
		end
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
			and not self:IsRuntimeRestricted()
			and self.GetPlayerAnnouncementLocationInfo
			and self:GetPlayerAnnouncementLocationInfo()
		or {}
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
	return (prefix or "req") .. "-" .. self:GetCommunicationSession() .. "-" .. self:NextCommunicationSequence()
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
			and self.GetPlayerAnnouncementLocationInfo
			and self:GetPlayerAnnouncementLocationInfo()
		or nil
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
		eventFacts = sanitizedExtraData.eventFacts or (self.BuildAnnouncementFacts and self:BuildAnnouncementFacts(
			eventType
		)) or "",
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
	return incomingLocalID ~= nil
		and incomingLocalID > 0
		and (expectedLocalID == incomingLocalID or self:IsGeographicChannelEvent(channel, incomingLocalID))
end

function QuestTogether:IsGlobalAnnouncementChannelEvent(distribution, localID, name)
	if distribution ~= "CHANNEL" then
		return false
	end
	name = SafePrimitiveString(self, name, "")
	if name ~= "" then
		return MatchesAnnouncementChannelName(self, name)
	end
	local expected = self:GetAnnouncementChannelLocalID(self.announcementChannelName)
	return expected ~= nil and expected == SafeChannelNumber(self, localID)
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
	if
		type(eventData) ~= "table"
		or not self.isEnabled
		or self:IsRuntimeRestricted()
		or self:IsRuntimeRestrictionTypeActive("chat")
	then
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
	if
		not self:CanAccessValue(nearbyUnitToken)
		or type(nearbyUnitToken) ~= "string"
		or not api.CanTargetUnitForEmote
		or not api.DoEmote
	then
		return false
	end
	local ok, targetable = pcall(api.CanTargetUnitForEmote, nearbyUnitToken)
	if not ok or not self:CanAccessValue(targetable) or targetable ~= true then
		return false
	end
	local matched, matches =
		pcall(self.DoesUnitTokenMatchSender, self, nearbyUnitToken, eventData.senderGUID, senderName)
	if not matched or not self:CanAccessValue(matches) or matches ~= true then
		return false
	end

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
	if not self:CanPublishPlayerLocation() then
		eventData.coordX, eventData.coordY, eventData.mapID, eventData.zoneName = "", "", "", ""
	end
	local operation = eventData.eventType == "PLAYER_LEVEL_UP" and "LVL" or "ANN"
	return self:Emit(operation, eventData, nil, { owner = self, expires = self.API.GetTime() + 30 })
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
	if self:IsIgnoredPlayerName(senderName) then
		return false
	end
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

function QuestTogether:HandleAnnouncementEvent(eventData, isLocal, skipTitleWait)
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
	if not isLocal and self:IsIgnoredPlayerName(senderName) then
		return false
	end
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
		nearbyByLocation =
			self:IsAnnouncementSenderNearbyByLocation(eventData, eventData.eventType == "LOOKING_FOR_QUEST_PARTNERS")
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
	if
		not isLocal
		and (self:GetOption("showChatLogs") or self:GetOption("showChatBubbles"))
		and self.LocalizeAnnouncementEvent
	then
		local localizedText, waitingForTitle = self:LocalizeAnnouncementEvent(eventData)
		if not skipTitleWait and self:QueueLocalizedAnnouncement(eventData, waitingForTitle) then
			return true
		end
		eventData.text = localizedText
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
				if ok and self:CanAccessValue(unit) and type(unit) == "string" then
					emoteTarget = unit
				end
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
		if type(query) ~= "function" then
			return nil
		end
		local ok, value = pcall(query, ...)
		if ok and self:CanAccessValue(value) and type(value) == "boolean" then
			return value
		end
	end
	local raid = ReadBoolean(api.IsInRaid)
	if raid == nil then
		return nil
	end
	if raid then
		return {}
	end
	local instance = ReadBoolean(api.IsInInstanceGroup)
	if instance == nil then
		return nil
	end
	if not instance then
		local party = ReadBoolean(api.IsInParty)
		if party == nil then
			return nil
		end
		if not party then
			return {}
		end
	end
	local missingQT = {}
	for index = 1, 4 do
		local unit = "party" .. index
		local exists = ReadBoolean(api.UnitExists, unit)
		if exists == nil then
			return nil
		end
		if exists then
			local ok, name = pcall(self.GetUnitFullName, self, unit)
			if
				not ok
				or not self:CanAccessValue(name)
				or type(name) ~= "string"
				or name == ""
				or #name > 120
				or name:find("[%c|]")
			then
				return nil
			end
			if not self:IsKnownQTPlayer(name) then
				missingQT[#missingQT + 1] = name
			end
		end
	end
	table.sort(missingQT)
	return missingQT, instance and "INSTANCE_CHAT" or "PARTY"
end

-- Only local publication reaches this path; received events are never relayed.
function QuestTogether:AnnounceToNonQTParty(eventData)
	if
		not self.isEnabled
		or not self:GetOption("announceToNonQTParty")
		or self.suppressLocalAnnouncementDisplayDuringTests
		or not self:ShouldDisplayAnnouncementType(eventData.eventType)
	then
		return false
	end
	if self:IsRuntimeRestrictionTypeActive("chat") then
		return false
	end
	local api = self.API or {}
	if type(api.SendPartyChatMessage) ~= "function" then
		return false
	end
	local members, distribution = self:GetNonQTPartyMembers()
	if not members or #members == 0 or not self:UpdatePartyChatReminder(members) then
		return false
	end
	-- Plain text only: custom QT links/textures are not usable by non-QT clients.
	local text = SafeTrimAddonString(self, eventData.text, "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
	text = text:gsub("[%c]", " ")
	text = self:SafeTrimString(text, "")
	if text == "" then
		return false
	end
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

	return self:PublishPreparedAnnouncement(eventData, extraData)
end

function QuestTogether:DispatchAnnouncementEvent(eventData)
	self:SendAnnouncementWireEvent(eventData)
	self:AnnounceToNonQTParty(eventData)
	if self.suppressLocalAnnouncementDisplayDuringTests then
		return true
	end
	self:HandleAnnouncementEvent(eventData, true)
	return true
end

function QuestTogether:SendQTChannelChat(message)
	if not self.isEnabled or self:IsRuntimeRestrictionTypeActive("chat") then
		return false
	end
	message = SafeTrimAddonString(self, message, "")
	message = TruncateUtf8(message:gsub("[%c]", " "), 255)
	if message == "" or not self.API.SendChannelChatMessage then
		return false
	end
	if not self:EnsureAnnouncementChannelJoined(self.announcementChannelName) then
		return false
	end
	local id = self:GetAnnouncementChannelLocalID()
	if not id then
		return false
	end
	local ok, sent = pcall(self.API.SendChannelChatMessage, message, id)
	return ok and sent == true
end

function QuestTogether:ShouldShowQTChannelChatFromSender(name)
	if self:GetOption("qtChatScope") ~= "zone_only" or self:IsSelfSender(name) then
		return true
	end
	if self:IsRuntimeRestricted() then
		return false
	end
	local api = self.API or {}
	if not api.GetBestMapForUnit then
		return false
	end
	local ok, localMapID = pcall(api.GetBestMapForUnit, "player")
	localMapID = ok and self:SafeToNumber(localMapID) or nil
	local remoteMapID = self:GetRecentPlayerLocationMapID(name)
	return localMapID ~= nil and remoteMapID ~= nil and localMapID == remoteMapID
end

-- Handle once per event, never from the per-chat-frame suppression filter.
-- Human channel chat is not addon protocol traffic or evidence of QT presence.
function QuestTogether:CHAT_MSG_CHANNEL(
	_,
	message,
	sender,
	_,
	channelName,
	_,
	_,
	_,
	_,
	channelBaseName,
	_,
	_,
	senderGUID
)
	if not self.isEnabled or self:GetOption("showQTChat") == false or self:IsRuntimeRestrictionTypeActive("chat") then
		return false
	end
	if
		not MatchesAnnouncementChannelName(self, channelBaseName)
		and not MatchesAnnouncementChannelName(self, channelName)
	then
		return false
	end
	local name = SafeTrimAddonString(self, sender, "")
	if name == "" then
		return false
	end
	name = self:NormalizeMemberName(name)
	if not name or self:IsIgnoredPlayerName(name) or not self:ShouldShowQTChannelChatFromSender(name) then
		return false
	end
	local text = SafePrimitiveString(self, message, "")
	-- Preserve link labels as plain text, without accepting user-supplied UI markup.
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
	text = TruncateUtf8(self:SafeTrimString(text:gsub("[%c]", " "), ""), 255)
	if text == "" then
		return false
	end
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
			if plate then
				self:ShowAnnouncementBubbleOnNameplate(plate, text, "QT_CHAT", icon, "texture", name)
			end
		end
	end
	return true
end

function QuestTogether:CHAT_MSG_ADDON(_, prefix, message, channel, sender, _, _, localID, name)
	self:OnCommReceived(prefix, message, channel, sender, localID, name)
end

function QuestTogether:OnCommReceived(prefix, message, channel, sender, localID, name)
	return self:ReceiveCommunication(prefix, message, channel, sender, localID, name)
end
