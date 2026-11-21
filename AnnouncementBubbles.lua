-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local Services = QuestTogether.NameplateServices
local ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS = 0.4
local ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS = 0.2
local ANNOUNCEMENT_BUBBLE_Y_OFFSET = 22
local function ApplyAnnouncementIconVisual(texture, eventType, iconAsset, iconKind)
	if not texture then
		return
	end
	local asset, kind = QuestTogether:ResolveAnnouncementDisplayIcon(eventType, iconAsset, iconKind)
	if kind == "atlas" and texture.SetAtlas then
		texture:SetAtlas(asset, true)
	else
		texture:SetTexture(
			kind ~= "atlas" and type(asset) == "string" and asset ~= "" and asset
				or QuestTogether.NAMEPLATE_PLAYER_ICON_TEXTURE
		)
	end
	texture:SetTexCoord(0, 1, 0, 1)
end

local function CreateAnnouncementBubbleFrame(parentFrame)
	-- ChatBubbleTemplate is not guaranteed in all UI states; degrade to a plain frame bubble.
	local ok, bubble = pcall(CreateFrame, "Frame", nil, parentFrame, "ChatBubbleTemplate")
	if ok and bubble then
		return bubble
	end

	local fallbackBubble = CreateFrame("Frame", nil, parentFrame)
	local background = fallbackBubble:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 1, 1, 0.92)
	fallbackBubble.Background = background

	local text = fallbackBubble:CreateFontString(nil, "ARTWORK", "ChatBubbleFont")
	fallbackBubble.String = text
	if text.SetNonSpaceWrap then
		text:SetNonSpaceWrap(true)
	end

	local tail = fallbackBubble:CreateTexture(nil, "ARTWORK")
	fallbackBubble.Tail = tail
	tail:SetColorTexture(1, 1, 1, 0.92)
	tail:SetSize(10, 10)
	tail:SetPoint("TOP", fallbackBubble, "BOTTOM", 0, 4)
	tail:SetRotation(math.rad(45))

	local icon = fallbackBubble:CreateTexture(nil, "ARTWORK")
	fallbackBubble.Icon = icon
	ApplyAnnouncementIconVisual(icon, nil)

	return fallbackBubble
end

local function ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, bubble)
	if not hostFrame or not unitFrame or not bubble then
		return
	end
	if
		not Services.Access.CanMutateFrame(hostFrame)
		or not Services.Access.CanMutateFrame(unitFrame)
		or not Services.Access.CanMutateFrame(bubble)
	then
		return
	end

	local frameStrata = "LOW"
	local getFrameStrata = select(1, QuestTogether:GetAccessibleFrameMember(hostFrame, "GetFrameStrata"))
	if type(getFrameStrata) == "function" then
		local okStrata, resolvedStrata = pcall(getFrameStrata, hostFrame)
		if okStrata then
			frameStrata = Services.Access.SafeTrimText(resolvedStrata)
			if frameStrata == "" then
				frameStrata = "LOW"
			end
		end
	end

	local frameLevel = 20
	local getFrameLevel = select(1, QuestTogether:GetAccessibleFrameMember(unitFrame, "GetFrameLevel"))
	if type(getFrameLevel) == "function" then
		local okLevel, resolvedLevel = pcall(getFrameLevel, unitFrame)
		if okLevel then
			frameLevel = Services.Access.SafeUiNumber(resolvedLevel, 0) + 20
		end
	end
	bubble:SetFrameStrata(frameStrata)
	bubble:SetFrameLevel(frameLevel)
end

