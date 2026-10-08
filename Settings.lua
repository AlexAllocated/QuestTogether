-- Profiles, validation and effects have one transaction boundary. Widgets and
-- commands submit changes; runtime services own the resulting work.
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate

local function NormalizeProfileKey(profileKey)
	if type(profileKey) ~= "string" then
		return nil
	end

	local trimmed = QuestTogether:SafeTrimString(profileKey, "")
	if trimmed == "" then
		return nil
	end
	return trimmed
end

function QuestTogether:GetCurrentCharacterKey()
	-- Keep existing Forever profile assignments: earlier versions interpreted
	-- UnitFullName's second return as a realm and stored First-Surname keys.
	-- This legacy storage key must not become a display or transport identity.
	local regionalNames = self:UsesRegionalPlayerNames()
	if regionalNames then
		local first, last = self.API.UnitFullName("player")
		first = self:SafeTrimString(first, "")
		last = self:SafeStripWhitespace(last, "")
		if first ~= "" and last ~= "" then
			return first .. "-" .. last
		end
	end
	local fullName = self.GetPlayerFullName and self:GetPlayerFullName() or nil
	if type(fullName) == "string" and fullName ~= "" then
		return fullName
	end

	local playerName = self:GetPlayerName() or "Unknown"
	if string.find(playerName, "-", 1, true) then
		return playerName
	end

	if not regionalNames then
		local realmName = self:SafeStripWhitespace(self.API.GetRealmName and self.API.GetRealmName() or "", "")
		if realmName ~= "" then
			return playerName .. "-" .. realmName
		end
	end

	return playerName
end

function QuestTogether:MigratePlayerLocationOptions(profile)
	if type(profile) ~= "table" then
		return
	end
	-- Read the old settings before filling defaults. Missing settings used to
	-- default on; every present value had to be exactly true to grant permission.
	-- Combining sharing uses AND, while combining viewing uses OR.
	if profile.sharePlayerLocation == nil then
		profile.sharePlayerLocation = (profile.shareLocationOnMap == nil or profile.shareLocationOnMap == true)
			and (profile.shareLocationOnMinimap == nil or profile.shareLocationOnMinimap == true)
	end
	if profile.showPlayerLocations == nil then
		profile.showPlayerLocations = (profile.showLocationsOnMap == nil or profile.showLocationsOnMap == true)
			or (profile.showLocationsOnMinimap == nil or profile.showLocationsOnMinimap == true)
	end
	-- Fold the 6.4.2 split display controls back into one preference. Preserve
	-- viewing when either surface was enabled; sharing remains independent.
	if profile.showWorldMapPlayers ~= nil or profile.showMinimapPlayers ~= nil then
		local world = profile.showWorldMapPlayers
		local minimap = profile.showMinimapPlayers
		if world == nil then
			world = profile.showPlayerLocations
		end
		if minimap == nil then
			minimap = profile.showPlayerLocations
		end
		profile.showPlayerLocations = world == true or minimap == true
	end
	profile.showWorldMapPlayers, profile.showMinimapPlayers = nil, nil
	if profile.onlyShowQuestPartners == nil then
		profile.onlyShowQuestPartners = false
	end
	profile.shareLocationOnMap, profile.shareLocationOnMinimap = nil, nil
	profile.showLocationsOnMap, profile.showLocationsOnMinimap = nil, nil
	if self.MigratePlayerMapVisibility then
		self:MigratePlayerMapVisibility(profile)
	end
end

function QuestTogether:EnsureProfileStorage()
	if not self.db then
		return false
	end

	if type(self.db.profiles) ~= "table" then
		self.db.profiles = {}
	end
	if type(self.db.profileKeys) ~= "table" then
		self.db.profileKeys = {}
	end
	-- Inactive profiles can be selected or copied later in this session.
	for _, profile in pairs(self.db.profiles) do
		self:MigratePlayerLocationOptions(profile)
	end
	self:MigratePlayerLocationOptions(self.db.profile)

	return true
end

function QuestTogether:GetCurrentProfileKey()
	return self.activeProfileKey
end

