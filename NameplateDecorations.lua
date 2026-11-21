-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Services = QuestTogether.NameplateServices
local EnsureQuestIcon
local ApplyQuestIconVisual
function QuestTogether:ShouldShowQuestNameplateIconForResolvedState(unitToken, unitFrame, isQuestObjective)
	if not self:GetOption("nameplateQuestIconEnabled") then
		return false
	end

	return self:ShouldApplyResolvedQuestVisualState(unitToken, unitFrame, isQuestObjective)
end

local function DeferBlockedQuestPlatePresentation(addon, plate, unitToken)
	if not addon:IsWorkBlocked("nameplate_refresh") then
		return false
	end
	addon:HideNameplateIcon(plate)
	if
		addon.isEnabled
		and addon:IsNameplateUnitToken(unitToken)
		and not addon:IsRuntimeWorkPending("nameplate_refresh", unitToken)
	then
		addon:ScheduleNameplateRefresh(unitToken)
	end
	return true
end

function QuestTogether:ApplyResolvedQuestStateToNameplate(
	namePlateFrameBase,
	unitToken,
	unitFrame,
	isQuestObjective,
	scheduleTintFollowUp,
	resolvedUnitGuid
)
	if not namePlateFrameBase or not unitFrame then
		return
	end

	local resolvedUnitToken = unitToken
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitToken = Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	end
	if self:IsNameplateUnitToken(resolvedUnitToken) and self:IsNameplateUnitPlayer(resolvedUnitToken) then
		self:RefreshQTPlayerNameplate(namePlateFrameBase, resolvedUnitToken, unitFrame)
		return
	end
	-- Cached NPC relevance can reach this presenter directly from a plate-added
	-- event, without passing through the deferred-work policy. Cleanup is safe
	-- when its owned regions are mutable; layout/show must wait for the same
	-- policy as scheduled presentation, including map and encounter restrictions.
	if DeferBlockedQuestPlatePresentation(self, namePlateFrameBase, resolvedUnitToken) then
		return
	end
	if not Services.Access.IsNonEmptyString(resolvedUnitGuid) and self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitGuid = self:GetNameplateTooltipScanGuid(resolvedUnitToken, unitFrame)
	end

	local shouldShow = self:ShouldShowQuestNameplateIconForResolvedState(resolvedUnitToken, unitFrame, isQuestObjective)
	local icon = self:GetNameplateStateStore().iconByUnitFrame[unitFrame]
	if resolvedUnitToken and resolvedUnitGuid then
		self:StoreResolvedNameplateQuestState(resolvedUnitToken, resolvedUnitGuid, isQuestObjective)
	end

	local canScheduleTintFollowUp = scheduleTintFollowUp and Services.Access.IsNonEmptyString(resolvedUnitGuid)
	self:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective, canScheduleTintFollowUp == true)
	if
		canScheduleTintFollowUp
		and isQuestObjective
		and type(resolvedUnitToken) == "string"
		and resolvedUnitToken ~= ""
	then
		self:ScheduleNameplateHealthTintRefresh(resolvedUnitToken, 0.05, true)
	end

	if shouldShow then
		if icon then
			if not self:SetNameplateIconKind(icon, "quest") then
				self:HideNameplateIcon(namePlateFrameBase)
				return
			end
			self:ApplyNameplateQuestIconStyle(icon, unitFrame)
		else
			icon = EnsureQuestIcon(unitFrame)
		end
		if not icon then
			return
		end
		if Services.Access.CanMutateFrame(icon) then
			self:CancelNameplateVisualCleanup(icon)
			icon:Show()
		end
	elseif icon then
		if Services.Access.CanMutateFrame(icon) then
			icon:Hide()
		end
		if isQuestObjective ~= true then
			self:RestoreNameplateHealthColor(unitFrame)
		end
	end
end

function QuestTogether:ShouldApplyResolvedQuestVisualState(unitToken, unitFrame, isQuestObjective)
	if not self.isEnabled then
		return false
	end
	if self:IsNameplateAugmentationBlockedInCurrentContext() then
		return false
	end
	if isQuestObjective ~= true then
		return false
	end

	if not unitFrame then
		return false
	end
	if Services.Access.IsFrameForbidden(unitFrame) then
		return false
	end

	local resolvedUnitToken = unitToken
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		resolvedUnitToken = Services.Access.ResolveNameplateUnitToken(nil, unitFrame)
	end
	if not self:IsNameplateUnitToken(resolvedUnitToken) then
		return false
	end

	if not Services.Access.GetAccessibleChildFrame(unitFrame, "healthBar") then
		return false
	end

	if not self:DoesNameplateUnitExist(resolvedUnitToken) then
		return false
	end

	-- Never tint players; this is intended for quest mobs/NPCs.
	if self:IsNameplateUnitPlayer(resolvedUnitToken) then
		return false
	end

	-- Plater's quest-color path only suppresses tap-denied hostile units
	-- (local retail Plater.lua:8993-9004). It does not gate quest visuals on
	-- dead or disconnected state, so keep the visual decision aligned here.
	if self:IsNameplateUnitTapDenied(resolvedUnitToken) then
		return false
	end

	return true
end