local function EnsureAnnouncementBubble(hostFrame)
	if not Services.Access.CanMutateFrame(hostFrame) then
		return nil
	end

	local unitFrame = Services.Personal.GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return nil
	end

	local existingBubble = QuestTogether:GetNameplateStateStore().bubbleByUnitFrame[unitFrame]
	if existingBubble then
		if not Services.Access.CanMutateFrame(existingBubble) then
			return nil
		end
		-- Blizzard pools UnitFrames independently from the base nameplates.
		-- Our cache follows the UnitFrame; our bubble must follow its new host.
		if Services.Access.CallAccessibleFrameMethod(existingBubble, "GetParent") ~= hostFrame then
			local setParent = select(1, QuestTogether:GetAccessibleFrameMember(existingBubble, "SetParent"))
			if type(setParent) ~= "function" then
				return nil
			end
			local ok = pcall(setParent, existingBubble, hostFrame)
			if not ok or not Services.Access.CanMutateFrame(existingBubble) then
				return nil
			end
		end
		ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, existingBubble)
		return existingBubble
	end

	local bubble = CreateAnnouncementBubbleFrame(hostFrame)
	if not bubble or not bubble.String then
		return nil
	end
	if not Services.Access.CanMutateFrame(bubble) or not Services.Access.CanMutateFrame(bubble.String) then
		return nil
	end

	ApplyAnnouncementBubbleLayering(hostFrame, unitFrame, bubble)
	bubble:SetAlpha(0)
	bubble:Hide()

	bubble:ClearAllPoints()

	bubble.String:ClearAllPoints()
	bubble.String:SetJustifyH("LEFT")
	bubble.String:SetJustifyV("MIDDLE")
	bubble.String:SetTextColor(1, 0.82, 0, 1)
	if bubble.String.SetNonSpaceWrap then
		bubble.String:SetNonSpaceWrap(true)
	end
	if bubble.String.SetSpacing then
		bubble.String:SetSpacing(1)
	end

	if not bubble.Icon then
		local icon = bubble:CreateTexture(nil, "ARTWORK", nil, 1)
		bubble.Icon = icon
	end
	ApplyAnnouncementIconVisual(bubble.Icon, nil)

	if bubble.Tail then
		bubble.Tail:ClearAllPoints()
		bubble.Tail:SetPoint("TOP", bubble, "BOTTOM", 0, 6)
	end

	local animationGroup = bubble:CreateAnimationGroup()
	local fadeIn = animationGroup:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetDuration(ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)

	local hold = animationGroup:CreateAnimation("Alpha")
	hold:SetOrder(2)
	local lifetimeSeconds = Services.Access.SafeUiNumber(
		Services.Personal.GetAnnouncementBubbleLifetimeSeconds(),
		QuestTogether.DEFAULTS.profile.chatBubbleDuration
	)
	hold:SetDuration(
		math.max(0, lifetimeSeconds - ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS - ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS)
	)
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)

	local fadeOut = animationGroup:CreateAnimation("Alpha")
	fadeOut:SetOrder(3)
	fadeOut:SetDuration(ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS)
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)

	animationGroup:SetScript("OnFinished", function()
		QuestTogether:CompleteAnnouncementBubblePlayback(bubble)
	end)
	animationGroup:SetScript("OnStop", function()
		QuestTogether:CompleteAnnouncementBubblePlayback(bubble)
	end)
	bubble.animationGroup = animationGroup
	bubble.fadeInAnimation = fadeIn
	bubble.holdAnimation = hold
	bubble.fadeOutAnimation = fadeOut

	QuestTogether:GetNameplateStateStore().bubbleByUnitFrame[unitFrame] = bubble
	return bubble
end

function QuestTogether:HideAnnouncementBubble(hostFrame)
	local unitFrame = Services.Personal.GetAnnouncementBubbleUnitFrame(hostFrame)
	if not hostFrame or not unitFrame then
		return
	end

	local bubble = self:GetNameplateStateStore().bubbleByUnitFrame[unitFrame]
	if not bubble then
		return
	end
	self:StopAndHideAnnouncementBubblePlayback(bubble)
end

function QuestTogether:ClearIgnoredAnnouncementBubbles()
	local discarded = 0
	for bubble, state in pairs(self:GetNameplateStateStore().bubbleStateByFrame or {}) do
		if
			state.unitToken ~= "player"
			and Services.Access.IsNonEmptyString(state.senderName)
			and self:IsIgnoredPlayerName(state.senderName)
		then
			discarded = discarded + 1
			-- The copied sender identity is addon-owned. Never resolve the old
			-- nameplate just to discard playback after its sender is ignored.
			if self:StopAndHideAnnouncementBubblePlayback(bubble, "ignored") then
				self:CancelNameplateVisualCleanup(bubble)
			else
				-- Stop already removed replayable data, even when the attached
				-- visual is forbidden or restricted. Finish hiding it when safe.
				local nameplateState = self:GetNameplateStateStore()
				self:QueueNameplateVisualCleanup(bubble, "bubble")
			end
		end
	end
	return discarded
end

function QuestTogether:RefreshOwnAnnouncementBubbleVisibility()
	if self:ShouldShowOwnChatBubble() then
		return
	end
	for bubble, state in pairs(self:GetNameplateStateStore().bubbleStateByFrame or {}) do
		if state.unitToken == "player" then
			-- Retire playback as well as hiding it. Leaving the group can allow
			-- future messages, but must never resurrect the discarded text.
			self:StopAndHideAnnouncementBubblePlayback(bubble, "own_bubble_visibility")
		end
	end
end