function QuestTogether:GetProfileKeys()
	if not self.db then
		return {}
	end
	self:EnsureProfileStorage()

	local keys = {}
	for profileKey, profileData in pairs(self.db.profiles) do
		if type(profileKey) == "string" and type(profileData) == "table" then
			keys[#keys + 1] = profileKey
		end
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	return keys
end

function QuestTogether:EnsureProfile(profileKey, sourceProfile)
	if not self.db or not self:EnsureProfileStorage() then
		return nil, nil
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return nil, nil
	end

	if type(self.db.profiles[normalizedKey]) ~= "table" then
		self.db.profiles[normalizedKey] = self:DeepCopy(sourceProfile or self.DEFAULTS.profile)
	end
	self:MigratePlayerLocationOptions(self.db.profiles[normalizedKey])
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return normalizedKey, self.db.profiles[normalizedKey]
end

function QuestTogether:ApplyActiveProfileState(changeReason)
	if not self.db or not self.db.profile then
		return false
	end
	self:NormalizeSettingsProfile()
	return self:ApplySettingsTransaction({}, { replace = true, reason = changeReason })
end

function QuestTogether:SetActiveProfile(profileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, L("Profile database is unavailable.")
	end

	local normalizedKey, profileData = self:EnsureProfile(profileKey)
	if not normalizedKey or not profileData then
		return false, L("Profile name cannot be empty.")
	end

	local characterKey = self.activeCharacterKey or self:GetCurrentCharacterKey()
	self.activeCharacterKey = characterKey
	self.activeProfileKey = normalizedKey
	self.db.profileKeys[characterKey] = normalizedKey
	self.db.profile = profileData

	self:ApplyActiveProfileState("switch")
	return true
end

function QuestTogether:CreateProfile(profileKey, sourceProfileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, L("Profile database is unavailable.")
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return false, L("Profile name cannot be empty.")
	end
	if type(self.db.profiles[normalizedKey]) == "table" then
		return false, L("A profile with that name already exists.")
	end

	local sourceProfile = self.db.profile
	local normalizedSource = NormalizeProfileKey(sourceProfileKey)
	if normalizedSource and type(self.db.profiles[normalizedSource]) == "table" then
		sourceProfile = self.db.profiles[normalizedSource]
	end

	self.db.profiles[normalizedKey] = self:DeepCopy(sourceProfile or self.DEFAULTS.profile)
	self:MigratePlayerLocationOptions(self.db.profiles[normalizedKey])
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return true
end

function QuestTogether:CopyProfileIntoActiveProfile(sourceProfileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, L("Profile database is unavailable.")
	end

	local sourceKey = NormalizeProfileKey(sourceProfileKey)
	if not sourceKey then
		return false, L("Profile name cannot be empty.")
	end
	if type(self.db.profiles[sourceKey]) ~= "table" then
		return false, L("Profile not found: ") .. tostring(sourceKey)
	end
	if not self.activeProfileKey then
		return false, L("No active profile is set.")
	end

	self.db.profiles[self.activeProfileKey] = self:DeepCopy(self.db.profiles[sourceKey])
	self:MigratePlayerLocationOptions(self.db.profiles[self.activeProfileKey])
	self:ApplyDefaults(self.db.profiles[self.activeProfileKey], self.DEFAULTS.profile)
	self.db.profile = self.db.profiles[self.activeProfileKey]
	self:ApplyActiveProfileState("copy")
	return true
end

function QuestTogether:ResetActiveProfile()
	if not self.db or not self:EnsureProfileStorage() then
		return false, L("Profile database is unavailable.")
	end
	if not self.activeProfileKey then
		return false, L("No active profile is set.")
	end

	self.db.profiles[self.activeProfileKey] = self:DeepCopy(self.DEFAULTS.profile)
	self.db.profile = self.db.profiles[self.activeProfileKey]
	self:ApplyActiveProfileState("reset")
	return true
end

function QuestTogether:DeleteProfile(profileKey)
	if not self.db or not self:EnsureProfileStorage() then
		return false, L("Profile database is unavailable.")
	end

	local normalizedKey = NormalizeProfileKey(profileKey)
	if not normalizedKey then
		return false, L("Profile name cannot be empty.")
	end
	if normalizedKey == self.activeProfileKey then
		return false, L("You cannot delete the active profile.")
	end
	if type(self.db.profiles[normalizedKey]) ~= "table" then
		return false, L("Profile not found: ") .. tostring(normalizedKey)
	end

	self.db.profiles[normalizedKey] = nil

	for characterKey, mappedProfileKey in pairs(self.db.profileKeys) do
		if mappedProfileKey == normalizedKey then
			-- The character's default key can be the profile just deleted.
			-- Resolve its default lazily on that character's next initialization.
			self.db.profileKeys[characterKey] = nil
		end
	end

	return true
end

function QuestTogether:GetOption(key)
	if not self.db or not self.db.profile then
		return nil
	end
	if key == "chatLogDestination" then
		return self:GetResolvedChatLogDestination()
	end
	return self.db.profile[key]
end

-- Compatibility helpers so old option-style code still works.
function QuestTogether:GetValue(infoOrKey)
	local key = infoOrKey
	if type(infoOrKey) == "table" then
		key = infoOrKey[#infoOrKey]
	end
	return self:GetOption(key)
end

function QuestTogether:SetValue(infoOrKey, value)
	local key = infoOrKey
	if type(infoOrKey) == "table" then
		key = infoOrKey[#infoOrKey]
	end
	return self:SetOption(key, value)
end

-- SavedVariables initializer.
function QuestTogether:InitializeDatabase(savedDatabase)
	if type(savedDatabase) == "table" then
		-- Private fixtures exercise normalization without rebinding SavedVariables.
		self.db = savedDatabase
	else
		if type(_G.QuestTogetherDB) ~= "table" then
			_G.QuestTogetherDB = {}
		end
		self.db = _G.QuestTogetherDB
	end

	if type(self.db.global) ~= "table" then
		self.db.global = {}
	end
	self:ApplyDefaults(self.db.global, self.DEFAULTS.global)
	self.db.global.debugLogLines = nil
	if type(self.db.global.debugLogSearchFilter) ~= "string" then
		if type(self.db.global.debugLogPrefixFilter) == "string" then
			self.db.global.debugLogSearchFilter = self.db.global.debugLogPrefixFilter
		else
			self.db.global.debugLogSearchFilter = self.db.global.debugLogSearchFilter ~= nil
					and tostring(self.db.global.debugLogSearchFilter)
				or ""
		end
	end
	if type(self.db.global.debugLogCategoryFilter) ~= "string" then
		self.db.global.debugLogCategoryFilter = self.DEBUG_ALL_CATEGORIES
	end
	self.debugLogLines = {}
	self.debugLogStoreNormalized = false
	self.debugLogTextLengthSum = 0
	self:EnsureProfileStorage()

	local characterKey = self:GetCurrentCharacterKey()
	local defaultProfileKey = NormalizeProfileKey(characterKey) or "Character"
	local assignedProfileKey = NormalizeProfileKey(self.db.profileKeys[characterKey])
	if not assignedProfileKey then
		assignedProfileKey = defaultProfileKey
		self.db.profileKeys[characterKey] = assignedProfileKey
	end

	if type(self.db.profiles[assignedProfileKey]) ~= "table" then
		self.db.profiles[assignedProfileKey] = self:DeepCopy(self.DEFAULTS.profile)
	end

	self.activeCharacterKey = characterKey
	self.activeProfileKey = assignedProfileKey
	self.db.profile = self.db.profiles[assignedProfileKey]
	self:ApplyDefaults(self.db.profile, self.DEFAULTS.profile)

	self:NormalizeSettingsProfile()
end

local validators = {
	showProgressFor = function(a, v)
		return a:IsShowProgressFor(v) and v or nil
	end,
	chatLogDestination = function(a, v)
		return a:IsChatLogDestination(v) and v or nil
	end,
	qtChatScope = function(_, v)
		if v == "global" or v == "zone_only" then
			return v
		end
	end,
	nearbyAnnouncementRange = function(a, v)
		return a:NormalizeNearbyAnnouncementRange(v)
	end,
	chatBubbleSize = function(a, v)
		return a:NormalizeChatBubbleSizeValue(v)
	end,
	chatBubbleDuration = function(a, v)
		return a:NormalizeChatBubbleDurationValue(v)
	end,
	nameplateQuestIconStyle = function(a, v)
		return a:IsNameplateQuestIconStyle(v) and v or nil
	end,
	nameplatePlayerIconStyle = function(a, v)
		return a:IsNameplateQuestIconStyle(v) and v or nil
	end,
	windowScale = function(a, v)
		local n = a:SafeToNumber(v)
		if n and n >= 80 and n <= 150 then
			return n
		end
	end,
	minimapButtonPosition = function(a, v)
		local n = a:SafeToNumber(v)
		if n and n ~= math.huge and n ~= -math.huge then
			return n % 360
		end
	end,
	nameplateQuestHealthColor = function(a, v)
		if not a:CanAccessTable(v) or type(v) ~= "table" then
			return nil
		end
		local color = {}
		for _, key in ipairs({ "r", "g", "b" }) do
			local n = a:SafeToNumber(v[key])
			if not n or n < 0 or n > 1 then
				return nil
			end
			color[key] = n
		end
		return color
	end,
}
for key, group in pairs({
	compareQuestOwnership = "ownership",
	compareQuestProgress = "progress",
	compareQuestAction = "action",
}) do
	local filterGroup = group
	validators[key] = function(a, v)
		return a:IsPartyQuestCompareFilterValue(filterGroup, v) and v or nil
	end
end

function QuestTogether:ValidateSetting(key, value)
	if type(key) ~= "string" or self.DEFAULTS.profile[key] == nil or not self:CanAccessValue(value) then
		return nil
	end
	local validate = validators[key]
	if validate then
		return validate(self, value)
	end
	if type(self.DEFAULTS.profile[key]) == "boolean" and type(value) == "boolean" then
		return value
	end
	return nil
end

function QuestTogether:NormalizeSettingsProfile()
	local profile = self.db.profile
	self:MigratePlayerLocationOptions(profile)
	for key, default in pairs(self.DEFAULTS.profile) do
		local value = self:ValidateSetting(key, profile[key])
		profile[key] = value
		if value == nil then
			profile[key] = self:DeepCopy(default)
		end
	end
end

local function Invoke(addon, method, ...)
	if type(addon[method]) == "function" then
		return addon[method](addon, ...)
	end
end

function QuestTogether:ApplySettingsTransaction(changed, context)
	context = context or {}
	local all = context.replace == true
	local function Has(...)
		if all then
			return true
		end
		for i = 1, select("#", ...) do
			if changed[select(i, ...)] then
				return true
			end
		end
		return false
	end
	-- Revocation must happen before any restart or asynchronous effect.
	if all or (changed.shareDeveloperDiagnostics and self:GetOption("shareDeveloperDiagnostics") ~= true) then
		self.developerRequestState = nil
		Invoke(self, "CancelDeveloperDiagnosticReplies")
	end
	if Has("enabled") and (not all or self.hasLoggedIn) then
		if self.db.profile.enabled then
			self:Enable()
		else
			self:Disable()
		end
	end
	if all then
		Invoke(self, "RefreshPartyRoster")
	end
	if (not all or self.isEnabled) and Has("sharePartyFocus", "sharePartyWaypoint", "showPartyWaypoints") then
		Invoke(self, "QueuePartyNavigationUpdate")
	end
	if Has("experimentalLayerDetection", "sharePlayerLocation") then
		Invoke(self, "ResetPlayerPhases")
		Invoke(self, "RefreshPlayerLocationPins")
	end
	if Has("lightMode", "reduceMotion") then
		Invoke(self, "RefreshWindowThemes")
	end
	if Has("windowScale") then
		Invoke(self, "RefreshManagedWindowLayouts")
	end
	if Has("announceToNonQTParty", "hidePartyChatReminder") then
		Invoke(self, "UpdatePartyChatReminder")
	end
	if Has("lookingForQuestPartners") then
		Invoke(self, "BroadcastQuestPartnerStatus", true)
		Invoke(self, "RefreshMinimapPartnerGlow")
	end
	if context.startedLooking then
		Invoke(self, "AnnounceQuestPartnerSearch")
	end
	if Has("sharePlayerLocation", "showPlayerLocations", "onlyShowQuestPartners") then
		Invoke(self, "OnPlayerLocationOptionsChanged", context.key)
	end
	if Has("showMinimapButton", "minimapButtonPosition") then
		Invoke(self, "RefreshMinimapButton")
	end
	if Has("chatLogDestination") then
		if self.db.profile.chatLogDestination == "separate" then
			local frame = self:EnsureQuestLogChatFrame()
			if frame then
				self:ApplyMainChatFontSizeToChatFrame(frame)
				if not all and self.isEnabled and self.hasLoggedIn then
					self:PrintChatLogDestinationMessage()
				end
			end
		else
			self:CloseQuestLogChatFrame()
		end
	end
	if Has("showChatBubbles", "hideMyOwnChatBubbles", "chatBubbleSize", "chatBubbleDuration") then
		Invoke(self, "RefreshActiveAnnouncementBubbles")
		Invoke(self, "RefreshPersonalBubbleAnchorVisualState")
		Invoke(self, "RefreshPersonalBubbleEditModeDialog")
	end
	if
		Has(
			"nameplateQuestIconEnabled",
			"nameplatePlayerIconEnabled",
			"nameplatePlayerIconStyle",
			"nameplateQuestIconStyle",
			"nameplateQuestHealthColorEnabled",
			"nameplateQuestHealthColor"
		)
	then
		Invoke(self, "RefreshNameplateAugmentation")
	end
	if all then
		Invoke(self, "RefreshOptionsWindow")
		Invoke(self, "RefreshProfilesWindow")
		self:Debugf(
			"profile",
			"Applied active profile state reason=%s character=%s profile=%s",
			tostring(context.reason or "unknown"),
			tostring(self.activeCharacterKey),
			tostring(self.activeProfileKey)
		)
	end
	return true
end

function QuestTogether:SetOptions(values, key)
	if not self.db or not self.db.profile or type(values) ~= "table" then
		return false
	end
	local normalized, changed = {}, {}
	for name, value in pairs(values) do
		local result = self:ValidateSetting(name, value)
		if result == nil then
			return false
		end
		normalized[name], changed[name] = result, true
	end
	local startedLooking = normalized.lookingForQuestPartners == true
		and self.db.profile.lookingForQuestPartners ~= true
	for name, value in pairs(normalized) do
		self.db.profile[name] = value
	end
	return self:ApplySettingsTransaction(changed, { key = key, startedLooking = startedLooking })
end

function QuestTogether:SetOption(key, value)
	if type(key) ~= "string" or value == nil then
		return false
	end
	return self:SetOptions({ [key] = value }, key)
end
