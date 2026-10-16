-- Location presentation only. Accepted observations and consent remain owned
-- by PlayerLocations; this module never requests or renews a location.
local QT = _G.QuestTogether
local L = QT.Translate
local MAX_ROWS, CLUSTER_RADIUS, SELECTION_LIFETIME, NAVIGATION_LIFETIME = 512, 24, 20, 2
local EXPANSION_PAGE_SIZE, EXPANSION_INSET, EXPANSION_SPACING = 12, 10, 22
local GEOMETRY_FIELDS = { "mapID", "width", "height", "canvasLeft", "canvasTop", "canvasWidth", "canvasHeight", "parent" }

local function Now(a)
	return a:SafeToNumber(a.API.GetTime()) or 0
end

-- Page boundaries precede grouping, so an expanded summary describes only its
-- visible fanout page. Collapsed summaries can pull later groupmates forward.
-- The shared party query owns freshness/revisions; no roster request is needed.
function QT:BuildPlayerLocationClusterTooltipMembers(rows, first, last, limit)
	if type(rows) ~= "table" then return {} end
	first = math.max(1, math.floor(self:SafeToNumber(first) or 1))
	last = math.min(MAX_ROWS, #rows, math.floor(self:SafeToNumber(last) or #rows))
	limit = math.max(0, math.min(6, math.floor(self:SafeToNumber(limit) or 6)))
	if first > last or limit == 0 then return {} end
	local groups, byParty = {}, {}
	for index = first, last do
		local row = rows[index]
		local name = type(row) == "table" and self:SafeTrimString(row.name, "") or ""
		if name ~= "" and not self:IsIgnoredPlayerName(name) then
			local info = self:GetPlayerPartyVisualInfo(name)
			local size = type(info) == "table" and self:SafeToNumber(info.size)
			local key = size and size >= 2 and size <= 40 and size == math.floor(size)
				and type(info.key) == "string" and info.key ~= "" and info.key or nil
			local group = key and byParty[key]
			if not group then
				group = { rows = {}, key = key, size = key and size or nil }
				groups[#groups + 1] = group
				if key then byParty[key] = group end
			end
			group.rows[#group.rows + 1] = row
		end
	end
	local members = {}
	for _, group in ipairs(groups) do
		for _, row in ipairs(group.rows) do
			local member = self:BuildPlayerTooltipMember(row, { shortName = true, usesQT = true })
			if member then
				member.partyKey = group.key
				member.partySize = group.size
				members[#members + 1] = member
				if #members == limit then return members end
			end
		end
	end
	return members
end

function QT:GetFindPlayerMapLocation(name)
	name = self:NormalizeMemberName(name)
	if not self.isEnabled or self.isLoggingOut then
		return nil, L("Enable QuestTogether to find players on the map.")
	end
	if self:IsRuntimeRestricted() then
		return nil, L("The map cannot be opened right now. Try again when combat or other restrictions end.")
	end
	if not name or self:IsIgnoredPlayerName(name) or self:IsSelfSender(name) then
		return nil, L("No shared location is available for this player.")
	end
	if self:IsGroupedSender(name) then
		return nil, L("Your party members are shown by WoW's own map markers.")
	end
	if self:GetOption("showPlayerLocations") ~= true or self:GetOption("mapPartyOnly") == true then
		return nil, L("Enable player locations in QuestTogether settings to find players on the map.")
	end
	local row = self:GetFreshPlayerLocation(name, "map")
	if not row then return nil, L("No recent shared world-map location is available for this player.") end
	return row
end

function QT:CanFindPlayerOnMap(name)
	local row, reason = self:GetFindPlayerMapLocation(name)
	return row ~= nil, reason
end

function QT:ClearPlayerMapSelection()
	self.playerMapSelection = nil
end

function QT:FindPlayerOnMap(name)
	self:ClearPlayerLocationClusterExpansion()
	local row, reason = self:GetFindPlayerMapLocation(name)
	if not row then self:Print(reason); return false end
	if not self.API.OpenPlayerLocationMap(row.mapID) then
		self:Print(L("This player's map cannot be opened right now."))
		return false
	end
	local current = self:GetFindPlayerMapLocation(row.name)
	if not current or current.mapID ~= row.mapID then
		self:Print(L("No recent shared world-map location is available for this player."))
		return false
	end
	-- An explicit Find action should reveal its result, while preserving all
	-- sharing and player-filter preferences controlled by other settings.
	if not self:IsQuestTogetherMapDataShown("map") then
		if not self:SetOption("showWorldMapData", true) then return false end
	end
	self.playerMapSelection = { name = row.name, mapID = row.mapID, expires = Now(self) + SELECTION_LIFETIME }
	self:RefreshPlayerLocationPins()
	return true
end

function QT:GetSelectedPlayerMapLocation(mapID)
	local selection = rawget(self, "playerMapSelection")
	if not selection then return nil end
	local row = self:GetFindPlayerMapLocation(selection.name)
	if Now(self) >= selection.expires or not row or row.mapID ~= selection.mapID
		or (mapID and selection.mapID ~= mapID) then
		self:ClearPlayerMapSelection()
		return nil
	end
	return row
end

function QT:ClearPlayerLocationClusterExpansion()
	self.playerLocationClusterExpansion = nil
	self.playerLocationClusterNavigation = nil
end

local function ExpansionAllowed(a)
	return a.isEnabled and not a.isLoggingOut and not a:IsRuntimeRestricted()
		and a:IsQuestTogetherMapDataShown("map")
		and a:GetOption("showPlayerLocations") == true and a:GetOption("clusterPlayerLocations") ~= false
end

local function SameGeometry(saved, current)
	if not saved or not current then return false end
	for _, field in ipairs(GEOMETRY_FIELDS) do
		if saved[field] ~= current[field] then return false end
	end
	return true
end

local function ClusterMemberKey(cluster)
	if type(cluster) ~= "table" or type(cluster.members) ~= "table"
		or #cluster.members < 2 or #cluster.members > MAX_ROWS then return nil end
	local names, seen = {}, {}
	for _, row in ipairs(cluster.members) do
		local name = type(row) == "table" and row.name
		if type(name) ~= "string" or name == "" or name:find("\n", 1, true) or seen[name] then return nil end
		seen[name], names[#names + 1] = true, name
	end
	table.sort(names)
	local key = table.concat(names, "\n")
	return key == cluster.key and key or nil
end

local function NavigationProfile(addon)
	local db = rawget(addon, "db")
	return db and db.profile
end

-- A navigation click owns one short intent. It retains member identity only;
-- target markers supply fresh admitted rows after native map navigation.
function QT:BeginPlayerLocationClusterNavigation(cluster, geometry, targetMapID)
	self:ClearPlayerLocationClusterExpansion()
	local key = ClusterMemberKey(cluster)
	targetMapID = self:SafeToNumber(targetMapID)
	if not key or not ExpansionAllowed(self) or type(geometry) ~= "table"
		or not targetMapID or targetMapID < 1 or targetMapID > 1000000
		or targetMapID ~= math.floor(targetMapID) or targetMapID == geometry.mapID then return nil end
	local now = Now(self)
	local intent = { key = key, count = #cluster.members, sourceMapID = geometry.mapID,
		targetMapID = targetMapID, parent = geometry.parent, createdAt = now, expires = now + NAVIGATION_LIFETIME,
		owner = rawget(self, "runtimeCoordinatorState"), world = rawget(self, "commsWorldGeneration"),
		profile = NavigationProfile(self), token = {}, navigating = true }
	self.playerLocationClusterNavigation = intent
	return intent
end

function QT:CancelPlayerLocationClusterNavigation(intent)
	if rawget(self, "playerLocationClusterNavigation") == intent then self.playerLocationClusterNavigation = nil end
	local expansion = rawget(self, "playerLocationClusterExpansion")
	if intent and expansion and expansion.navigationToken == intent.token then self.playerLocationClusterExpansion = nil end
end

function QT:ConsumePlayerLocationClusterNavigation(markers, geometry)
	local intent = rawget(self, "playerLocationClusterNavigation")
	if not intent then return false end
	local now = Now(self)
	if not ExpansionAllowed(self) or now < intent.createdAt or now >= intent.expires
		or rawget(self, "runtimeCoordinatorState") ~= intent.owner or rawget(self, "commsWorldGeneration") ~= intent.world
		or NavigationProfile(self) ~= intent.profile or not geometry or geometry.parent ~= intent.parent then
		self:CancelPlayerLocationClusterNavigation(intent)
		return false
	end
	if geometry.mapID ~= intent.targetMapID then
		-- SetMapID can synchronously notify listeners while the old canvas is
		-- still being retired. Only that call may retain its source-map intent.
		if not intent.navigating or geometry.mapID ~= intent.sourceMapID then
			self:CancelPlayerLocationClusterNavigation(intent)
		end
		return false
	end
	self.playerLocationClusterNavigation = nil
	for index = 1, math.min(MAX_ROWS + 1, #markers) do
		local marker = markers[index]
		if marker.members and #marker.members == intent.count and ClusterMemberKey(marker) == intent.key then
			if self:TogglePlayerLocationClusterExpansion(marker, geometry) then
				self.playerLocationClusterExpansion.navigationToken = intent.token
				return true
			end
			break
		end
	end
	return false
end

local function ExpansionInfo(page, pageSize, total)
	local pages = pageSize > 0 and math.ceil(total / pageSize) or 0
	page = pages > 0 and math.max(1, math.min(pages, math.floor(page or 1))) or 0
	return { page = page, pages = pages, pageSize = pageSize, total = total,
		first = pages > 0 and (page - 1) * pageSize + 1 or 0,
		last = pages > 0 and math.min(page * pageSize, total) or 0 }
end

-- Produce display positions only. The player's accepted coordinates remain
-- untouched and sourceX/sourceY identify the true projected point for a line.
-- Rings are sampled in a fixed order, then rejected when clipped/overlapping;
-- individual points are never clamped onto each other at viewport boundaries.
function QT:LayoutPlayerLocationClusterExpansion(cluster, geometry, page, obstacles)
	local members = {}
	for index = 1, math.min(MAX_ROWS, #(cluster.members or {})) do members[index] = cluster.members[index] end
	table.sort(members, function(a, b) return a.name < b.name end)
	local slots = {}
	local radius = math.max(24, math.min(48, (math.min(geometry.width, geometry.height) - 2 * EXPANSION_INSET) / 2))
	local function AddSlot(x, y)
		if x < EXPANSION_INSET or y < EXPANSION_INSET
			or x > geometry.width - EXPANSION_INSET or y > geometry.height - EXPANSION_INSET then return end
		if (x - cluster.x)^2 + (y - cluster.y)^2 < 24^2 then return end
		for _, other in ipairs(slots) do
			if (x - other.x)^2 + (y - other.y)^2 < EXPANSION_SPACING^2 then return end
		end
		for index = 1, math.min(EXPANSION_PAGE_SIZE, #(obstacles or {})) do
			local other = obstacles[index]
			if (x - other.x)^2 + (y - other.y)^2 < 26^2 then return end
		end
		slots[#slots + 1] = { x = x, y = y }
	end
	for ring = 0, 4 do
		for index = 0, 23 do
			if #slots >= EXPANSION_PAGE_SIZE then break end
			local angle = -math.pi / 2 + index * math.pi / 12
			AddSlot(cluster.x + math.cos(angle) * (radius + ring * 28), cluster.y + math.sin(angle) * (radius + ring * 28))
		end
		if #slots >= EXPANSION_PAGE_SIZE then break end
	end
	local info = ExpansionInfo(self:SafeToNumber(page) or 1, #slots, #members)
	local dots = {}
	for index = info.first, info.last do
		local row, slot = members[index], slots[index - info.first + 1]
		if row and slot then
			local sourceX, sourceY = self:ProjectPlayerLocationPin("map", row, geometry)
			if not sourceX or not sourceY then return {}, info end
			dots[#dots + 1] = { row = row, key = row.name, clusterKey = cluster.key,
				x = slot.x, y = slot.y, sourceX = sourceX, sourceY = sourceY, expanded = true }
		end
	end
	return dots, info
end

function QT:TogglePlayerLocationClusterExpansion(cluster, geometry)
	self.playerLocationClusterNavigation = nil
	if not ExpansionAllowed(self) or not cluster or not cluster.members or #cluster.members < 2 then
		self:ClearPlayerLocationClusterExpansion()
		return false
	end
	local previous = rawget(self, "playerLocationClusterExpansion")
	if previous and previous.key == cluster.key and SameGeometry(previous.geometry, geometry) then
		self:ClearPlayerLocationClusterExpansion()
		return false
	end
	local dots, info = self:LayoutPlayerLocationClusterExpansion(cluster, geometry, 1)
	if #dots == 0 then self:ClearPlayerLocationClusterExpansion(); return false end
	local view = {}
	for _, field in ipairs(GEOMETRY_FIELDS) do view[field] = geometry[field] end
	self.playerLocationClusterExpansion = { key = cluster.key, page = 1, pageSize = info.pageSize, geometry = view }
	return true
end

function QT:ChangePlayerLocationClusterPage(cluster, geometry, delta)
	local state = rawget(self, "playerLocationClusterExpansion")
	if not state or not ExpansionAllowed(self) or not SameGeometry(state.geometry, geometry)
		or not cluster or cluster.key ~= state.key then
		self:ClearPlayerLocationClusterExpansion()
		return false
	end
	local info = ExpansionInfo(state.page + (self:SafeToNumber(delta) or 0), state.pageSize, #cluster.members)
	local changed = state.page ~= info.page
	state.page, state.pageSize = info.page, info.pageSize
	return changed
end

-- Only the current admitted markers can provide members. Removed, ignored,
-- expired, hidden or otherwise filtered players cannot survive in expansion
-- state, which retains no rows or identities beyond the cluster's exact key.
function QT:GetPlayerLocationClusterExpansion(markers, geometry)
	local state = rawget(self, "playerLocationClusterExpansion")
	if not state then return nil end
	if not ExpansionAllowed(self) or not SameGeometry(state.geometry, geometry) then
		self:ClearPlayerLocationClusterExpansion()
		return nil
	end
	local cluster, obstacles
	for index = 1, math.min(MAX_ROWS + 1, #markers) do
		local marker = markers[index]
		if marker.selected then obstacles = { marker } end
		if marker.members and marker.key == state.key then cluster = marker end
	end
	if not cluster then self:ClearPlayerLocationClusterExpansion(); return nil end
	local dots, info = self:LayoutPlayerLocationClusterExpansion(cluster, geometry, state.page, obstacles)
	if #dots == 0 then self:ClearPlayerLocationClusterExpansion(); return nil end
	state.page, state.pageSize = info.page, info.pageSize
	info.token = state
	return dots, cluster, info
end

-- Rendering and menu-currentness checks must admit exactly the same peers,
-- including distance priority, private diagnostic rows and explicit Find.
function QT:GetPlayerLocationMapMarkers(rows, geometry, maximumPins)
	if #rows > maximumPins then rows = self:PrioritizePlayerLocationRows(rows, self:GetPlayerLocationPriorityOrigin()) end
	local selected = self:GetSelectedPlayerMapLocation(geometry.mapID)
	if selected then
		local copy = { selected }
		for _, row in ipairs(rows) do
			if row.name ~= selected.name then copy[#copy + 1] = row end
		end
		rows = copy
	end
	local cluster = self:GetOption("clusterPlayerLocations") ~= false
	if not cluster then self:ClearPlayerLocationClusterExpansion() end
	return self:BuildPlayerLocationMapMarkers(rows, geometry, selected and selected.name, cluster)
end

-- Project before grouping: the radius is measured in UI pixels and therefore
-- naturally separates groups as the map zooms in. Stable name order makes
-- membership deterministic even if peer/store iteration order changes.
function QT:BuildPlayerLocationMapMarkers(rows, geometry, selectedName, clustersEnabled)
	local points = {}
	for index = 1, math.min(MAX_ROWS, #rows) do
		local row = rows[index]
		local x, y = self:ProjectPlayerLocationPin("map", row, geometry)
		if x and y and type(row.name) == "string" and row.name ~= "" then
			points[#points + 1] = { row = row, x = x, y = y, rank = index }
		end
	end
	table.sort(points, function(a, b) return a.row.name < b.row.name end)
	if clustersEnabled == false or geometry.width < 24 or geometry.height < 24 then
		-- A count marker cannot fit on this surface. Retain normal-size dots.
		table.sort(points, function(a, b)
			if (a.row.name == selectedName) ~= (b.row.name == selectedName) then return a.row.name == selectedName end
			return a.rank < b.rank
		end)
		local markers = {}
		for _, point in ipairs(points) do
			markers[#markers + 1] = { row = point.row, x = point.x, y = point.y,
				key = point.row.name, selected = point.row.name == selectedName }
		end
		return markers
	end
	local groups, cells, selected = {}, {}, nil
	local function Cell(x, y) return x .. ":" .. y end
	for _, point in ipairs(points) do
		if point.row.name == selectedName then
			selected = { row = point.row, x = point.x, y = point.y, key = point.row.name, selected = true }
		else
			local cx, cy = math.floor(point.x / CLUSTER_RADIUS), math.floor(point.y / CLUSTER_RADIUS)
			local best, distance
			for dx = -1, 1 do
				for dy = -1, 1 do
					for _, group in ipairs(cells[Cell(cx + dx, cy + dy)] or {}) do
						local d = (point.x - group.anchorX)^2 + (point.y - group.anchorY)^2
						if d <= CLUSTER_RADIUS^2 and (not distance or d < distance or (d == distance and group.key < best.key)) then
							best, distance = group, d
						end
					end
				end
			end
			if not best then
				best = { members = {}, x = 0, y = 0, anchorX = point.x, anchorY = point.y, rank = point.rank, key = point.row.name }
				groups[#groups + 1] = best
				local key = Cell(cx, cy)
				cells[key] = cells[key] or {}
				cells[key][#cells[key] + 1] = best
			end
			best.members[#best.members + 1] = point.row
			best.x, best.y = best.x + point.x, best.y + point.y
			best.rank = math.min(best.rank, point.rank)
		end
	end
	table.sort(groups, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.key < b.key
	end)
	local markers = selected and { selected } or {}
	for _, group in ipairs(groups) do
		local count = #group.members
		group.x, group.y = group.x / count, group.y / count
		if count == 1 then group.row, group.members = group.members[1], nil
		else
			-- Individual dots can fit nearer the edge than a count marker. Keep
			-- the larger marker and its entire hit target inside the viewport.
			local half = 12
			group.x = math.max(half, math.min(geometry.width - half, group.x))
			group.y = math.max(half, math.min(geometry.height - half, group.y))
			local names = {}
			for _, row in ipairs(group.members) do names[#names + 1] = row.name end
			group.key = table.concat(names, "\n")
		end
		markers[#markers + 1] = group
	end
	return markers
end