-- Keep tinting conservative so we do not override important Blizzard states.
function QuestTogether:ShouldApplyQuestHealthTint(frame, isQuestObjective)
	if not self:GetOption("nameplateQuestHealthColorEnabled") then
		return false
	end

	local resolvedUnitToken = Services.Access.ResolveNameplateUnitToken(nil, frame)
	if not resolvedUnitToken then
		return false
	end

	if isQuestObjective ~= nil then
		return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, isQuestObjective)
	end

	local cachedQuestObjective = self:GetNameplateStateStore().questStateByUnitToken[resolvedUnitToken]
	local cachedUnitGuid = self:GetNameplateStateStore().questGuidByUnitToken[resolvedUnitToken]
	if cachedQuestObjective ~= nil and Services.Access.IsNonEmptyString(cachedUnitGuid) then
		local hasCachedQuestState, resolvedCachedQuestState =
			self:TryGetReusableCachedNameplateQuestState(resolvedUnitToken, cachedUnitGuid)
		if hasCachedQuestState then
			return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, resolvedCachedQuestState)
		end
	end

	local hasResolvedQuestState, isQuestObjectiveNameplate =
		self:TryResolveNameplateQuestObjectiveState(resolvedUnitToken, frame, false)
	if not hasResolvedQuestState then
		return false
	end

	return self:ShouldApplyResolvedQuestVisualState(resolvedUnitToken, frame, isQuestObjectiveNameplate)
end

local function GetIconBarAnchor(unitFrame)
	return Services.Access.GetAccessibleChildFrame(unitFrame, "healthBar")
		or Services.Access.GetAccessibleChildFrame(unitFrame, "HealthBarsContainer")
		or unitFrame
end

local function GetRightIconAnchor(addon, unitFrame, barAnchor)
	if addon:IsWorkBlocked("nameplate_refresh") or not addon:UsesRegionalPlayerNames() then
		return barAnchor
	end
	-- Forever's level box is on the right; Retail's is on the left. Follow the
	-- known Forever frame directly: both coordinates and GetPoint can throw on
	-- visible nameplates even though the frame remains accessible as an anchor.
	local level = Services.Access.GetAccessibleChildFrame(unitFrame, "PlayerLevelDiffFrame")
	if Services.Access.CallAccessibleFrameMethod(level, "IsVisible") ~= true then
		return barAnchor
	end
	local border = Services.Access.GetAccessibleChildFrame(level, "selectedBorder")
	if Services.Access.CallAccessibleFrameMethod(border, "IsVisible") == true then
		return border
	end
	return level
end

local function GetPlayerBuffIconAnchor(unitFrame)
	-- Current Retail/Forever buffs grow left from the classification marker.
	-- Empty lists stay shown with a nonzero width, so check visible children,
	-- never aura contents, frame pools, or Blizzard's layout helpers.
	local auras = Services.Access.GetAccessibleChildFrame(unitFrame, "AurasFrame")
	if Services.Access.CallAccessibleFrameMethod(auras, "IsShown") ~= true then
		return nil
	end
	local buffs = Services.Access.GetAccessibleChildFrame(auras, "BuffListFrame")
	if Services.Access.CallAccessibleFrameMethod(buffs, "IsShown") ~= true then
		return nil
	end
	local count = Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(buffs, "GetNumChildren"))
	local getChildren = select(1, QuestTogether:GetAccessibleFrameMember(buffs, "GetChildren"))
	-- Blizzard currently displays at most two. Bound work if another layout
	-- changes this container; older/unknown layouts keep the normal bar anchor.
	if not count or count < 1 or count > 8 or count % 1 ~= 0 or type(getChildren) ~= "function" then
		return nil
	end
	local ok, children = pcall(function()
		return { getChildren(buffs) }
	end)
	if not ok then
		return nil
	end
	local occupied, border = false, 2
	local unitScale =
		Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(unitFrame, "GetEffectiveScale"), 0)
	for index = 1, count do
		local child = children[index]
		if
			QuestTogether:CanAccessValue(child)
			and Services.Access.CallAccessibleFrameMethod(child, "IsShown") == true
		then
			occupied = true
			-- Keep a compact gap around the buff artwork, scaled to the logo
			-- parent without reading aura data.
			local childScale =
				Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(child, "GetEffectiveScale"), 0)
			if unitScale > 0 and childScale > 0 then
				border = math.max(border, Services.Access.SafeUiNumber(2 * childScale / unitScale, 2))
			end
		end
	end
	if occupied then
		-- Anchor to the stable list, not a pooled aura child that can be reused.
		return buffs, border + 2
	end
	return nil
end

local function GetNameplateNameTextAnchor(unitFrame)
	local healthBar = Services.Access.GetAccessibleChildFrame(unitFrame, "healthBar")
	return Services.Access.GetAccessibleChildFrame(unitFrame, "unitName")
		or Services.Access.GetAccessibleChildFrame(unitFrame, "name")
		or Services.Access.GetAccessibleChildFrame(healthBar, "unitName")
		or Services.Access.GetAccessibleChildFrame(healthBar, "name")
end

local function GetNameplateTextExtent(nameText, iconFrame, stringMethod, boxMethod)
	-- The name's box can span the whole bar even when its letters are centered.
	-- Measure the visible text without reading its contents or screen position.
	local extent = Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(nameText, stringMethod))
	if not extent or extent <= 0 then
		return
	end
	local boxExtent = Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(nameText, boxMethod))
	if boxExtent and boxExtent > 0 then
		extent = math.min(extent, boxExtent)
	else
		boxExtent = nil
	end
	local nameScale =
		Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(nameText, "GetEffectiveScale"))
	local iconScale =
		Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(iconFrame, "GetEffectiveScale"))
	if not nameScale or nameScale <= 0 or not iconScale or iconScale <= 0 then
		return
	end
	local ratio = nameScale / iconScale
	extent = Services.Access.SafeUiNumber(extent * ratio)
	if not extent or extent <= 0 then
		return
	end
	return extent, boxExtent and Services.Access.SafeUiNumber(boxExtent * ratio)