function QuestTogether:RefreshActiveAnnouncementBubbles()
	for unitFrame, bubble in pairs(self:GetNameplateStateStore().bubbleByUnitFrame) do
		local bubbleState = Services.Personal.GetAnnouncementBubbleState(bubble)
		local unitToken = bubbleState and bubbleState.unitToken or nil
		if unitToken == "player" and not self:ShouldShowOwnChatBubble() then
			self:StopAndHideAnnouncementBubblePlayback(bubble, "own_bubble_visibility")
		elseif self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken) then
			if bubbleState then
				if bubbleState.text then
					self:Debugf(
						"bubble",
						"playback_discard unit=%s reason=restricted",
						Services.Access.SafeText(unitToken, "")
					)
				end
				-- Discard replayable data immediately; the addon-owned side tables
				-- are safe even when the attached visual cannot be touched yet.
				Services.Personal.SetAnnouncementBubbleState(bubble, { unitToken = unitToken })
			end
		else
			local shouldHide = not self.isEnabled
				or not self:GetOption("showChatBubbles")
				or not bubbleState
				or not Services.Access.IsNonEmptyString(bubbleState.text)
			if
				not shouldHide
				and bubbleState
				and bubbleState.senderName
				and self.ShouldShowAnnouncementsForRemoteSender
			then
				shouldHide = not self:ShouldShowAnnouncementsForRemoteSender(bubbleState.senderName, true)
			end
			if not shouldHide and bubbleState then
				local hostFrame = unitToken and self:GetAnnouncementBubbleHostFrameForUnit(unitToken) or nil
				shouldHide = not hostFrame or Services.Personal.GetAnnouncementBubbleUnitFrame(hostFrame) ~= unitFrame
				if not shouldHide and unitToken ~= "player" then
					shouldHide = not self:CanAccessForeignFrame(hostFrame, true)
						or not bubbleState.unitGUID
						or self:GetNameplateUnitGuid(unitToken) ~= bubbleState.unitGUID
				end
			end
			if not shouldHide then
				-- A settings/context refresh is never a new announcement. A stopped
				-- animation or a lost completion callback must not replay old text.
				shouldHide = not (bubble.animationGroup and bubble.animationGroup:IsPlaying())
			end
			if shouldHide then
				self:StopAndHideAnnouncementBubblePlayback(bubble, "refresh_policy_identity_or_finished")
			end
		end
	end
end

function QuestTogether:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if unitToken == "player" then
		return Services.Personal.GetAnnouncementBubbleScreenHostFrame()
	end

	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
	return namePlateFrameBase
end

function QuestTogether:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	if unitToken == "player" and not self:ShouldShowOwnChatBubble() then
		return false, L("Unable to show a bubble on that nameplate.")
	end
	local hostFrame = self:GetAnnouncementBubbleHostFrameForUnit(unitToken)
	if hostFrame then
		if not self:ShowAnnouncementBubbleOnNameplate(hostFrame, text, eventType, iconAsset, iconKind) then
			self:Debugf("bubble", "Failed to show bubble on host for unit=%s", Services.Access.SafeText(unitToken, ""))
			return false, L("Unable to show a bubble on that nameplate.")
		end
		local unitName = self:GetUnitFullName(unitToken)
		return true, unitName or unitToken
	end

	if unitToken ~= "player" then
		return false, L("No visible nameplate found for that unit.")
	end
	return false, L("Your personal bubble anchor is unavailable.")
end

