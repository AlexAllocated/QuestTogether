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

function QuestTogether:IsOwnChatBubbleMode(value)
	return self:CanAccessValue(value) and (value == "always" or value == "solo" or value == "party" or value == "hidden")
end

function QuestTogether:MigrateOwnChatBubbleMode(profile)
	if type(profile) ~= "table" then return end
	-- Migrate before defaults so a saved opt-out cannot become the new default.
	if not self:IsOwnChatBubbleMode(profile.ownChatBubbleMode) then
		profile.ownChatBubbleMode = self:CanAccessValue(profile.hideMyOwnChatBubbles)
			and profile.hideMyOwnChatBubbles == true and "hidden" or "always"
	end
	profile.hideMyOwnChatBubbles = nil
end

function QuestTogether:GetOwnChatBubbleMode()
	local mode = self:GetOption("ownChatBubbleMode")
	return self:IsOwnChatBubbleMode(mode) and mode or "always"
end

function QuestTogether:ShouldShowOwnChatBubble()
	if self:GetOption("showChatBubbles") ~= true then return false end
	local mode = self:GetOwnChatBubbleMode()
	if mode == "hidden" then return false end
	if mode == "always" then return true end
	local query = self.API and self.API.IsInAnyGroup
	if not self:CanAccessValue(query) or type(query) ~= "function" then return false end
	local ok, grouped = pcall(query)
	return ok and self:CanAccessValue(grouped) and grouped == (mode == "party")
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
		self:MigrateOwnChatBubbleMode(profile)
	end
	self:MigratePlayerLocationOptions(self.db.profile)
	self:MigrateOwnChatBubbleMode(self.db.profile)

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
		self.db.profiles[normalizedKey] = sourceProfile and self:DeepCopy(sourceProfile) or self:CreateDefaultProfile()
	end
	self:MigratePlayerLocationOptions(self.db.profiles[normalizedKey])
	self:MigrateOwnChatBubbleMode(self.db.profiles[normalizedKey])
	self:ApplyDefaults(self.db.profiles[normalizedKey], self.DEFAULTS.profile)
	return normalizedKey, self.db.profiles[normalizedKey]
end

function QuestTogether:ApplyActiveProfileState(changeReason)
	if not self.db or not self.db.profile then
		return false
	end
	if self.CancelPartyQuestFocusFollowRequest then self:CancelPartyQuestFocusFollowRequest() end
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
	self:MigrateOwnChatBubbleMode(self.db.profiles[normalizedKey])
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
	self:MigrateOwnChatBubbleMode(self.db.profiles[self.activeProfileKey])
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

	local fresh = next(self.db) == nil
	if type(self.db.global) ~= "table" then
		self.db.global = {}
	end
	if self.db.global.welcomeSetupComplete == nil then self.db.global.welcomeSetupComplete = not fresh end
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
		self.db.profiles[assignedProfileKey] = self:CreateDefaultProfile()
	end

	self.activeCharacterKey = characterKey
	self.activeProfileKey = assignedProfileKey
	self.db.profile = self.db.profiles[assignedProfileKey]
	self:ApplyDefaults(self.db.profile, self.DEFAULTS.profile)

	self:NormalizeSettingsProfile()
end

function QuestTogether:NormalizeSettingsProfile()
	local profile = self.db.profile
	-- Retire the unreleased tracker checkbox in favor of one display policy.
	if profile.showQuestFocusWindow == false then profile.questTrackerMode = "hidden" end
	profile.showQuestFocusWindow = nil
	self:MigratePlayerLocationOptions(profile)
	self:MigrateOwnChatBubbleMode(profile)
	for key, default in pairs(self.DEFAULTS.profile) do
		local value = self:ValidateSetting(key, profile[key])
		profile[key] = value
		if value == nil then
			profile[key] = self:DeepCopy(default)
		end
	end
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