end

local function GetNameplatePrefixAnchor(addon, nameText, iconFrame, gap)
	if addon:IsWorkBlocked("nameplate_refresh") then
		return "LEFT", -gap
	end
	local justify = Services.Access.CallAccessibleFrameMethod(nameText, "GetJustifyH")
	if justify ~= "CENTER" and justify ~= "RIGHT" then
		return "LEFT", -gap
	end
	local width = GetNameplateTextExtent(nameText, iconFrame, "GetStringWidth", "GetWidth")
	if not width then
		return "LEFT", -gap
	end
	return justify, -(justify == "CENTER" and width / 2 or width) - gap
end

local function GetNameOnlyIconAnchor(addon, nameText, iconFrame, style, gap)
	local textHeight, boxHeight = GetNameplateTextExtent(nameText, iconFrame, "GetStringHeight", "GetHeight")
	local centerY = 0
	if textHeight and boxHeight then
		local justifyV = Services.Access.CallAccessibleFrameMethod(nameText, "GetJustifyV")
		if justifyV == "TOP" then
			centerY = (boxHeight - textHeight) / 2
		elseif justifyV == "BOTTOM" then
			centerY = -(boxHeight - textHeight) / 2
		end
	end
	if style == "left" or style == "prefix" then
		local point, x = GetNameplatePrefixAnchor(addon, nameText, iconFrame, gap)
		return "RIGHT", point, x, centerY
	end
	local justify = Services.Access.CallAccessibleFrameMethod(nameText, "GetJustifyH")
	local width = GetNameplateTextExtent(nameText, iconFrame, "GetStringWidth", "GetWidth")
	if style == "right" then
		if justify == "CENTER" and width then
			return "LEFT", "CENTER", width / 2 + gap, centerY
		end
		if justify == "LEFT" and width then
			return "LEFT", "LEFT", width + gap, centerY
		end
		return "LEFT", "RIGHT", gap, centerY
	end
	local point, x = "CENTER", 0
	if width and justify == "LEFT" then
		point, x = "LEFT", width / 2
	elseif width and justify == "RIGHT" then
		point, x = "RIGHT", -width / 2
	end
	if textHeight then
		return "BOTTOM", point, x, centerY + textHeight / 2 + gap
	end
	-- Older layouts may not expose text height. Their name-box edge remains a
	-- safe relative anchor without consulting restricted screen geometry.
	return "BOTTOM", point == "CENTER" and "TOP" or "TOP" .. point, x, gap
end

-- The texture and its animations belong exclusively to QT. A native animation
-- group keeps the pulse off our Lua update loop and preserves the logo contour.
function QuestTogether:CreateQTPlayerGlowPulse(layer, minimumAlpha, duration)
	if not Services.Access.CanMutateFrame(layer) then
		return nil
	end
	minimumAlpha = minimumAlpha or 0.55
	duration = duration or 1.2
	local create = self:GetAccessibleFrameMember(layer, "CreateAnimationGroup")
	if type(create) ~= "function" then
		return nil
	end
	local ok, group = pcall(create, layer)
	if not ok or not self:CanAccessTable(group) then
		return nil
	end
	local ready = pcall(function()
		group:SetLooping("REPEAT")
		for order = 1, 2 do
			local alpha = group:CreateAnimation("Alpha")
			alpha:SetOrder(order)
			alpha:SetFromAlpha(order == 1 and minimumAlpha or 1)
			alpha:SetToAlpha(order == 1 and 1 or minimumAlpha)
			alpha:SetDuration(duration)
			alpha:SetSmoothing("IN_OUT")
		end
	end)
	if ready then
		return group
	end
	-- Unsupported animation APIs retain a bright static glow.
	return nil
end

function QuestTogether:SetQTPlayerIconLookingForPartners(iconFrame, looking, glowAnchor, workClass)
	if not Services.Access.CanMutateFrame(iconFrame) then
		return false
	end
	glowAnchor = glowAnchor or iconFrame
	if not Services.Access.CanMutateFrame(glowAnchor) then
		return false
	end
	looking = looking == true
	local glow = iconFrame.qtPartnerGlow
	if looking and self:IsWorkBlocked(workClass or "nameplate_refresh") then
		return false
	end
	if not glow and not looking then
		iconFrame.qtLookingForPartners = false
		return true
	end
	if not glow then
		glow = {}
		iconFrame.qtPartnerGlow = glow
	end
	-- Offset translucent copies of the transparent logo create a contour glow.
	-- These owned background layers leave the original artwork and anchor alone.
	if looking and not iconFrame.qtPartnerGlowReady then
		for index = 1, 8 do
			if not glow[index] then
				local ok, layer = pcall(iconFrame.CreateTexture, iconFrame, nil, "BACKGROUND")
				if not ok or not Services.Access.CanMutateFrame(layer) then
					return false
				end
				layer:Hide()
				glow[index] = layer
			end
		end
		for _, layer in ipairs(glow) do
			if not Services.Access.CanMutateFrame(layer) then
				return false
			end
		end
		for index, layer in ipairs(glow) do
			local angle = (index - 1) * math.pi / 4
			local x, y = 4 * math.cos(angle), 4 * math.sin(angle)
			layer:SetTexture(self.NAMEPLATE_PLAYER_ICON_TEXTURE)
			layer:SetTexCoord(0, 1, 0, 1)
			layer:SetVertexColor(1, 0.78, 0.12, 0.9)
			layer:SetBlendMode("ADD")
			layer:ClearAllPoints()
			layer:SetPoint("TOPLEFT", glowAnchor, "TOPLEFT", x, y)
			layer:SetPoint("BOTTOMRIGHT", glowAnchor, "BOTTOMRIGHT", x, y)
		end
		iconFrame.qtPartnerGlowPulses = iconFrame.qtPartnerGlowPulses or {}
		for index, layer in ipairs(glow) do
			iconFrame.qtPartnerGlowPulses[index] = self:CreateQTPlayerGlowPulse(layer)
		end
		iconFrame.qtPartnerGlowReady = true
	end
	for _, layer in ipairs(glow) do
		if not Services.Access.CanMutateFrame(layer) then
			return false
		end
	end
	-- Resume after an engine-driven hide without restarting an active pulse.
	for index in ipairs(glow) do
		local pulse = iconFrame.qtPartnerGlowPulses and iconFrame.qtPartnerGlowPulses[index]
		if pulse then
			if looking then
				if not pulse:IsPlaying() then
					pulse:Play()
				end
			else
				pulse:Stop()
			end
		end
	end
	if iconFrame.qtLookingForPartners ~= looking then
		for _, layer in ipairs(glow) do
			if looking then
				layer:Show()
			else
				layer:Hide()
			end
		end
		iconFrame.qtLookingForPartners = looking
	end
	return true