function QuestTogether:ShowAnnouncementBubbleOnNameplate(
	namePlateFrameBase,
	text,
	eventType,
	iconAsset,
	iconKind,
	senderName
)
	local isPersonalBubble = namePlateFrameBase == self.announcementBubbleScreenHostFrame
	local normalizedSenderName = not isPersonalBubble and self:NormalizeMemberName(senderName) or nil
	if normalizedSenderName and self:IsIgnoredPlayerName(normalizedSenderName) then
		return false
	end
	local policyUnitToken = isPersonalBubble and "player" or "nameplate"
	if not self.isEnabled or not self:GetOption("showChatBubbles") then
		self:Debug("show_suppressed reason=bubbles_disabled", "bubble")
		return false
	end
	if isPersonalBubble and not self:ShouldShowOwnChatBubble() then
		self:Debug("show_suppressed unit=player reason=own_bubble_visibility", "bubble")
		return false
	end
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(policyUnitToken) then
		self:Debugf("bubble", "show_suppressed unit=%s reason=restricted", policyUnitToken)
		return false
	end

	local unitFrame = Services.Personal.GetAnnouncementBubbleUnitFrame(namePlateFrameBase)
	if not namePlateFrameBase or not unitFrame then
		return false
	end
	if not Services.Access.CanMutateFrame(namePlateFrameBase) or not Services.Access.CanMutateFrame(unitFrame) then
		return false
	end
	local message = Services.Access.SafeTrimText(text)
	if message == "" then
		return false
	end

	local bubble = EnsureAnnouncementBubble(namePlateFrameBase)
	if not bubble or not bubble.String then
		self:Debug("Failed to create or resolve bubble frame", "bubble")
		return false
	end
	if not Services.Access.CanMutateFrame(bubble) or not Services.Access.CanMutateFrame(bubble.String) then
		return false
	end

	local bubbleUnitToken = nil
	if isPersonalBubble then
		bubbleUnitToken = "player"
	else
		bubbleUnitToken = Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	end
	if not Services.Access.IsNonEmptyString(bubbleUnitToken) then
		return false
	end
	local bubbleUnitGUID = not isPersonalBubble and self:GetNameplateUnitGuid(bubbleUnitToken) or nil
	if not isPersonalBubble and not bubbleUnitGUID then
		return false
	end
	if bubble.animationGroup and bubble.animationGroup:IsPlaying() then
		bubble.animationGroup:Stop()
	end

	local anchorFrame, anchorReadable = self:GetAccessibleFrameMember(unitFrame, "HealthBarsContainer")
	if not anchorReadable then
		return false
	end
	anchorFrame = anchorFrame or unitFrame
	if not self:CanAccessForeignFrame(anchorFrame) then
		anchorFrame = unitFrame
	end
	if not self:CanAccessForeignFrame(anchorFrame) then
		return false
	end
	local visualConfig = Services.Personal.GetAnnouncementBubbleVisualConfig()
	local inset = Services.Access.SafeUiNumber(visualConfig.inset, 16)
	local minTextWidth = Services.Access.SafeUiNumber(visualConfig.minTextWidth, 48)
	local maxTextWidth = Services.Access.SafeUiNumber(visualConfig.maxTextWidth, 220)
	local iconSize = Services.Access.SafeUiNumber(visualConfig.iconSize, 18)
	local iconGap = Services.Access.SafeUiNumber(visualConfig.iconGap, 8)
	local fontSize = Services.Access.SafeUiNumber(visualConfig.fontSize, 14)
	local lifetimeSeconds = Services.Access.SafeUiNumber(
		Services.Personal.GetAnnouncementBubbleLifetimeSeconds(),
		QuestTogether.DEFAULTS.profile.chatBubbleDuration
	)

	if bubble.holdAnimation then
		local holdSeconds =
			math.max(0, lifetimeSeconds - ANNOUNCEMENT_BUBBLE_FADE_IN_SECONDS - ANNOUNCEMENT_BUBBLE_FADE_OUT_SECONDS)
		bubble.holdAnimation:SetDuration(holdSeconds)
	end

	local fontPath, _, fontFlags = bubble.String:GetFont()
	if fontPath and bubble.String.SetFont then
		bubble.String:SetFont(fontPath, fontSize, fontFlags)
	end

	bubble.String:SetWidth(maxTextWidth)
	-- Bubbles are reused between human chat and quest announcements.
	if eventType == "QT_CHAT" then
		bubble.String:SetTextColor(1, 1, 1, 1)
	else
		bubble.String:SetTextColor(1, 0.82, 0, 1)
	end
	bubble.String:SetText(message)

	local measuredUnboundedWidth = nil
	if bubble.String.GetUnboundedStringWidth then
		local okWidth, widthValue = pcall(bubble.String.GetUnboundedStringWidth, bubble.String)
		if okWidth then
			measuredUnboundedWidth = Services.Access.SafeUiNumber(widthValue, nil)
		end
	end
	local unboundedWidth = measuredUnboundedWidth
		or Services.Personal.EstimateBubbleTextWidth(message, fontSize, minTextWidth, maxTextWidth)
	local targetTextWidth = math.min(maxTextWidth, math.max(minTextWidth, unboundedWidth))
	bubble.String:SetWidth(targetTextWidth)

	local measuredTextHeight = nil
	if bubble.String.GetStringHeight then
		local okHeight, textHeightValue = pcall(bubble.String.GetStringHeight, bubble.String)
		if okHeight then
			measuredTextHeight = Services.Access.SafeUiNumber(textHeightValue, nil)
		end
	end
	local textHeight = measuredTextHeight
		or Services.Personal.EstimateBubbleTextHeight(message, targetTextWidth, fontSize)
	local contentHeight = math.max(iconSize, textHeight)
	local contentWidth = iconSize + iconGap + targetTextWidth
	local bubbleWidth = contentWidth + (inset * 2)
	local bubbleHeight = contentHeight + (inset * 2)
	bubble:ClearAllPoints()
	bubble:SetPoint("BOTTOM", anchorFrame, "TOP", 0, ANNOUNCEMENT_BUBBLE_Y_OFFSET)
	bubble:SetSize(bubbleWidth, bubbleHeight)

	if bubble.Icon then
		ApplyAnnouncementIconVisual(bubble.Icon, eventType, iconAsset, iconKind)
		bubble.Icon:ClearAllPoints()
		bubble.Icon:SetSize(iconSize, iconSize)
		bubble.Icon:SetPoint("CENTER", bubble, "CENTER", -((iconGap + targetTextWidth) / 2), 0)
		bubble.Icon:Show()
	end

	bubble.String:ClearAllPoints()
	bubble.String:SetWidth(targetTextWidth)
	bubble.String:SetPoint("CENTER", bubble, "CENTER", ((iconSize + iconGap) / 2), 0)

	if bubble.SetClampRectInsets then
		bubble:SetClampRectInsets(0, 0, 0, 0)
	end
	-- The personal host is a one-pixel anchor outside Edit Mode. Clamp the
	-- measured bubble itself so a saved edge position also fits smaller displays.
	-- Nearby players' bubbles remain attached to their nameplates as before.
	if isPersonalBubble then
		bubble:SetClampedToScreen(true)
	end

	Services.Personal.SetAnnouncementBubbleState(bubble, {
		text = message,
		eventType = type(eventType) == "string" and eventType ~= "" and eventType or nil,
		iconAsset = type(iconAsset) == "string" and iconAsset ~= "" and iconAsset or nil,
		iconKind = type(iconKind) == "string" and iconKind ~= "" and iconKind or nil,
		unitToken = bubbleUnitToken,
		unitGUID = bubbleUnitGUID,
		senderName = normalizedSenderName,
	})
	bubble:SetAlpha(0)
	self:CancelNameplateVisualCleanup(bubble)
	bubble:Show()
	if bubble.Tail then
		bubble.Tail:Show()
	end
	if bubble.animationGroup then
		bubble.animationGroup:Play()
	end
	self:Debugf(
		"bubble",
		"playback_start unit=%s guid=%s event=%s duration=%.1f text=%s",
		bubbleUnitToken,
		Services.Access.SafeText(bubbleUnitGUID, ""),
		Services.Access.SafeText(eventType, ""),
		lifetimeSeconds,
		message
	)
	return true
