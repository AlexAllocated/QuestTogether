local L = _G.QuestTogether.Translate
-- Welcome and release notes use account-wide version state, separate from the
-- enabled runtime lifetime so disabled announcements do not suppress the UI.
local Addon = _G.QuestTogether
local DISCORD_URL = "https://discord.gg/Uxyyvhfva9"

function Addon:RenderDiscordSupportLink(url)
	return self:ShowDiscordLinkDialog(url)
end

function Addon:OpenDiscordSupport()
	if self:IsRuntimeRestricted() or not self:CanAccessForeignFrame(self:GetReleaseNotesUIParent(), true) then
		return false
	end
	local ok, shown = pcall(self.RenderDiscordSupportLink, self, DISCORD_URL)
	if not ok or shown ~= true then
		self:Print(L("QuestTogether Discord — feedback and support tickets: ") .. DISCORD_URL)
		return false
	end
	return true
end

function Addon:GetReleaseNotesSeries(version)
	local text = self:SafeTrimString(version, "")
	local major, minor, patch, suffix = text:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
	if not major or (suffix ~= "" and not suffix:match("^%-alpha%.%d+$") and not suffix:match("^%-beta%.%d+$")) then
		return nil
	end
	major, minor, patch = self:SafeToNumber(major), self:SafeToNumber(minor), self:SafeToNumber(patch)
	if not major or not minor or not patch then
		return nil
	end
	return major, minor
end

function Addon:ShouldShowReleaseNotes(version)
	if not self.db or type(self.db.global) ~= "table" then
		return false
	end
	local major, minor = self:GetReleaseNotesSeries(version)
	if not major then
		return false
	end
	local seenMajor, seenMinor = self:GetReleaseNotesSeries(self.db.global.releaseNotesSeenVersion)
	return not seenMajor or major > seenMajor or (major == seenMajor and minor > seenMinor)
end

function Addon:GetCurrentReleaseNotes()
	local version = self:GetAddonVersion()
	local notes = rawget(self, "releaseNotes")
	local translated = self.releaseNotesByLocale and self.releaseNotesByLocale[self.localizationTestLocale or self.locale]
	if translated and notes and translated.version == notes.version then notes = translated end
	if
		not self:GetReleaseNotesSeries(version)
		or type(notes) ~= "table"
		or notes.version ~= version
		or type(notes.welcome) ~= "string"
		or notes.welcome == ""
		or type(notes.sections) ~= "table"
		or #notes.sections == 0
	then
		return nil
	end
	return notes, version
end

function Addon:CanPresentReleaseNotes()
	return self.hasLoggedIn == true
		and not self.isLoggingOut
		and not self:IsRuntimeRestricted()
		and self:CanAccessForeignFrame(self:GetReleaseNotesUIParent(), true)
end

function Addon:GetReleaseNotesCatalog(notes, version)
	local dates = rawget(self, "releaseNotesDates") or {}
	local entries = { { notes = notes, version = version, date = dates[version] } }
	local locale = self.localizationTestLocale or self.locale or "enUS"
	if locale == "enGB" then locale = "enUS" end
	local seen = { [version] = true }
	for _, entry in ipairs(rawget(self, "releaseNotesHistory") or {}) do
		local archived = type(entry.locales) == "table" and (entry.locales[locale] or entry.locales.enUS)
		if type(archived) == "table" and self:GetReleaseNotesSeries(entry.version)
			and not seen[entry.version] and archived.version == entry.version then
			entries[#entries + 1] = {
				notes = archived, version = entry.version, date = entry.date,
				englishOnly = locale ~= "enUS" and not entry.locales[locale],
			}
			seen[entry.version] = true
		end
	end
	return entries
end

function Addon:ShowReleaseNotesPage(index, history)
	local browser = rawget(self, "releaseNotesBrowser")
	index = self:SafeToNumber(index)
	if not browser or not index or index ~= math.floor(index) or not browser.entries[index]
		or not self:CanPresentReleaseNotes() then return false end
	local oldIndex, oldHistory = browser.index, browser.history
	browser.index, browser.history = index, history == true
	local entry = browser.entries[index]
	local ok, shown = pcall(self.RenderReleaseNotesWindow, self, entry.notes, entry.version, false)
	if not ok or shown ~= true then
		browser.index, browser.history = oldIndex, oldHistory
		return false
	end
	-- Browsing history never acknowledges an upgrade or changes startup state.
	return true