end

function QuestTogether:SetNameplateIconKind(iconFrame, kind)
	if not Services.Access.CanMutateFrame(iconFrame) then
		return false
	end
	local texture = iconFrame.Icon
	if not texture or not Services.Access.CanMutateFrame(texture) then
		return false
	end
	if kind ~= "player" and not self:SetQTPlayerIconLookingForPartners(iconFrame, false) then
		return false
	end
	if iconFrame.qtIconKind == kind then
		return true
	end
	if kind == "player" then
		texture:SetTexture(self.NAMEPLATE_PLAYER_ICON_TEXTURE)
		texture:SetTexCoord(0, 1, 0, 1)
	elseif texture.SetAtlas and self.NAMEPLATE_QUEST_ICON_ATLAS then
		texture:SetAtlas(self.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
	else
		texture:SetTexture(self.NAMEPLATE_QUEST_ICON_TEXTURE)
		local coords = self.NAMEPLATE_QUEST_ICON_TEX_COORDS
		if coords then
			texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end
	iconFrame.qtIconKind = kind
	return true
end

function QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)
	if not iconFrame or not unitFrame then
		return
	end
	if not Services.Access.CanMutateFrame(iconFrame) or not self:CanAccessForeignFrame(unitFrame) then
		return
	end

	local icon = iconFrame.Icon or iconFrame
	if not Services.Access.CanMutateFrame(icon) then
		return
	end
	local healthBarsContainer = Services.Access.GetAccessibleChildFrame(unitFrame, "HealthBarsContainer")
	local style = iconFrame.qtIconKind == "player" and self:GetNameplatePlayerIconStyle()
		or self:GetNameplateQuestIconStyle()
	local playerIcon = iconFrame.qtIconKind == "player"
	-- Native friendly name-only plates retain an invisible health bar frame.
	-- Honor the same position setting around the rendered name in this mode.
	local nameOnly = playerIcon
		and not self:IsWorkBlocked("nameplate_refresh")
		and select(1, self:GetAccessibleFrameMember(unitFrame, "showOnlyName")) == true
	local nameText = nameOnly and GetNameplateNameTextAnchor(unitFrame)
	local gap = playerIcon and 4 or 1
	local width = self.NAMEPLATE_QUEST_ICON_WIDTH
	local height = self.NAMEPLATE_QUEST_ICON_HEIGHT
	local buffAnchor, buffGap
	if playerIcon and not nameOnly and style == "left" then
		buffAnchor, buffGap = GetPlayerBuffIconAnchor(unitFrame)
	end

	iconFrame:ClearAllPoints()

	if nameText then
		width = math.max(14, math.floor(width * 0.8 + 0.5))
		height = math.max(14, math.floor(height * 0.8 + 0.5))
		local point, relativePoint, x, y = GetNameOnlyIconAnchor(self, nameText, iconFrame, style, gap)
		iconFrame:SetPoint(point, nameText, relativePoint, x, y)
	elseif style == "left" then
		local barAnchor = buffAnchor or GetIconBarAnchor(unitFrame)
		if Services.Access.IsFrameForbidden(barAnchor) then
			barAnchor = unitFrame
		end
		iconFrame:SetPoint("RIGHT", barAnchor, "LEFT", -(buffGap or gap), 0)
	elseif style == "right" then
		local barAnchor = GetIconBarAnchor(unitFrame)
		if Services.Access.IsFrameForbidden(barAnchor) then
			barAnchor = unitFrame
		end
		iconFrame:SetPoint("LEFT", GetRightIconAnchor(self, unitFrame, barAnchor), "RIGHT", gap, 0)
	elseif style == "prefix" then
		local nameText = GetNameplateNameTextAnchor(unitFrame)
		if nameText then
			-- Keep the prefix icon large enough to remain legible on live nameplates.
			width = math.max(14, math.floor(width * 0.8 + 0.5))
			height = math.max(14, math.floor(height * 0.8 + 0.5))
			local point, offset = GetNameplatePrefixAnchor(self, nameText, iconFrame, playerIcon and 4 or 2)
			iconFrame:SetPoint("RIGHT", nameText, point, offset, 0)
		elseif healthBarsContainer then
			iconFrame:SetPoint("BOTTOM", healthBarsContainer, "TOP", 0, 16)
		else
			iconFrame:SetPoint("TOP", unitFrame, "TOP", 0, 12)
		end
	else
		-- Leave clearance above Blizzard's name text, not just the health bar.
		if healthBarsContainer then
			iconFrame:SetPoint("BOTTOM", healthBarsContainer, "TOP", 0, 16)
		else
			iconFrame:SetPoint("TOP", unitFrame, "TOP", 0, 12)
		end
	end

	iconFrame:SetSize(width, height)
	if icon and icon.SetAllPoints then
		icon:SetAllPoints(iconFrame)
	end
