-- Shared QT-owned detail-section artwork for the PQL and focused quest HUD.
local CORNER_RADIUS = 6
local CORNER_FILL = "Interface\\AddOns\\QuestTogether\\Media\\PanelCornerFill"
local CORNER_BORDER = "Interface\\AddOns\\QuestTogether\\Media\\PanelCornerBorder"
local CORNER_UV = { { 0, 0.5, 0, 0.5 }, { 0.5, 1, 0, 0.5 }, { 0, 0.5, 0.5, 1 }, { 0.5, 1, 0.5, 1 } }
local function ShowPanel(region, shown)
	region.panelShown = shown
	region[shown and "Show" or "Hide"](region)
	for _, part in ipairs(region.panelParts or {}) do
		part[shown and part.panelActive and "Show" or "Hide"](part)
	end
end
local function ColorPanel(region, ...)
	region:SetColorTexture(...)
	for index, part in ipairs(region.panelParts or {}) do
		if index <= 2 then
			part:SetColorTexture(...)
		else
			part:SetVertexColor(...)
		end
	end
end
local function LayoutPanel(region, parent, layer, sublevel, x, y, width, height, roundedTop, roundedBottom)
	local radius = (roundedTop or roundedBottom) and CORNER_RADIUS or 0
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", x + radius, -y)
	region:SetSize(width - radius * 2, height)
	if radius > 0 and not region.panelParts then
		region.panelParts = {}
		for index = 1, 6 do
			local part = parent:CreateTexture(nil, layer, nil, sublevel)
			region.panelParts[index] = part
			if index > 2 then
				part:SetTexture(CORNER_FILL)
				part:SetTexCoord(unpack(CORNER_UV[index - 2]))
			end
		end
	end
	for index, part in ipairs(region.panelParts or {}) do
		part:ClearAllPoints()
		part.panelActive = radius > 0 and (index <= 2 or (index <= 4 and roundedTop) or (index >= 5 and roundedBottom))
		if index <= 2 then
			local top = roundedTop and radius or 0
			part:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (index == 1 and 0 or width - radius), -y - top)
			part:SetSize(math.max(1, radius), height - top - (roundedBottom and radius or 0))
		else
			local right, bottom = index % 2 == 0, index >= 5
			part:SetPoint(
				"TOPLEFT",
				parent,
				"TOPLEFT",
				x + (right and width - radius or 0),
				-y - (bottom and height - radius or 0)
			)
			part:SetSize(CORNER_RADIUS, CORNER_RADIUS)
		end
	end
	ShowPanel(region, region.panelShown ~= false)
end