end

function Addon:CreateReleaseNotesWakeFrame()
	-- No foreign parent or hooks. The short-lived listener also works while
	-- runtime announcements are disabled or UIParent is temporarily hidden.
	return CreateFrame("Frame")
end

function Addon:StopReleaseNotesWakeup()
	self.pendingReleaseNotes = nil
	local frame = rawget(self, "releaseNotesWakeFrame")
	if frame and self.LibChev.CanMutateOwnedRegion(frame) then
		frame:SetScript("OnUpdate", nil)
		frame:UnregisterAllEvents()
	end
end

function Addon:OpenReleaseNotes(automatic)
	local notes, version = self:GetCurrentReleaseNotes()
	if not notes or not self:CanPresentReleaseNotes() then
		if not automatic then
			self:Print(L("Patch notes are unavailable right now. Try again when UI restrictions end."))
		end
		return false
	end
	local global = self.db and self.db.global
	local seenMajor, seenMinor = self:GetReleaseNotesSeries(global and global.releaseNotesSeenVersion)
	local previousBrowser = rawget(self, "releaseNotesBrowser")
	self.releaseNotesBrowser = { entries = self:GetReleaseNotesCatalog(notes, version), index = 1, history = false }
	-- Contain a partial installation or a failed UI build without breaking login.
	-- The renderer guards native access itself; pcall is not a taint barrier.
	local ok, shown = pcall(self.RenderReleaseNotesWindow, self, notes, version, seenMajor == nil)
	if not ok or shown ~= true then
		self.releaseNotesBrowser = previousBrowser
		if not automatic then
			self:Print(L("Unable to open patch notes right now."))
		end
		return false
	end
	local major, minor = self:GetReleaseNotesSeries(version)
	if global and (not seenMajor or major > seenMajor or (major == seenMajor and minor >= seenMinor)) then
		-- Record only a successfully visible window; never lower the remembered
		-- release series on a downgrade, or repeat for another character/profile.
		global.releaseNotesSeenVersion = version
	end
	self:StopReleaseNotesWakeup()
	return true
end

function Addon:TryPendingReleaseNotes()
	local pending = rawget(self, "pendingReleaseNotes")
	if not pending then
		return false
	end
	local notes, version = self:GetCurrentReleaseNotes()
	if self.isLoggingOut or not notes or version ~= pending.version or not self:ShouldShowReleaseNotes(version) then
		self:StopReleaseNotesWakeup()
		return false
	end
	if not self:CanPresentReleaseNotes() then
		return false
	end
	-- Poll only for presentation eligibility, not failed render attempts. A
	-- failed build may retry on a release event or an explicit user request.
	local frame = rawget(self, "releaseNotesWakeFrame")
	if frame and self.LibChev.CanMutateOwnedRegion(frame) then
		frame:SetScript("OnUpdate", nil)
	end
	return self:OpenReleaseNotes(true)
end

function Addon:InitializeReleaseNotes()
	local notes, version = self:GetCurrentReleaseNotes()
	if not self.hasLoggedIn or not notes or not self:ShouldShowReleaseNotes(version) then
		self:StopReleaseNotesWakeup()
		return false
	end
	local frame = rawget(self, "releaseNotesWakeFrame")
	if not frame then
		frame = self:CreateReleaseNotesWakeFrame()
		self.releaseNotesWakeFrame = frame
	end
	if not self.LibChev.CanMutateOwnedRegion(frame) then
		return false
	end
	local pending = { version = version, elapsed = 0 }
	self.pendingReleaseNotes = pending
	frame:SetScript("OnEvent", function()
		self:TryPendingReleaseNotes()
	end)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnUpdate", function(_, elapsed)
		if rawget(self, "pendingReleaseNotes") ~= pending then
			return
		end
		pending.elapsed = pending.elapsed + math.max(0, self:SafeToNumber(elapsed) or 0)
		if pending.elapsed >= 0.5 then
			pending.elapsed = 0
			self:TryPendingReleaseNotes()
		end
	end)
	return self:TryPendingReleaseNotes()
end