end

function QuestTogether:CreateNameplateQuestIconFrame(unitFrame)
	if not Services.Access.CanMutateFrame(unitFrame) then
		return nil
	end
	local ok, iconFrame = pcall(CreateFrame, "Frame", nil, unitFrame)
	if not ok or not Services.Access.CanMutateFrame(iconFrame) then
		return nil
	end
	return iconFrame
end

EnsureQuestIcon = function(unitFrame, kind)
	kind = kind or "quest"
	if not unitFrame then
		return nil
	end
	if not Services.Access.CanMutateFrame(unitFrame) then
		return nil
	end

	local existingIcon = QuestTogether:GetNameplateStateStore().iconByUnitFrame[unitFrame]
	if existingIcon then
		if not QuestTogether:SetNameplateIconKind(existingIcon, kind) then
			return nil
		end
		QuestTogether:ApplyNameplateQuestIconStyle(existingIcon, unitFrame)
		return existingIcon
	end

	local iconFrame = QuestTogether:CreateNameplateQuestIconFrame(unitFrame)
	if not iconFrame or not Services.Access.CanMutateFrame(iconFrame) then
		return nil
	end
	iconFrame:SetFrameStrata(Services.Access.CallAccessibleFrameMethod(unitFrame, "GetFrameStrata") or "LOW")
	iconFrame:SetFrameLevel(
		Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(unitFrame, "GetFrameLevel"), 0) + 30
	)

	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	iconFrame.Icon = icon
	QuestTogether:GetNameplateStateStore().iconByUnitFrame[unitFrame] = iconFrame

	iconFrame:Hide()
	if not QuestTogether:SetNameplateIconKind(iconFrame, kind) then
		return nil
	end
	QuestTogether:ApplyNameplateQuestIconStyle(iconFrame, unitFrame)

	return iconFrame
end

local function EnsureQuestHealthOverlay(unitFrame)
	local healthBar = Services.Access.GetAccessibleChildFrame(unitFrame, "healthBar")
	if not healthBar then
		return nil
	end
	if not Services.Access.CanMutateFrame(unitFrame) or not Services.Access.CanMutateFrame(healthBar) then
		return nil
	end

	local existingOverlay = QuestTogether:GetNameplateStateStore().healthOverlayByUnitFrame[unitFrame]
	if existingOverlay then
		return existingOverlay
	end

	local fillTexture = QuestTogether:CreateNameplateHealthOverlayTexture(healthBar, "ARTWORK", 0)
	local highlight = healthBar:CreateTexture(nil, "ARTWORK", nil, 1)
	if not fillTexture or not highlight then
		return nil
	end

	local overlay = {
		FillTexture = fillTexture,
		Highlight = highlight,
	}

	if fillTexture.Hide then
		fillTexture:Hide()
	end

	if highlight.SetBlendMode then
		highlight:SetBlendMode("ADD")
	end
	if highlight.Hide then
		highlight:Hide()
	end

	QuestTogether:GetNameplateStateStore().healthOverlayByUnitFrame[unitFrame] = overlay
	return overlay
end

local function AnchorQuestHealthFillTexture(texture, anchorTarget)
	if not texture or not anchorTarget then
		return
	end
	if not Services.Access.CanMutateFrame(texture) or Services.Access.IsFrameForbidden(anchorTarget) then
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 0, 0)
	texture:SetPoint("BOTTOMLEFT", anchorTarget, "BOTTOMLEFT", 0, 0)
	texture:SetPoint("TOPRIGHT", anchorTarget, "TOPRIGHT", 0, 0)
	texture:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", 0, 0)
end

local function GetQuestHealthOverlayAnchorTarget(unitFrame)
	local healthBar = Services.Access.GetAccessibleChildFrame(unitFrame, "healthBar")
	if not healthBar or not QuestTogether:CanAccessForeignFrame(healthBar, true) then
		return nil
	end

	local liveFillTexture = Services.Access.CallAccessibleFrameMethod(healthBar, "GetStatusBarTexture")
	if not QuestTogether:CanAccessForeignFrame(liveFillTexture, true) then
		return nil
	end
	return liveFillTexture
end

ApplyQuestIconVisual = function(texture)
	if not texture then
		return
	end

	if texture.SetAtlas and QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS then
		texture:SetAtlas(QuestTogether.NAMEPLATE_QUEST_ICON_ATLAS, true)
		texture:SetTexCoord(0, 1, 0, 1)
	else
		texture:SetTexture(QuestTogether.NAMEPLATE_QUEST_ICON_TEXTURE)
		local coords = QuestTogether.NAMEPLATE_QUEST_ICON_TEX_COORDS
		if coords then
			texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
		else
			texture:SetTexCoord(0, 1, 0, 1)
		end
	end
end