local function LayoutDetailsPanel(row, width, details, first, last, expanded, dark, compact, opacity, borderless)
	local height = row:GetHeight()
	local left, right = details and not compact and 28 or 0, details and not compact and 14 or 0
	local top, bottom = details and not compact and first and 6 or 0, details and not compact and last and 6 or 0
	opacity = opacity or 1
	-- Each pooled row supplies one slice of the same inset panel. Only the
	-- true section edges get end caps; scrolling clips the panel naturally.
	local roundTop, roundBottom = details and first, details and last
	LayoutPanel(
		row.paper,
		row,
		"BACKGROUND",
		-1,
		left,
		top,
		width - left - right,
		height - top - bottom,
		roundTop,
		roundBottom
	)
	LayoutPanel(
		row.background,
		row,
		"BACKGROUND",
		0,
		left,
		top,
		width - left - right,
		height - top - bottom,
		roundTop,
		roundBottom
	)
	LayoutPanel(
		row.hover,
		row,
		"BORDER",
		0,
		left,
		top,
		width - left - right,
		height - top - bottom,
		roundTop,
		roundBottom
	)
	if dark then
		ColorPanel(row.paper, 0.10, 0.12, 0.15, (details and 0.98 or 0.6) * opacity)
	else
		ColorPanel(row.paper, 1, 0.94, 0.79, (details and 0.85 or 0.35) * opacity)
	end
	if details or expanded then
		ShowPanel(row.paper, true)
	else
		ShowPanel(row.paper, false)
	end
	if borderless then
		for _, edge in ipairs(row.panelEdges) do
			edge:Hide()
		end
		for _, corner in ipairs(row.panelCorners or {}) do
			corner:Hide()
		end
		return top, bottom
	end
	for _, edge in ipairs(row.panelEdges) do
		edge:Hide()
		edge:ClearAllPoints()
		if dark then
			edge:SetColorTexture(0.64, 0.58, 0.42, 0.65 * opacity)
		else
			edge:SetColorTexture(0.32, 0.22, 0.10, 0.65 * opacity)
		end
	end
	if details then
		for i, x in ipairs({ left, width - right - 1 }) do
			local edge = row.panelEdges[i]
			edge:SetPoint("TOPLEFT", row, "TOPLEFT", x, -top - (roundTop and CORNER_RADIUS or 0))
			edge:SetSize(
				1,
				height - top - bottom - (roundTop and CORNER_RADIUS or 0) - (roundBottom and CORNER_RADIUS or 0)
			)
			edge:Show()
		end
	end
	if (details and first) or expanded then
		row.panelEdges[3]:SetPoint("TOPLEFT", row, "TOPLEFT", left + (roundTop and CORNER_RADIUS or 0), -top)
		row.panelEdges[3]:SetSize(width - left - right - (roundTop and CORNER_RADIUS * 2 or 0), 1)
		row.panelEdges[3]:Show()
	end
	if (details and last) or expanded then
		row.panelEdges[4]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left + (roundBottom and CORNER_RADIUS or 0), bottom)
		row.panelEdges[4]:SetSize(width - left - right - (roundBottom and CORNER_RADIUS * 2 or 0), 1)
		row.panelEdges[4]:Show()
	end
	if (roundTop or roundBottom) and not row.panelCorners then
		row.panelCorners = {}
		for index = 1, 4 do
			local corner = row:CreateTexture(nil, "ARTWORK")
			corner:SetTexture(CORNER_BORDER)
			corner:SetTexCoord(unpack(CORNER_UV[index]))
			corner:SetSize(CORNER_RADIUS, CORNER_RADIUS)
			row.panelCorners[index] = corner
		end
	end
	for index, corner in ipairs(row.panelCorners or {}) do
		corner:ClearAllPoints()
		local rightSide, bottomSide = index % 2 == 0, index > 2
		corner:SetPoint(
			"TOPLEFT",
			row,
			"TOPLEFT",
			rightSide and width - right - CORNER_RADIUS or left,
			bottomSide and -height + bottom + CORNER_RADIUS or -top
		)
		if dark then
			corner:SetVertexColor(0.64, 0.58, 0.42, 0.65 * opacity)
		else
			corner:SetVertexColor(0.32, 0.22, 0.10, 0.65 * opacity)
		end
		corner[((bottomSide and roundBottom) or (not bottomSide and roundTop)) and "Show" or "Hide"](corner)
	end
	row.accent:ClearAllPoints()
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", details and left + 3 or 0, -top)
	row.accent:SetSize(3, height - top - bottom)
	return top, bottom
end

local function LayoutProgressBar(row, data, dark, x, y, width)
	if data.fraction then
		local barWidth = width
		row.progressTrack:ClearAllPoints()
		row.progressTrack:SetPoint("TOPLEFT", x, -y)
		row.progressFill:ClearAllPoints()
		row.progressFill:SetPoint("TOPLEFT", x, -y)
		row.progressTrack:SetWidth(barWidth)
		row.progressTrack:SetColorTexture(
			dark and 0.75 or 0.3,
			dark and 0.78 or 0.2,
			dark and 0.8 or 0.08,
			dark and 0.22 or 0.15
		)
		row.progressTrack:Show()
		row.progressFill:SetWidth(math.max(1, barWidth * data.fraction))
		if dark then
			row.progressFill:SetColorTexture(
				data.complete and 0.40 or 0.86,
				data.complete and 0.90 or 0.65,
				data.complete and 0.48 or 0.32,
				0.9
			)
		else
			row.progressFill:SetColorTexture(data.complete and 0.12 or 0.50, data.complete and 0.38 or 0.32, 0.12, 0.85)
		end
		if data.fraction > 0 then
			row.progressFill:Show()
		else
			row.progressFill:Hide()
		end
	else
		row.progressTrack:Hide()
		row.progressFill:Hide()
	end
end

_G.QuestTogether.QuestProgressStyle = {
	ShowPanel = ShowPanel,
	LayoutPanel = LayoutPanel,
	ColorPanel = ColorPanel,
	LayoutDetailsPanel = LayoutDetailsPanel,
	LayoutProgressBar = LayoutProgressBar,
}
