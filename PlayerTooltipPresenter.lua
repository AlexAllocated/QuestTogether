local QuestTogether = _G.QuestTogether
local L = QuestTogether.Translate
local function Number(addon, value)
	return addon:SafeToNumber(value)
end
local function Positive(addon, value)
	value = Number(addon, value)
	return value and value > 0 and value
end
local function Guard(addon, region)
	return addon:CanMutateOwnedUI(region)
end
local function Call(addon, region, method, ...)
	return addon:CallOwnedUI(region, method, ...)
end
function QuestTogether:GetPlayerTooltipPresentationParent()
	return self:GetLocationPinTooltipParent()
end
function QuestTogether:CreatePlayerTooltipPresentationFrame(...)
	return self:CreateLocationPinFrame(...)
end
local function New(addon, kind, parent)
	return addon:CreateOwnedUIFrame(addon.CreatePlayerTooltipPresentationFrame, kind, parent)
end
local function Native(addon, fn, ...)
	if addon:IsRuntimeRestricted() or not addon:CanAccessValue(fn) or type(fn) ~= "function" then
		return
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
end
local function Method(addon, frame, method, ...)
	return Native(addon, addon:GetAccessibleFrameMember(frame, method), frame, ...)
end
function QuestTogether:HidePlayerTooltipPresentation(state)
	self:ClearPlayerDetailsInterest(state)
	state.hovered = nil
	self:HideOwnedUI(state.tooltip)
	if state.onHoverChanged then
		state.onHoverChanged()
	end
end
local function HideTooltip(addon, state)
	addon:HidePlayerTooltipPresentation(state)
end
local function Color(addon, classFile)
	local color = addon:SafeTrimString(addon:GetClassColorCode(classFile), "")
	local r, g, b = color:match("^|c%x%x(%x%x)(%x%x)(%x%x)$")
	if r then
		return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
	end
	return 1, 1, 1
end

local PARTY_MEDIA = "Interface\\AddOns\\QuestTogether\\Media\\"
local function PartyTexture(addon, frame, name, width, height, point, relative, relativePoint, x, y)
	local texture = Call(addon, frame, "CreateTexture", nil, "OVERLAY")
	Call(addon, texture, "SetTexture", PARTY_MEDIA .. name)
	Call(addon, texture, "SetSize", width, height)
	Call(addon, texture, "SetPoint", point, relative, relativePoint, x, y)
	Call(addon, texture, "Hide")
	return texture
end

local function Text(addon, value, fallback)
	local text = addon:SafeTrimString(value, "")
	if text == "" then
		text = fallback or L("Unknown")
	end
	return text:gsub("|", "||")
end