function QuestTogether:ApplyQuestTintToNameplate(unitFrame)
	if not unitFrame then
		return false
	end
	local healthBar = Services.Access.GetAccessibleChildFrame(unitFrame, "healthBar")
	if
		not healthBar
		or not Services.Access.CanMutateFrame(unitFrame)
		or not Services.Access.CanMutateFrame(healthBar)
	then
		return false
	end

	local overlay = EnsureQuestHealthOverlay(unitFrame)
	if not overlay then
		return false
	end

	local color = self:GetNameplateQuestHealthColor()
	local highlightRed = math.min(1, color.r + 0.18)
	local highlightGreen = math.min(1, color.g + 0.18)
	local highlightBlue = math.min(1, color.b + 0.12)
	local anchorTarget = GetQuestHealthOverlayAnchorTarget(unitFrame)
	if not anchorTarget then
		self:RestoreNameplateHealthColor(unitFrame)
		return false
	end
	AnchorQuestHealthFillTexture(overlay.FillTexture, anchorTarget)
	AnchorQuestHealthFillTexture(overlay.Highlight, anchorTarget)

	if overlay.FillTexture then
		if overlay.FillTexture.SetVertexColor and Services.Access.CanMutateFrame(overlay.FillTexture) then
			overlay.FillTexture:SetVertexColor(color.r, color.g, color.b, 1)
		end
		if Services.Access.CanMutateFrame(overlay.FillTexture) then
			self:CancelNameplateVisualCleanup(overlay.FillTexture)
			overlay.FillTexture:Show()
		end
	end
	if overlay.Highlight and Services.Access.CanMutateFrame(overlay.Highlight) then
		overlay.Highlight:SetColorTexture(highlightRed, highlightGreen, highlightBlue, 0.14)
		self:CancelNameplateVisualCleanup(overlay.Highlight)
		overlay.Highlight:Show()
	end

	if healthBar then
		local alpha = Services.Access.SafeUiNumber(Services.Access.CallAccessibleFrameMethod(healthBar, "GetAlpha"), 1)
		if
			overlay.FillTexture
			and overlay.FillTexture.SetAlpha
			and Services.Access.CanMutateFrame(overlay.FillTexture)
		then
			overlay.FillTexture:SetAlpha(alpha)
		end
		if overlay.Highlight and overlay.Highlight.SetAlpha and Services.Access.CanMutateFrame(overlay.Highlight) then
			overlay.Highlight:SetAlpha(alpha)
		end
	end

	return true
end

function QuestTogether:RestoreNameplateHealthColor(unitFrame)
	if not unitFrame then
		return
	end
	if Services.Access.IsFrameForbidden(unitFrame) then
		return
	end

	local overlay = self:GetNameplateStateStore().healthOverlayByUnitFrame[unitFrame]
	if overlay then
		if overlay.FillTexture and overlay.FillTexture.Hide and Services.Access.CanMutateFrame(overlay.FillTexture) then
			overlay.FillTexture:Hide()
		end
		if overlay.Highlight and overlay.Highlight.Hide and Services.Access.CanMutateFrame(overlay.Highlight) then
			overlay.Highlight:Hide()
		end
	end
end

function QuestTogether:RefreshNameplateHealthTint(namePlateFrameBase, isQuestObjective, retryOnFailure)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return
	end

	local unitToken = Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	local shouldTint = self:ShouldApplyQuestHealthTint(unitFrame, isQuestObjective)
	if shouldTint then
		local applied = self:ApplyQuestTintToNameplate(unitFrame)
		if not applied and retryOnFailure ~= false and type(unitToken) == "string" and unitToken ~= "" then
			self:ScheduleNameplateHealthTintRefresh(unitToken, 0.05, true)
		end
	else
		self:RestoreNameplateHealthColor(unitFrame)
	end
end

function QuestTogether:ScheduleNameplateHealthTintRefresh(unitToken, delaySeconds, _preferCachedQuestState)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local function refreshTint()
		local namePlateFrameBase, unitFrame = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
		if not namePlateFrameBase or not unitFrame then
			return
		end

		local liveUnitToken = Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
		if not liveUnitToken then
			self:ForgetResolvedNameplateQuestState(unitToken)
			self:RestoreNameplateHealthColor(unitFrame)
			return
		end

		if liveUnitToken ~= unitToken then
			self:ForgetResolvedNameplateQuestState(unitToken)
		end
		if self:IsNameplateUnitPlayer(liveUnitToken) then
			self:RefreshQTPlayerNameplate(namePlateFrameBase, liveUnitToken, unitFrame)
			return
		end

		local hasResolvedQuestState, isQuestObjective, unitGuid =
			self:TryResolveNameplateQuestObjectiveState(liveUnitToken, unitFrame, false)
		if not hasResolvedQuestState then
			self:ForgetResolvedNameplateQuestState(liveUnitToken)
			self:HideNameplateIcon(namePlateFrameBase)
			-- Health/threat ticks are presentation updates, not a new discovery
			-- lifetime. Empty/nonquest tooltips must not bypass exhausted retries.
			-- Quest changes, target/mouseover and plate additions reset the budget.
			if
				self.ScheduleNameplateTooltipResolution
				and self:GetNameplateTooltipResolveRetryCount(liveUnitToken)
					< Services.Quests.NAMEPLATE_TOOLTIP_RETRY_MAX_ATTEMPTS
			then
				self:ScheduleNameplateTooltipResolution(
					liveUnitToken,
					self:GetNameplateTooltipScanGuid(liveUnitToken, unitFrame),
					0,
					"ScheduleNameplateHealthTintRefresh"
				)
			end
			return
		end

		-- Both visuals follow the same result. Health/threat events may be the
		-- first opportunity to repair a newly visible plate's missing icon.
		self:ApplyResolvedQuestStateToNameplate(
			namePlateFrameBase,
			liveUnitToken,
			unitFrame,
			isQuestObjective,
			false,
			unitGuid
		)
	end

	if self.ScheduleDeferredWork then
		self:ScheduleRuntimeWork(
			"nameplate_tint_refresh",
			unitToken,
			refreshTint,
			{
				delay = delaySeconds,
				owner = self:GetNameplateWorkOwner(unitToken),
				reason = "ScheduleNameplateHealthTintRefresh",
			}
		)
		return
	end

	refreshTint()