end

function QuestTogether:ShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
	if type(unitToken) ~= "string" or unitToken == "" then
		return false, L("No unit token was provided.")
	end
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext(unitToken) then
		return false, L("Announcement bubbles are unavailable in the current context.")
	end

	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
		if unitToken ~= "player" then
			return false, L("Nameplates are unavailable.")
		end
	end

	return self:TryShowAnnouncementBubbleOnUnitNameplate(unitToken, text, eventType, iconAsset, iconKind)
end

function QuestTogether:ShowAnnouncementBubbleOnRandomVisiblePlayer(text)
	if self:IsAnnouncementBubbleAugmentationBlockedInCurrentContext("nameplate") then
		return false, L("Announcement bubbles are unavailable in the current context.")
	end

	local candidateNameplates = {}

	self:ForEachVisibleNamePlate(function(frame)
		local unitFrame, memberReadable = self:GetAccessibleFrameMember(frame, "UnitFrame")
		if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
			return
		end

		local unitToken = Services.Access.ResolveNameplateUnitToken(frame, unitFrame)
		if not unitToken or not self:IsNameplateUnitToken(unitToken) then
			return
		end
		if not self:IsNameplateUnitPlayer(unitToken) then
			return
		end
		if self.API.UnitIsUnit and self.API.UnitIsUnit(unitToken, "player") then
			return
		end

		candidateNameplates[#candidateNameplates + 1] = frame
	end)

	if #candidateNameplates == 0 then
		return false, L("No visible player nameplates found.")
	end

	local randomIndex = self.API.Random(1, #candidateNameplates)
	local namePlateFrameBase = candidateNameplates[randomIndex]
	if not self:ShowAnnouncementBubbleOnNameplate(namePlateFrameBase, text) then
		return false, L("Unable to show a bubble on the selected nameplate.")
	end

	local unitFrame = select(1, self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame"))
	local unitToken = unitFrame and Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame) or nil
	local unitName = unitToken and self:GetUnitFullName(unitToken) or nil
	return true, unitName or L("Unknown")
end