function QuestTogether:GetChatLogQuestTooltipRow(questID, fallbackTitle)
	local title = self:GetQuestDisplayTitle(questID, fallbackTitle)
	local lines = {
		L("Your quest status") .. ": " .. L(self:GetQuestStatusLabel(questID)),
		L("Shareable") .. ": " .. L(self:GetQuestShareableStatusLabel(questID)),
		"|cff909090" .. L("Quest ID") .. ": " .. tostring(questID) .. "|r",
	}
	-- Read only QT's own current objective text, never infer the sender's
	-- progress from our quest stage. A missing local quest has no objectives.
	local tracker = self.db and self.db.global and self:GetPlayerTracker()
	local quest = tracker and tracker[questID]
	local objectives = quest and quest.objectives
	if type(objectives) == "table" then
		for index = 1, 100 do
			local objective = self:SafeTrimString(objectives[index], "")
			if objective ~= "" then
				lines[#lines + 1] = Text(self, objective)
			end
		end
	end
	return { questID = questID, name = title, questText = table.concat(lines, "\n") }
end

local function TooltipTextWidth(addon, label, maxWidth)
	-- Measure addon-owned font strings unconstrained, then apply the final
	-- wrapping width after all title, body and party content has been measured.
	Call(addon, label, "SetWidth", 0)
	local width = Number(addon, Call(addon, label, "GetStringWidth"))
	maxWidth = maxWidth or 272
	return width and width >= 0 and math.min(maxWidth, math.ceil(width)) or maxWidth
end

local GROUP_INSET, GROUP_ICON_SPACE, GROUP_PADDING, GROUP_GAP = 6, 44, 4, 8
local GROUP_COUNT_WIDTH, GROUP_COUNT_GAP = 20, 3
local GROUP_CORNER_UV = { { 0, 0.5, 0, 0.5 }, { 0.5, 1, 0, 0.5 }, { 0, 0.5, 0.5, 1 }, { 0.5, 1, 0.5, 1 } }

function QuestTogether:LayoutPlayerTooltipPartyGroup(state, index, anchor, top, width, height, key, size, first, last)
	local addon = self
	state.partyGroups = state.partyGroups or {}
	local group = state.partyGroups[index]
	if not group then
		group = { frame = New(addon, "Frame", state.tooltip), corners = {}, edges = {} }
		state.partyGroups[index] = group
		Call(addon, group.frame, "EnableMouse", false)
		for corner, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
			local texture = Call(addon, group.frame, "CreateTexture", nil, "BORDER")
			group.corners[corner] = texture
			Call(addon, texture, "SetTexture", PARTY_MEDIA .. "PanelCornerBorder")
			Call(addon, texture, "SetTexCoord", unpack(GROUP_CORNER_UV[corner]))
			Call(addon, texture, "SetVertexColor", 1, 1, 1, 1)
			Call(addon, texture, "SetSize", 6, 6)
			Call(addon, texture, "SetPoint", point, group.frame, point, 0, 0)
		end
		for edge = 1, 4 do
			local texture = Call(addon, group.frame, "CreateTexture", nil, "BORDER")
			group.edges[edge] = texture
			Call(addon, texture, "SetColorTexture", 1, 1, 1, 1)
		end
		Call(addon, group.edges[1], "SetPoint", "TOPLEFT", group.frame, "TOPLEFT", 6, 0)
		Call(addon, group.edges[2], "SetPoint", "BOTTOMLEFT", group.frame, "BOTTOMLEFT", 6, 0)
		Call(addon, group.edges[3], "SetPoint", "TOPLEFT", group.frame, "TOPLEFT", 0, -6)
		Call(addon, group.edges[4], "SetPoint", "TOPRIGHT", group.frame, "TOPRIGHT", 0, -6)
		group.icon = PartyTexture(addon, group.frame, "PartyBadge", 16, 16, "RIGHT", group.frame, "RIGHT", -6 - GROUP_COUNT_WIDTH - GROUP_COUNT_GAP, 0)
		Call(addon, group.icon, "SetVertexColor", 1, 1, 1, 1)
		Call(addon, group.icon, "Show")
		group.count = Call(addon, group.frame, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
		Call(addon, group.count, "SetPoint", "RIGHT", group.frame, "RIGHT", -6, 0)
		Call(addon, group.count, "SetSize", GROUP_COUNT_WIDTH, 16)
		Call(addon, group.count, "SetJustifyH", "LEFT")
		Call(addon, group.count, "SetJustifyV", "MIDDLE")
		Call(addon, group.count, "SetWordWrap", false)
		Call(addon, group.count, "SetTextColor", 1, 1, 1, 1)
	end
	group.active, group.key, group.first, group.last = true, key, first, last
	group.partySize = size
	Call(addon, group.count, "SetText", size and tostring(size) or "")
	Call(addon, group.frame, "ClearAllPoints")
	Call(addon, group.frame, "SetPoint", "TOPLEFT", anchor, "BOTTOMLEFT", 0, -top)
	Call(addon, group.frame, "SetSize", width, height)
	for edge, texture in ipairs(group.edges) do
		Call(addon, texture, "SetSize", edge <= 2 and width - 12 or 1, edge <= 2 and 1 or height - 12)
	end
	Call(addon, group.frame, "Show")
end

local function LayoutPartyTooltipRows(addon, state, width, hasIntro, bodyGap)
	local height, groups, index = 0, 0, 1
	local anchor = hasIntro and state.tooltipIntro or state.tooltipTitle
	local topGap = hasIntro and 8 or bodyGap
	local rows = state.partyRows or {}
	while rows[index] and rows[index].active do
		local first, last, key = index, index, rows[index].partyKey
		if key then
			while rows[last + 1] and rows[last + 1].active and rows[last + 1].partyKey == key do last = last + 1 end
			if height > 0 then height = height + GROUP_GAP end
		end
		local groupTop = height
		if key then height = height + GROUP_PADDING end
		for row = first, last do
			local item = rows[row]
			local inset = key and GROUP_INSET or 0
			Call(addon, item.label, "SetWidth", width - 38 - inset * 2 - (key and GROUP_ICON_SPACE or 0))
			local lineHeight = math.max(key and 16 or 14, (Positive(addon, Call(addon, item.label, "GetStringHeight")) or 12) + 2)
			Call(addon, item.frame, "SetSize", width - inset * 2, lineHeight)
			Call(addon, item.frame, "ClearAllPoints")
			Call(addon, item.frame, "SetPoint", "TOPLEFT", anchor, "BOTTOMLEFT", inset, -topGap - height)
			height = height + lineHeight
		end
		if key then
			height, groups = height + GROUP_PADDING, groups + 1
			addon:LayoutPlayerTooltipPartyGroup(state, groups, anchor, topGap + groupTop, width, height - groupTop, key, rows[first].partySize, first, last)
			if rows[last + 1] and rows[last + 1].active and not rows[last + 1].partyKey then height = height + GROUP_GAP end
		end
		index = last + 1
	end
	for unused = groups + 1, #(state.partyGroups or {}) do
		local group = state.partyGroups[unused]
		group.active, group.key, group.first, group.last = false, nil, nil, nil
		group.partySize = nil
		Call(addon, group.count, "SetText", "")
		Call(addon, group.frame, "Hide")
	end
	return height > 0 and height + (hasIntro and 8 or 0) or 0
end

local function PartyTooltipMembers(addon, info)
	local members, seen, known = {}, {}, 0
	local function Add(member)
		if not member.name or seen[member.name] then
			return
		end
		seen[member.name], known = true, known + 1
		if not addon:IsIgnoredPlayerName(member.name) then
			members[#members + 1] = member
		end
	end
	if info then
		local source = info.members or info.knownMembers or {}
		for _, member in ipairs(source) do
			if member.name == info.leader then Add(member) end
		end
		if info.size and info.size <= 5 then
			for _, member in ipairs(source) do Add(member) end
		end
	end
	return members, known
end

-- Both party rosters and cluster summaries use the same presentation-only
-- member model. Party membership and leadership are supplied by the caller;
-- authentication and private location status come from their owned queries.
function QuestTogether:BuildPlayerTooltipMember(member, options)
	options = options or {}
	local name = self:SafeTrimString(member.name, "")
	if name == "" or self:IsIgnoredPlayerName(name) then return nil end
	local r, g, b = Color(self, member.classFile)
	local leader = options.leader == true
	local developer = self:IsVerifiedDeveloper(name) == true
	local hiddenLocation = self:IsPlayerLocationHiddenForDeveloper(name) == true
	local looking = self:IsPlayerLookingForQuestPartners(name)
		or (member.developerOnly and member.lookingForQuestPartners == true)
	local displayName = options.shortName and self:GetShortDisplayName(name) or name
	local label = self:GetClassColorCode(member.classFile) .. Text(self, displayName) .. "|r"
	if leader then label = label .. " — " .. L("Leader") end
	return {
		name = name,
		leader = leader,
		color = { r, g, b },
		usesQT = self:HasQTPlayerDisplayEvidence(name),
		icon = looking and PARTY_MEDIA .. "QuestTogetherPartnerIcon" or self.NAMEPLATE_PLAYER_ICON_TEXTURE,
		label = label,
		developer = developer,
		hiddenLocation = hiddenLocation,
	}
end

function QuestTogether:BuildPlayerTooltipModel(row)
	local addon = self
	if row.tipAction then
		local info = self:GetHintActionInfo(row.tipAction)
		return { title = info and info.label or "", text = info and info.tooltip or "", color = { 1, 0.82, 0 }, members = {} }
	end
	if not row.questID then
		row = addon:GetPlayerDetailsTooltipRow(row)
	end
	local classColor = addon:GetClassColorCode(row.classFile)
	local r, g, b = Color(addon, row.classFile)
	if row.questID then
		classColor, r, g, b = "|cffffd200", 1, 0.82, 0
	end
	local factionTexture = row.faction == "Alliance" and "Interface\\TargetingFrame\\UI-PVP-Alliance"
		or row.faction == "Horde" and "Interface\\TargetingFrame\\UI-PVP-Horde"
	local text, introText, lastUpdate
	local party = not row.questID and addon:GetPlayerPartyVisualInfo(row.name) or nil
	local partyMembers, knownPartyMembers = PartyTooltipMembers(addon, party)
	if row.questID then
		text = row.questText
	else
		local raceName, className = addon:GetPlayerTooltipIdentity(row)
		introText = string.format(
			L("Level %s %s %s"),
			Number(addon, row.level) and tostring(row.level) or L("Unknown"),
			Text(addon, raceName),
			classColor .. Text(addon, className, Text(addon, row.classFile)) .. "|r"
		)
		text = ""
		if addon:GetPlayerPhaseStatus(row.name) == "different" then
			text = L("Likely different layer (experimental)")
				.. "\n"
				.. L("Nearby NPC observations differ. This is an estimate, not a confirmed phase.")
		end
		if addon:SupportsWarMode() == true and type(row.warMode) == "boolean" then
			text = text .. L("\nWar Mode: ") .. (row.warMode and L("On") or L("Off"))
		end
		if addon:IsPlayerLookingForQuestPartners(row.name) or (row.developerOnly and row.lookingForQuestPartners) then
			text = text .. "\n" .. L("\n|cff40ff40Looking for Questing Partners|r"):gsub("|cff40ff40", "|cffffd200")
			local questID, sourceTitle = addon:GetPlayerPartnerQuestID(row.name)
			if questID then
				text = text
					.. "|cffffd200"
					.. L("\nTracked quest: ")
					.. Text(addon, addon:GetLocalizedQuestTitle(questID) or sourceTitle or addon:GetQuestTitle(questID))
					.. "|r"
			end
		end
		local now = addon.API and addon.API.GetTime and Number(addon, addon.API.GetTime())
		local receivedAt = Number(addon, row.sampledAt or row.receivedAt)
		if now and receivedAt and now >= receivedAt + 30 then
			lastUpdate = L("\nLast update: "):gsub("^\n+", "") .. math.floor(now - receivedAt) .. L(" seconds ago")
		end
		local partySize = party and party.size
		local partyText = partySize == 0 and L("Solo")
			or partySize and string.format(L("Party of %d"), partySize)
			or party and party.grouped and L("In a party")
			or L("Party status unknown")
		local version = addon:GetPlayerAddonVersion(row.name)
		local note = addon:GetPlayerNoteTooltipText(row.name)
		if note then text = text .. "\n\n" .. note end
		text = text:gsub("^\n+", "")
		text = text
			.. (text ~= "" and "\n\n" or "")
			.. "|cff909090"
			.. (lastUpdate and (lastUpdate .. "\n") or "")
			.. (version and ("v" .. Text(addon, version)) or L("Unknown"))
			.. "|r"
		if addon:IsVerifiedDeveloper(row.name) then
			introText = introText .. "\n|cffffd200" .. L("QuestTogether developer") .. "|r"
		end
		if addon:IsPlayerLocationHiddenForDeveloper(row.name) then
			introText = introText .. "\n|cffff8080" .. L("Location sharing is off") .. "|r"
		end
		introText = introText .. "\n\n" .. partyText
		if party and party.key and party.size <= 5 and not party.members and knownPartyMembers < party.size then
			introText = introText .. "\n|cff909090" .. L("Loading party members…") .. "|r"
		end
	end
	local members = {}
	for _, member in ipairs(partyMembers) do
		local model = addon:BuildPlayerTooltipMember(member, { leader = member.name == party.leader })
		if model then members[#members + 1] = model end
	end
	return {
		title = classColor .. Text(addon, row.name) .. "|r",
		color = { r, g, b },
		factionTexture = factionTexture,
		text = text,
		introText = introText,
		members = members,
	}
end

local function PartyTooltipRows(addon, state, members)
	state.partyRows = state.partyRows or {}
	local width = 0
	for index, member in ipairs(members) do
		local item = state.partyRows[index]
		if not item then
			item = { frame = New(addon, "Frame", state.tooltip) }
			state.partyRows[index] = item
			Call(addon, item.frame, "SetSize", 272, 14)
			item.qtIcon = Call(addon, item.frame, "CreateTexture", nil, "ARTWORK")
			Call(addon, item.qtIcon, "SetSize", 14, 14)
			Call(addon, item.qtIcon, "SetPoint", "LEFT", 0, 0)
			item.dot = Call(addon, item.frame, "CreateTexture", nil, "ARTWORK")
			Call(addon, item.dot, "SetSize", 10, 10)
			Call(addon, item.dot, "SetPoint", "LEFT", 20, 0)
			local mask = Call(addon, item.frame, "CreateMaskTexture")
			Call(addon, mask, "SetAllPoints", item.dot)
			Call(
				addon,
				mask,
				"SetTexture",
				"Interface\\CharacterFrame\\TempPortraitAlphaMask",
				"CLAMPTOBLACKADDITIVE",
				"CLAMPTOBLACKADDITIVE"
			)
			Call(addon, item.dot, "AddMaskTexture", mask)
			-- Keep the gear separate from the masked class dot so its teeth retain
			-- their shape. All indicators are reused and reset for each occupant.
			item.developerIcon = PartyTexture(addon, item.frame, "DeveloperGear", 14, 14, "CENTER", item.dot, "CENTER", 0, 0)
			item.hiddenGlow = addon:CreatePlayerMarkerGlow(item.frame, item.dot)
			item.crown = PartyTexture(addon, item.frame, "PartyLeader", 12, 9, "BOTTOM", item.dot, "TOP", 0, -2)
			item.label = Call(addon, item.frame, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
			Call(addon, item.label, "SetPoint", "TOPLEFT", 38, -1)
			Call(addon, item.label, "SetWidth", 234)
			Call(addon, item.label, "SetJustifyH", "LEFT")
			Call(addon, item.label, "SetWordWrap", true)
		end
		local r, g, b = unpack(member.color)
		Call(addon, item.qtIcon, "SetTexture", member.icon)
		Call(addon, item.qtIcon, member.usesQT and "Show" or "Hide")
		Call(addon, item.dot, "SetColorTexture", r, g, b, 1)
		Call(addon, item.dot, member.developer and "Hide" or "Show")
		Call(addon, item.developerIcon, "SetVertexColor", r, g, b, 1)
		Call(addon, item.developerIcon, member.developer and "Show" or "Hide")
		addon:SetPlayerMarkerGlow(item.hiddenGlow, member.hiddenLocation and "hidden" or nil, member.developer and 20 or 16)
		local leader = member.leader
		Call(addon, item.label, "SetText", member.label)
		item.partyKey = member.partyKey
		item.partySize = member.partySize
		width = math.max(width, TooltipTextWidth(addon, item.label) + 38 + (member.partyKey and GROUP_INSET * 2 + GROUP_ICON_SPACE or 0))
		item.active = true
		Call(addon, item.crown, leader and "Show" or "Hide")
		Call(addon, item.frame, "Show")
	end
	for i = #members + 1, #state.partyRows do
		state.partyRows[i].active = false
		state.partyRows[i].partyKey = nil
		state.partyRows[i].partySize = nil
		Call(addon, state.partyRows[i].frame, "Hide")
	end
	return width
end

-- Legend rows share the tooltip's lifecycle and layout. The caller draws its
-- owned samples; this presenter only owns spacing, wrapping and row reuse.
local function LayoutTooltipLegend(addon, state, model, width, anchor, top)
	if not model.legend and not state.legendRows then return 0 end
	local entries, height = model.legend or {}, 0
	state.legendRows = state.legendRows or {}
	for index, entry in ipairs(entries) do
		local item = state.legendRows[index]
		if not item then
			item = { frame = New(addon, "Frame", state.tooltip) }
			state.legendRows[index] = item
			Call(addon, item.frame, "EnableMouse", false)
			item.sampleFrame = New(addon, "Frame", item.frame)
			Call(addon, item.sampleFrame, "EnableMouse", false)
			Call(addon, item.sampleFrame, "SetSize", 58, 26)
			Call(addon, item.sampleFrame, "SetPoint", "LEFT", item.frame, "LEFT", 0, 0)
			item.label = Call(addon, item.frame, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
			Call(addon, item.label, "SetPoint", "LEFT", item.frame, "LEFT", 68, 0)
			Call(addon, item.label, "SetJustifyH", "LEFT")
			Call(addon, item.label, "SetWordWrap", true)
		end
		Call(addon, item.label, "SetWidth", width - 68)
		Call(addon, item.label, "SetText", entry.label)
		local rowHeight = math.max(28, (Positive(addon, Call(addon, item.label, "GetStringHeight")) or 12) + 8)
		height = height + (entry.gapBefore or 0)
		Call(addon, item.frame, "ClearAllPoints")
		Call(addon, item.frame, "SetPoint", "TOPLEFT", anchor, "BOTTOMLEFT", 0, -top - height)
		Call(addon, item.frame, "SetSize", width, rowHeight)
		model.drawLegendSample(addon, item, entry)
		Call(addon, item.frame, "Show")
		height = height + rowHeight
	end
	for index = #entries + 1, #state.legendRows do Call(addon, state.legendRows[index].frame, "Hide") end
	return height
end

function QuestTogether:RenderPlayerTooltip(state, anchor, model)
	local addon, pin = self, anchor
	local parent = addon:GetPlayerTooltipPresentationParent()
	if not addon:CanAccessForeignFrame(parent, true) or not Guard(addon, pin.frame) then
		return
	end
	local tooltip = state.tooltip
	if not tooltip then
		tooltip = New(addon, "Frame", parent)
		Call(addon, tooltip, "Hide")
		state.tooltip = tooltip
		Call(addon, tooltip, "SetFrameStrata", "TOOLTIP")
		Call(addon, tooltip, "SetClampedToScreen", true)
		local background = Call(addon, tooltip, "CreateTexture", nil, "BACKGROUND")
		Call(addon, background, "SetAllPoints")
		Call(addon, background, "SetColorTexture", 0.03, 0.03, 0.04, 0.97)
		state.tooltipTitle = Call(addon, tooltip, "CreateFontString", nil, "OVERLAY", "GameFontNormalLarge")
		Call(addon, state.tooltipTitle, "SetPoint", "TOPLEFT", 14, -12)
		Call(addon, state.tooltipTitle, "SetWidth", 272)
		Call(addon, state.tooltipTitle, "SetJustifyH", "LEFT")
		Call(addon, state.tooltipTitle, "SetWordWrap", true)
		local divider = Call(addon, tooltip, "CreateTexture", nil, "BORDER")
		state.tooltipDivider = divider
		Call(addon, divider, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -8)
		Call(addon, divider, "SetSize", 272, 1)
		state.tooltipFaction = Call(addon, tooltip, "CreateTexture", nil, "ARTWORK")
		-- The native crest artwork sits above its texture's center. Align the
		-- visible badge with the name, including when the name wraps.
		Call(addon, state.tooltipFaction, "SetPoint", "LEFT", state.tooltipTitle, "RIGHT", 8, -7)
		Call(addon, state.tooltipFaction, "SetSize", 36, 36)
		Call(addon, state.tooltipFaction, "SetAlpha", 0.65)
		state.tooltipIntro = Call(addon, tooltip, "CreateFontString", nil, "OVERLAY", "GameFontHighlight")
		Call(addon, state.tooltipIntro, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -18)
		Call(addon, state.tooltipIntro, "SetWidth", 272)
		Call(addon, state.tooltipIntro, "SetJustifyH", "LEFT")
		Call(addon, state.tooltipIntro, "SetWordWrap", true)
		Call(addon, state.tooltipIntro, "SetSpacing", 3)
		state.tooltipLabel = Call(addon, tooltip, "CreateFontString", nil, "OVERLAY", "GameFontHighlight")
		Call(addon, state.tooltipLabel, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -18)
		Call(addon, state.tooltipLabel, "SetWidth", 272)
		Call(addon, state.tooltipLabel, "SetJustifyH", "LEFT")
		Call(addon, state.tooltipLabel, "SetWordWrap", true)
		Call(addon, state.tooltipLabel, "SetSpacing", 3)
	end
	local r, g, b = unpack(model.color)
	local factionTexture = model.factionTexture
	Call(addon, state.tooltipDivider, "SetColorTexture", r, g, b, 0.6)
	if factionTexture then
		Call(addon, state.tooltipFaction, "SetTexture", factionTexture)
		Call(addon, state.tooltipFaction, "Show")
	else
		Call(addon, state.tooltipFaction, "Hide")
	end
	Call(addon, state.tooltipTitle, "SetText", model.title)
	local text, introText = model.text, model.introText
	Call(addon, state.tooltipIntro, "SetText", introText or "")
	Call(addon, state.tooltipLabel, "SetText", text)
	local maxWidth = math.max(160, math.min(360, Number(addon, model.maxWidth) or 272))
	local contentWidth = math.min(
		maxWidth,
		math.max(
			model.legend and maxWidth or 160,
			TooltipTextWidth(addon, state.tooltipTitle, maxWidth) + (factionTexture and 44 or 0),
			TooltipTextWidth(addon, state.tooltipIntro, maxWidth),
			TooltipTextWidth(addon, state.tooltipLabel, maxWidth),
			PartyTooltipRows(addon, state, model.members)
		)
	)
	Call(addon, state.tooltipTitle, "SetWidth", contentWidth - (factionTexture and 44 or 0))
	Call(addon, state.tooltipIntro, "SetWidth", contentWidth)
	Call(addon, state.tooltipLabel, "SetWidth", contentWidth)
	local titleHeight = Positive(addon, Call(addon, state.tooltipTitle, "GetStringHeight"))
	if not titleHeight then
		HideTooltip(addon, state)
		return
	end
	local bodyGap = math.max(16, factionTexture and (30 - titleHeight) or 0)
	Call(addon, state.tooltipDivider, "ClearAllPoints")
	Call(addon, state.tooltipDivider, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -6)
	Call(addon, state.tooltipDivider, "SetWidth", contentWidth)
	Call(addon, state.tooltipIntro, "ClearAllPoints")
	Call(addon, state.tooltipIntro, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -bodyGap)
	local introHeight = 0
	if introText then
		Call(addon, state.tooltipIntro, "SetText", introText)
		introHeight = Positive(addon, Call(addon, state.tooltipIntro, "GetStringHeight"))
		if not introHeight then
			HideTooltip(addon, state)
			return
		end
		Call(addon, state.tooltipIntro, "Show")
	else
		Call(addon, state.tooltipIntro, "Hide")
	end
	local partyHeight = LayoutPartyTooltipRows(addon, state, contentWidth, introText ~= nil, bodyGap)
	local legendHeight = LayoutTooltipLegend(addon, state, model, contentWidth,
		introText and state.tooltipIntro or state.tooltipTitle, (introText and 8 or bodyGap) + partyHeight)
	if legendHeight > 0 then partyHeight = partyHeight + legendHeight + (introText and 8 or 0) end
	Call(addon, state.tooltipLabel, "ClearAllPoints")
	if introText then
		Call(addon, state.tooltipLabel, "SetPoint", "TOPLEFT", state.tooltipIntro, "BOTTOMLEFT", 0, -partyHeight - 14)
	elseif partyHeight > 0 then
		Call(addon, state.tooltipLabel, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -bodyGap - partyHeight - 14)
	else
		Call(addon, state.tooltipLabel, "SetPoint", "TOPLEFT", state.tooltipTitle, "BOTTOMLEFT", 0, -18)
	end
	Call(addon, state.tooltipLabel, "SetText", text)
	local height = Positive(addon, Call(addon, state.tooltipLabel, "GetStringHeight"))
	if not height then
		HideTooltip(addon, state)
		return
	end
	Call(
		addon,
		tooltip,
		"SetSize",
		contentWidth + 28,
		titleHeight + height + 28 + bodyGap + introHeight + partyHeight + ((introText or partyHeight > 0) and 14 or 0)
	)
	Call(addon, tooltip, "ClearAllPoints")
	if pin.chatLink then
		local x, y = addon:GetChatLogTooltipCursorPosition(parent)
		if not x or not y then
			HideTooltip(addon, state)
			return
		end
		Call(addon, tooltip, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT", x + 12, y + 12)
	else
		Call(addon, tooltip, "SetPoint", "BOTTOMLEFT", pin.frame, "TOPRIGHT", 6, 6)
	end
	Call(addon, tooltip, "Show")
	state.hovered = pin
	if state.onHoverChanged then
		state.onHoverChanged()
	end
end

function QuestTogether:PresentPlayerTooltip(state, anchor, row)
	-- IsShown stays true below a hidden UIParent (Alt+Z). No hover interest may
	-- outlive its visible anchor, including a recycled pin or a different link.
	local name, generation = row.name, anchor.presentationGeneration
	local function Current()
		return state.hovered == anchor and anchor.name == name and anchor.presentationGeneration == generation
			and not self:IsRuntimeRestricted()
			and Method(self, anchor.frame, "IsVisible") == true
			and Method(self, self:GetPlayerTooltipPresentationParent(), "IsVisible") == true
			and (not anchor.isCurrent or anchor.isCurrent())
	end
	if Method(self, anchor.frame, "IsVisible") ~= true
		or Method(self, self:GetPlayerTooltipPresentationParent(), "IsVisible") ~= true then
		self:HidePlayerTooltipPresentation(state)
		return
	end
	self:RenderPlayerTooltip(state, anchor, self:BuildPlayerTooltipModel(row))
	if not row.questID and not row.tipAction and Current() then
		self:SetPlayerDetailsInterest(state, name, Current)
	else
		self:ClearPlayerDetailsInterest(state)
	end
end

-- The same owned tooltip renderer serves dots and QT speaker links. Keep their
-- hover state separate so refreshing map pins cannot dismiss a chat tooltip.
function QuestTogether:GetChatLogTooltipCursorPosition(parent)
	local x, y = Native(self, GetCursorPosition)
	x, y = Number(self, x), Number(self, y)
	local scale = Positive(self, Method(self, parent, "GetEffectiveScale"))
	if x and y and scale then
		return x / scale, y / scale
	end
end

function QuestTogether:GetChatLogPlayerTooltipRow(name)
	if self:IsSelfSender(name) and not self:IsRuntimeRestricted() then
		local ok, row = pcall(self.ReadLocalPlayerLocation, self)
		if ok and type(row) == "table" then
			row.name = name
			return row
		end
		return { name = name }
	end
	local state = rawget(self, "playerLocationState")
	local row = state and state.peers and state.peers[name]
	return row or { name = name }
end

function QuestTogether:HideChatLogPlayerTooltip()
	local state = rawget(self, "chatLogPlayerTooltipState")
	if state then
		HideTooltip(self, state)
	end
end

function QuestTogether:UpdateChatLogPlayerTooltip()
	local state = rawget(self, "chatLogPlayerTooltipState")
	if not state then
		return
	end
	self:FlushOwnedUICleanup()
	local pin = state.hovered
	if not pin then
		return
	end
	if
		not self.isEnabled
		or self:IsRuntimeRestricted()
		or (not pin.questID and not pin.tipAction and self:IsIgnoredPlayerName(pin.name))
		or Method(self, pin.frame, "IsShown") ~= true
	then
		self:HideChatLogPlayerTooltip()
		return
	end
	local ok, row
	if pin.tipAction then
		ok, row = true, { tipAction = pin.tipAction }
	elseif pin.questID then
		ok, row = pcall(self.GetChatLogQuestTooltipRow, self, pin.questID, pin.title)
	else
		ok, row = pcall(self.GetChatLogPlayerTooltipRow, self, pin.name)
	end
	if not ok or type(row) ~= "table" or not pcall(self.PresentPlayerTooltip, self, state, pin, row) then
		self:HideChatLogPlayerTooltip()
	end
end

function QuestTogether:ShowChatLogPlayerTooltip(frame, link, text)
	self:HideChatLogPlayerTooltip()
	if not self.isEnabled or self:IsRuntimeRestricted() or not self:CanAccessForeignFrame(frame, true) then
		return false
	end
	link = self:SafeTrimString(link, "")
	local kind, name = link:match("^([^:]+):(.+)$")
	local questID, tipAction
	if kind == "questtogethertip" then
		tipAction = self:ParseHintActionLink(link)
		if not tipAction then return false end
	elseif kind == self.chatLogQuestLinkType then
		questID = self:SafeToNumber(name)
		if not questID or questID < 1 or questID > 1000000000 or questID ~= math.floor(questID) then
			return false
		end
	elseif kind == self.chatLogLinkType then
		name = self:NormalizeMemberName(name)
		if not name or self:IsIgnoredPlayerName(name) then
			return false
		end
	else
		return false
	end
	local state = rawget(self, "chatLogPlayerTooltipState") or {}
	self.chatLogPlayerTooltipState = state
	state.hovered =
		{ frame = frame, name = name, questID = questID, tipAction = tipAction, title = self:SafeTrimString(text, ""), chatLink = true }
	self:UpdateChatLogPlayerTooltip()
	return state.hovered ~= nil
end

-- Public event callbacks avoid replacing chat scripts or writing onto chat frames.
function QuestTogether:RegisterChatLogHoverCallbacks(enter, leave)
	if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
		return false
	end
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", enter, self)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", leave, self)
	return true
end

function QuestTogether:InitializeChatLogPlayerTooltips()
	if rawget(self, "chatLogHoverCallbacksInstalled") then
		return
	end
	self.chatLogHoverCallbacksInstalled = self:RegisterChatLogHoverCallbacks(function(_, frame, link, text)
		self:ShowChatLogPlayerTooltip(frame, link, text)
	end, function()
		self:HideChatLogPlayerTooltip()
	end)
end