end

function QuestTogether:ScheduleNameplateRefresh(unitToken)
	if not self:IsNameplateUnitToken(unitToken) then
		return
	end

	local generations = self:GetNameplateStateStore().identityGenerationByUnitToken
	local generation = generations[unitToken]
	self:GetNameplateStateStore().refreshPendingByUnitToken[unitToken] = true
	return self:ScheduleRuntimeWork(
		"nameplate_refresh",
		unitToken,
		function()
			if
				self:GetNameplateStateStore().identityGenerationByUnitToken ~= generations
				or generations[unitToken] ~= generation
			then
				return
			end
			self:GetNameplateStateStore().refreshPendingByUnitToken[unitToken] = nil
			local plate = self:GetAccessibleNameplateFrameForUnit(unitToken, true)
			if not plate then
				self:MaybeScheduleNameplateTooltipRetry(unitToken, "ScheduleNameplateRefresh")
				return
			end
			self:RefreshNameplateIcon(plate)
		end,
		{
			mode = "nextFrame",
			coalesce = true,
			owner = self:GetNameplateWorkOwner(unitToken),
			reason = "ScheduleNameplateRefresh",
		}
	)
end

function QuestTogether:HideQTPlayerIcon(icon)
	if self.qtPlayerIconStateByFrame then
		self.qtPlayerIconStateByFrame[icon] = nil
	end
	if Services.Access.CanMutateFrame(icon) then
		self:SetQTPlayerIconLookingForPartners(icon, false)
		icon:Hide()
		self:CancelNameplateVisualCleanup(icon)
	else
		self:QueueNameplateVisualCleanup(icon, "icon")
	end
end

function QuestTogether:RefreshQTPlayerPlatePresence()
	for icon, info in pairs(self.qtPlayerIconStateByFrame or {}) do
		if not self:ShouldShowQTPlayerLogoForName(info.name) then
			self:HideQTPlayerIcon(icon)
		end
	end
	if self.isEnabled and self.nameplateRegisteredEvents and self.nameplateRegisteredEvents.NAME_PLATE_UNIT_ADDED then
		self:ScheduleNameplatePresentationRefresh("QT player presence", 0)
	end
end

function QuestTogether:RefreshQTPlayerPartnerIndicators()
	if not self.isEnabled then
		return false
	end
	local scheduled = false
	for _, info in pairs(self.qtPlayerIconStateByFrame or {}) do
		local looking = self:IsPlayerLookingForQuestPartners(info.name) == true
		if
			(info.partnerIndicatorPending == true or (info.lookingForPartners == true) ~= looking)
			and self:IsNameplateUnitToken(info.unitToken)
			and not self:IsRuntimeWorkPending("nameplate_refresh", info.unitToken)
		then
			self:ScheduleNameplateRefresh(info.unitToken)
			scheduled = true
		end
	end
	return scheduled
end

function QuestTogether:GetFriendlyPlayerNameplateVisibility()
	local getter = self.API and self.API.GetCVar
	if not self:CanAccessValue(getter) or type(getter) ~= "function" then
		return nil
	end
	-- Retail/Forever use the player-specific CVar. An explicit modern value
	-- takes precedence; only an absent key permits the older client fallback.
	for _, key in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowFriends" }) do
		local ok, value, readable = pcall(getter, key)
		if
			not ok
			or not self:CanAccessValue(value)
			or not self:CanAccessValue(readable)
			or (readable ~= nil and readable ~= true)
		then
			return nil, key
		end
		if value ~= nil then
			if value == "1" then
				return true, key
			end
			if value == "0" then
				return false, key
			end
			return nil, key
		end
	end
	return nil
end

function QuestTogether:RefreshQTPlayerNameplate(plate, unitToken, unitFrame)
	local icon = self:GetNameplateStateStore().iconByUnitFrame[unitFrame]
	self:ForgetResolvedNameplateQuestState(unitToken)
	self:ClearNameplateTooltipResolveRetryCount(unitToken)
	-- Only restore an old quest overlay; the player path never creates a tint.
	self:RestoreNameplateHealthColor(unitFrame)
	-- Direct plate-added and presentation calls do not pass through the work
	-- scheduler. Apply its policy before creating or laying out a player icon;
	-- safe stale-visual cleanup remains allowed while presentation is deferred.
	if self:IsWorkBlocked("nameplate_refresh") then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		if self.isEnabled then
			self:ScheduleNameplateRefresh(unitToken)
		end
		return false
	end
	local show, name, guid = false, nil, nil
	if
		self.isEnabled
		and self:GetOption("nameplatePlayerIconEnabled") == true
		and not self:IsNameplateAugmentationBlockedInCurrentContext()
		and self:CanAccessForeignFrame(plate, true)
		and self:CanAccessForeignFrame(unitFrame)
		and self:GetFriendlyPlayerNameplateVisibility() == true
	then
		show, name = self:IsFriendlyQTPlayerUnit(unitToken)
		if show then
			guid = self:GetNameplateUnitGuid(unitToken)
			show = Services.Access.IsNonEmptyString(guid)
		end
	end
	if not show then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		return false
	end
	if not Services.Access.CanMutateFrame(unitFrame) or (icon and not Services.Access.CanMutateFrame(icon)) then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		return false
	end
	local readyIcon = EnsureQuestIcon(unitFrame, "player")
	if not readyIcon then
		if icon then
			self:HideQTPlayerIcon(icon)
		end
		return false
	end
	icon = readyIcon
	local lookingForPartners = self:IsPlayerLookingForQuestPartners(name) == true
	self.qtPlayerIconStateByFrame = self.qtPlayerIconStateByFrame or setmetatable({}, { __mode = "k" })
	local info = { name = name, unitToken = unitToken, guid = guid, lookingForPartners = lookingForPartners }
	if not self:SetQTPlayerIconLookingForPartners(icon, lookingForPartners) then
		self:HideQTPlayerIcon(icon)
		-- A quarantined child can recover while its plate stays visible. Keep
		-- only owned identity/retry state so the normal presence prune retries
		-- presentation; removal and disable still discard this record.
		info.lookingForPartners, info.partnerIndicatorPending = false, true
		self.qtPlayerIconStateByFrame[icon] = info
		return false
	end
	self.qtPlayerIconStateByFrame[icon] = info
	self:CancelNameplateVisualCleanup(icon)
	icon:Show()
	return true
end

function QuestTogether:RefreshNameplateIcon(namePlateFrameBase)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return
	end
	local unitToken = Services.Access.ResolveNameplateUnitToken(namePlateFrameBase, unitFrame)
	if self:IsNameplateUnitToken(unitToken) and self:IsNameplateUnitPlayer(unitToken) then
		self:RefreshQTPlayerNameplate(namePlateFrameBase, unitToken, unitFrame)
		return
	end
	-- Presentation is cache-only. Discovery uses a separate next-frame worker
	-- fenced by plate identity, never by another presentation refresh.
	if DeferBlockedQuestPlatePresentation(self, namePlateFrameBase, unitToken) then
		return
	end
	local existing = self:GetNameplateStateStore().iconByUnitFrame[unitFrame]
	if existing and self.qtPlayerIconStateByFrame then
		self.qtPlayerIconStateByFrame[existing] = nil
	end
	local hasResolvedQuestState, isQuestObjective, resolvedUnitGuid =
		self:TryResolveNameplateQuestObjectiveState(unitToken, unitFrame, false)
	if not hasResolvedQuestState then
		self:ForgetResolvedNameplateQuestState(unitToken)
		self:HideNameplateIcon(namePlateFrameBase)
		if self.ScheduleNameplateTooltipResolution then
			self:ScheduleNameplateTooltipResolution(
				unitToken,
				self:GetNameplateTooltipScanGuid(unitToken, unitFrame),
				0,
				"RefreshNameplateIcon"
			)
		end
		return
	end
	if isQuestObjective then
		self:ClearNameplateTooltipResolveRetryCount(unitToken)
	else
		-- Keep the negative fallback, but let fresh tooltip evidence reveal a
		-- newly relevant quest or unfinished party objective. Retries stay bounded.
		self:MaybeScheduleNameplateTooltipRetry(unitToken, "RefreshNameplateIcon", resolvedUnitGuid)
	end

	self:ApplyResolvedQuestStateToNameplate(
		namePlateFrameBase,
		unitToken,
		unitFrame,
		isQuestObjective,
		true,
		resolvedUnitGuid
	)
end

function QuestTogether:HideNameplateIcon(namePlateFrameBase)
	if not self:CanAccessForeignFrame(namePlateFrameBase) then
		return
	end
	local unitFrame, memberReadable = self:GetAccessibleFrameMember(namePlateFrameBase, "UnitFrame")
	if not memberReadable or not unitFrame or not self:CanAccessForeignFrame(unitFrame) then
		return
	end

	local icon = self:GetNameplateStateStore().iconByUnitFrame[unitFrame]
	if icon and Services.Access.CanMutateFrame(icon) then
		icon:Hide()
	end
	self:RestoreNameplateHealthColor(unitFrame)
end

function QuestTogether:HideTapDeniedNameplateVisuals(unitToken)
	if self:IsNameplateUnitToken(unitToken) and self:IsNameplateUnitPlayer(unitToken) then
		return
	end
	if not self:IsNameplateUnitToken(unitToken) or not self:IsNameplateUnitTapDenied(unitToken) then
		return
	end

	-- Tap ownership can change after quest detection and while combat defers
	-- normal plate refreshes. Hide our existing visuals without a tooltip scan
	-- or layout work; HideNameplateIcon guards forbidden/protected objects.
	local namePlateFrameBase = self:GetAccessibleNameplateFrameForUnit(unitToken, false)
	if namePlateFrameBase then
		self:HideNameplateIcon(namePlateFrameBase)
	end
end

function QuestTogether:RefreshNameplateForUnitAlias(unitAlias)
	local unitGuid = self:GetNameplateUnitGuid(unitAlias)
	if not Services.Access.IsNonEmptyString(unitGuid) then
		return
	end

	self:ForEachVisibleNamePlate(function(frame)
		local unitFrame = Services.Access.GetAccessibleChildFrame(frame, "UnitFrame")
		local unitToken = Services.Access.ResolveNameplateUnitToken(frame, unitFrame)
		if self:IsNameplateUnitToken(unitToken) and self:GetNameplateUnitGuid(unitToken) == unitGuid then
			self:ClearNameplateTooltipResolveRetryCount(unitToken)
			self:ScheduleNameplateRefresh(unitToken)
		end
	end)
end

Services.Decorations = {
	ApplyQuestIconVisual = ApplyQuestIconVisual,
}
