-- Pure model and adapter tests: never access native map/UI state.
local QT = _G.QuestTogether
local function Equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function Near(a, b) assert(math.abs(a - b) < 0.00001) end
local function Fixture()
	local a = setmetatable({ isEnabled = true, now = 100, rows = {}, options = { showPlayerLocations = true } }, { __index = QT })
	a.API = {
		GetTime = function() return a.now end,
		OpenPlayerLocationMap = function(mapID) a.opened = mapID; return not a.openFails end,
	}
	function a:NormalizeMemberName(name) return type(name) == "string" and name ~= "" and name or nil end
	function a:IsRuntimeRestricted() return self.blocked end
	function a:IsIgnoredPlayerName(name) return name == self.ignored end
	function a:IsSelfSender(name) return name == "Me" end
	function a:IsGroupedSender(name) return name == self.party end
	function a:GetOption(key) return self.options[key] end
	function a:Print(message) self.message = message end
	function a:RefreshPlayerLocationPins() self.refreshes = (self.refreshes or 0) + 1 end
	function a:ProjectPlayerLocationPin(_, row, geometry)
		self.projections = (self.projections or 0) + 1
		if row.mapID == geometry.mapID then return row.x * geometry.width, row.y * geometry.height end
	end
	a.playerLocationState = { peers = a.rows }
	return a
end
local function Row(name, x, y)
	return { name = name, x = x or 0.5, y = y or 0.5, mapID = 1, mask = 3, sampledAt = 100, receivedAt = 100, lifetime = 600 }
end
local geometry = { mapID = 1, width = 1000, height = 600 }

local function TooltipFixture()
	local a = Fixture()
	a.visuals, a.partyQueries, a.memberBuilds, a.networkCalls = {}, {}, {}, 0
	function a:GetPlayerPartyVisualInfo(name)
		self.partyQueries[#self.partyQueries + 1] = name
		return self.visuals[name]
	end
	function a:BuildPlayerTooltipMember(row, options)
		assert(options.shortName == true and options.usesQT == true and options.leader == nil)
		self.memberBuilds[#self.memberBuilds + 1] = row.name
		if row.name == self.skipMember then return nil end
		return { name = row.name, label = row.name, icon = row.icon, developer = row.developer,
			hiddenLocation = row.hiddenLocation, color = { 0.1, 0.2, 0.3 } }
	end
	local function NoNetwork(self)
		self.networkCalls = self.networkCalls + 1
		error("cluster tooltip grouping must not request or publish data")
	end
	a.RequestPartyVisualRoster, a.RequestPlayerDetails, a.Request, a.Publish = NoNetwork, NoNetwork, NoNetwork, NoNetwork
	return a
end

local function MemberNames(members)
	local names = {}
	for _, member in ipairs(members) do names[#names + 1] = member.name end
	return table.concat(names, ",")
end

QT:RegisterTest("cluster tooltip parties stay adjacent in first appearance order before the display cap", function()
	local a, rows = TooltipFixture(), {}
	for index = 1, 10 do rows[index] = Row(string.char(64 + index)) end
	for _, pair in ipairs({ { "A", "H", "Leader:1" }, { "B", "I", "Leader:2" }, { "C", "J", "Other:1" } }) do
		for index = 1, 2 do a.visuals[pair[index]] = { key = pair[3], size = 2, leader = "Leader" } end
	end
	rows[1].developer, rows[1].hiddenLocation, rows[1].icon = true, true, "existing-LFQP-icon"
	local before = QT:DeepCopy(rows)
	local members = a:BuildPlayerLocationClusterTooltipMembers(rows)
	Equal(MemberNames(members), "A,H,B,I,C,J")
	Equal(members[1].partyKey, "Leader:1")
	Equal(members[2].partyKey, "Leader:1")
	Equal(members[3].partyKey, "Leader:2")
	assert(members[1].developer and members[1].hiddenLocation and members[1].icon == rows[1].icon)
	for index, row in ipairs(rows) do
		Equal(row.name, before[index].name)
		Equal(row.partyKey, nil)
		Equal(row.partySize, nil)
		Equal(row.developer, before[index].developer)
		assert(row ~= members[index])
	end
	Equal(#a.partyQueries, 10)
	Equal(#a.memberBuilds, 6)
	Equal(a.networkCalls, 0)
	Equal(MemberNames(a:BuildPlayerLocationClusterTooltipMembers(rows)), "A,H,B,I,C,J")
end)

QT:RegisterTest("cluster tooltip party grouping never pulls members across the expanded page boundary", function()
	local a, rows = TooltipFixture(), {}
	for index = 1, 10 do rows[index] = Row(string.char(64 + index)) end
	a.visuals.A, a.visuals.H = { key = "First:1", size = 2 }, { key = "First:1", size = 2 }
	a.visuals.C, a.visuals.J = { key = "Second:1", size = 2 }, { key = "Second:1", size = 2 }
	local members = a:BuildPlayerLocationClusterTooltipMembers(rows, 3, 8)
	Equal(MemberNames(members), "C,D,E,F,G,H")
	Equal(members[1].partyKey, "Second:1") -- one visible member still has known party identity
	Equal(members[6].partyKey, "First:1")
	Equal(members[2].partyKey, nil)
	Equal(table.concat(a.partyQueries, ","), "C,D,E,F,G,H")
	Equal(MemberNames(a:BuildPlayerLocationClusterTooltipMembers(rows, 3, 10)), "C,J,D,E,F,G")
	a.ignored, a.skipMember = "C", "D"
	Equal(MemberNames(a:BuildPlayerLocationClusterTooltipMembers(rows, 3, 8)), "E,F,G,H")
	Equal(a.networkCalls, 0)
end)

QT:RegisterTest("cluster tooltip party keys require an explicit valid grouped size and exact revision identity", function()
	local a, rows = TooltipFixture(), { Row("A"), Row("B"), Row("C"), Row("D") }
	a.visuals.A, a.visuals.C = { key = "Leader:1", size = 2 }, { key = "Leader:1", size = 2 }
	a.visuals.B, a.visuals.D = { key = "Leader:2", size = 40 }, { key = "Leader:2", size = 40 }
	Equal(MemberNames(a:BuildPlayerLocationClusterTooltipMembers(rows)), "A,C,B,D")
	for _, info in ipairs({ { leader = "Leader", size = 2 }, { key = "", size = 2 },
		{ key = "Leader:1" }, { key = "Leader:1", grouped = true }, { key = "Leader:1", size = 0 },
		{ key = "Leader:1", size = 1 }, { key = "Leader:1", size = 41 }, { key = "Leader:1", size = 2.5 },
		{ key = "Leader:1", size = math.huge } }) do
		a.visuals.A, a.visuals.B = info, info
		local members = a:BuildPlayerLocationClusterTooltipMembers({ rows[1], rows[2] })
		Equal(MemberNames(members), "A,B")
		Equal(members[1].partyKey, nil)
		Equal(members[2].partyKey, nil)
		Equal(members[1].partySize, nil)
		Equal(members[2].partySize, nil)
	end
end)

QT:RegisterTest("cluster tooltip party counts retain total membership beyond the cluster or visible page", function()
	local a, rows = TooltipFixture(), { Row("A"), Row("B"), Row("C") }
	a.visuals.A, a.visuals.C = { key = "Raid:1", size = 40 }, { key = "Raid:1", size = 40 }
	rows[2].partySize = 40 -- location records alone cannot establish the count
	local members = a:BuildPlayerLocationClusterTooltipMembers(rows)
	Equal(MemberNames(members), "A,C,B")
	Equal(members[1].partySize, 40)
	Equal(members[2].partySize, 40)
	Equal(members[3].partySize, nil)
	members = a:BuildPlayerLocationClusterTooltipMembers(rows, 3, 3)
	Equal(#members, 1)
	Equal(members[1].partyKey, "Raid:1")
	Equal(members[1].partySize, 40)
	a.visuals.C = { key = "Party:2", size = 5 }
	members = a:BuildPlayerLocationClusterTooltipMembers(rows, 3, 3)
	Equal(members[1].partySize, 5)
	a.visuals.C = nil
	Equal(a:BuildPlayerLocationClusterTooltipMembers(rows, 3, 3)[1].partySize, nil)
	Equal(rows[1].partySize, nil)
	Equal(rows[2].partySize, 40)
	Equal(rows[3].partySize, nil)
	Equal(a.networkCalls, 0)
end)

QT:RegisterTest("cluster tooltip grouping bounds source queries and member rendering without mutating input", function()
	local a, rows = TooltipFixture(), {}
	for index = 1, 600 do rows[index] = Row(string.format("Peer%03d", index)) end
	a.visuals.Peer001, a.visuals.Peer512, a.visuals.Peer513 =
		{ key = "Party:1", size = 3 }, { key = "Party:1", size = 3 }, { key = "Party:1", size = 3 }
	local members = a:BuildPlayerLocationClusterTooltipMembers(rows, -10, 1000, 1000)
	Equal(MemberNames(members), "Peer001,Peer512,Peer002,Peer003,Peer004,Peer005")
	Equal(#a.partyQueries, 512)
	Equal(#a.memberBuilds, 6)
	Equal(rows[2].name, "Peer002")
	Equal(rows[512].name, "Peer512")
	a.partyQueries, a.memberBuilds = {}, {}
	Equal(#a:BuildPlayerLocationClusterTooltipMembers(rows, 501, 600, 2), 2)
	Equal(#a.partyQueries, 12)
	Equal(#a.memberBuilds, 2)
	a.partyQueries = {}
	Equal(#a:BuildPlayerLocationClusterTooltipMembers(rows, 513, 600), 0)
	Equal(#a:BuildPlayerLocationClusterTooltipMembers(rows, 4, 3), 0)
	Equal(#a:BuildPlayerLocationClusterTooltipMembers(rows, 1, 6, 0), 0)
	Equal(#a.partyQueries, 0)
	Equal(a.networkCalls, 0)
end)

QT:RegisterTest("cluster tooltip grouping respects shared party query expiry partial revisions and ignores without requests", function()
	local a, rows = TooltipFixture(), { Row("A"), Row("B"), Row("C") }
	a.GetPlayerPartyVisualInfo = QT.GetPlayerPartyVisualInfo
	a.known = { A = true, B = true, C = true }
	function a:IsKnownQTPlayer(name) return self.known[name] == true end
	function a:GetPlayerTooltipStats() return nil end
	function a:GetPlayerPartySize() return nil end
	local peers = a:GetPartyVisualState().peers
	local function Record(revision)
		return { key = "Leader:" .. revision, leader = "Leader", revision = revision,
			size = 2, at = a.now, sampledAt = a.now, lifetime = 1 }
	end
	peers.A, peers.C = Record("1"), Record("1") -- current metadata; no full roster was fetched
	Equal(MemberNames(a:BuildPlayerLocationClusterTooltipMembers(rows)), "A,C,B")
	a.now = 101
	local members = a:BuildPlayerLocationClusterTooltipMembers(rows)
	Equal(MemberNames(members), "A,B,C")
	for _, member in ipairs(members) do Equal(member.partyKey, nil) end
	peers.A, peers.C = Record("2"), Record("1")
	members = a:BuildPlayerLocationClusterTooltipMembers(rows)
	Equal(MemberNames(members), "A,B,C")
	Equal(members[1].partyKey, "Leader:2")
	Equal(members[3].partyKey, "Leader:1")
	a.ignored, a.known.A = "C", nil
	members = a:BuildPlayerLocationClusterTooltipMembers(rows)
	Equal(MemberNames(members), "A,B")
	Equal(members[1].partyKey, nil)
	Equal(a.networkCalls, 0)
end)

QT:RegisterTest("map clusters use projected density deterministic membership and truthful centroids", function()
	local a = Fixture()
	local first, second, third = Row("A", 0.5), Row("B", 0.52), Row("C", 0.8)
	local markers = a:BuildPlayerLocationMapMarkers({ third, second, first }, geometry)
	Equal(#markers, 2)
	Equal(markers[1].row.name, "C") -- preserves admission priority across clusters
	Equal(markers[2].key, "A\nB")
	Near(markers[2].x, 510)
	local reordered = a:BuildPlayerLocationMapMarkers({ first, third, second }, geometry)
	Equal(reordered[1].key, markers[2].key)
	Equal(#reordered[1].members, 2)
	Equal(first.x, 0.5)
	local zoomed = a:BuildPlayerLocationMapMarkers({ first, second, third }, { mapID = 1, width = 2000, height = 1200 })
	Equal(#zoomed, 3)
end)

QT:RegisterTest("map clustering crosses cell edges without chaining distant groups and bounds projection", function()
	local a = Fixture()
	local markers = a:BuildPlayerLocationMapMarkers({ Row("A", 0.023), Row("B", 0.025), Row("C", 0.06), Row("D", 0.08) }, geometry)
	Equal(#markers, 2)
	Equal(markers[1].key, "A\nB")
	Equal(markers[2].key, "C\nD")
	local rows = {}
	for index = 1, 600 do rows[index] = Row(string.format("Peer%03d", index)) end
	a.projections = 0
	markers = a:BuildPlayerLocationMapMarkers(rows, geometry)
	Equal(a.projections, 512)
	Equal(#markers, 1)
	Equal(#markers[1].members, 512)
end)

QT:RegisterTest("cluster hit targets fit viewport edges while tiny maps retain individual dots", function()
	local a = Fixture()
	local markers = a:BuildPlayerLocationMapMarkers({ Row("A", 0.007, 0.013), Row("B", 0.008, 0.013) }, geometry)
	Equal(#markers, 1)
	Near(markers[1].x, 12)
	Near(markers[1].y, 12)
	markers = a:BuildPlayerLocationMapMarkers({ Row("A", 0.992, 0.987), Row("B", 0.993, 0.987) }, geometry)
	Near(markers[1].x, 988)
	Near(markers[1].y, 588)
	markers = a:BuildPlayerLocationMapMarkers({ Row("A"), Row("B") }, { mapID = 1, width = 20, height = 20 })
	Equal(#markers, 2)
	assert(markers[1].row and not markers[1].members)
end)

QT:RegisterTest("selected map player retains exact coordinates outside the containing cluster", function()
	local a = Fixture()
	local markers = a:BuildPlayerLocationMapMarkers({ Row("A"), Row("B", 0.501), Row("C", 0.502) }, geometry, "B")
	Equal(#markers, 2)
	Equal(markers[1].row.name, "B")
	assert(markers[1].selected)
	Near(markers[1].x, 501)
	Equal(markers[2].key, "A\nC")
end)

QT:RegisterTest("find player opens current shared map without changing saved filters or navigation", function()
	local a = Fixture()
	a.rows.Friend = Row("Friend")
	a.options.onlyShowQuestPartners = true
	assert(a:FindPlayerOnMap("Friend"))
	Equal(a.opened, 1)
	Equal(a.refreshes, 1)
	assert(a.options.onlyShowQuestPartners)
	Equal(a:GetSelectedPlayerMapLocation(1), a.rows.Friend)
	a.now = 120
	Equal(a:GetSelectedPlayerMapLocation(1), nil)
	Equal(a.playerMapSelection, nil)
end)

QT:RegisterTest("find player refuses stale hidden ignored party self disabled and restricted locations", function()
	local changes = {
		function(a) a.rows.Friend.mask = 0 end,
		function(a) a.rows.Friend.mask = 2 end,
		function(a) a.now = 700 end,
		function(a) a.ignored = "Friend" end,
		function(a) a.party = "Friend" end,
		function(a) a.options.showPlayerLocations = false end,
		function(a) a.isEnabled = false end,
		function(a) a.blocked = true end,
		function(a) a.isLoggingOut = true end,
	}
	for _, change in ipairs(changes) do
		local a = Fixture()
		a.rows.Friend = Row("Friend")
		change(a)
		local allowed, reason = a:CanFindPlayerOnMap("Friend")
		assert(not allowed and type(reason) == "string")
		assert(not a:FindPlayerOnMap("Friend"))
		assert(a.message and not a.opened and not a.playerMapSelection)
	end
	local a = Fixture()
	a.rows.Me = Row("Me")
	assert(not a:FindPlayerOnMap("Me"))
	a.rows.Friend, a.openFails = Row("Friend"), true
	assert(not a:FindPlayerOnMap("Friend"))
	Equal(a.playerMapSelection, nil)
end)

QT:RegisterTest("temporary map selection retires on map change consent withdrawal party join and restrictions", function()
	local changes = {
		function(a) a.rows.Friend.mask = 0 end,
		function(a) a.rows.Friend = nil end,
		function(a) a.party = "Friend" end,
		function(a) a.ignored = "Friend" end,
		function(a) a.blocked = true end,
		function(a) a.isEnabled = false end,
		function(a) a.rows.Friend.mapID = 2 end,
		function(a) a.options.showPlayerLocations = false end,
	}
	for _, change in ipairs(changes) do
		local a = Fixture()
		a.rows.Friend = Row("Friend")
		assert(a:FindPlayerOnMap("Friend"))
		change(a)
		Equal(a:GetSelectedPlayerMapLocation(1), nil)
		Equal(a.playerMapSelection, nil)
	end
	local a = Fixture()
	a.rows.Friend = Row("Friend")
	assert(a:FindPlayerOnMap("Friend"))
	Equal(a:GetSelectedPlayerMapLocation(2), nil)
end)

QT:RegisterTest("find rechecks location eligibility after native map opening callbacks", function()
	local a = Fixture()
	a.rows.Friend = Row("Friend")
	a.API.OpenPlayerLocationMap = function()
		a.rows.Friend.mask = 0
		return true
	end
	assert(not a:FindPlayerOnMap("Friend"))
	Equal(a.playerMapSelection, nil)
	Equal(a.refreshes, nil)
end)

local function Cluster(a, count, x, y, view)
	local rows = {}
	for index = count, 1, -1 do rows[#rows + 1] = Row(string.format("Peer%03d", index), x, y) end
	local markers = a:BuildPlayerLocationMapMarkers(rows, view or geometry)
	assert(#markers == 1 and markers[1].members)
	return markers[1]
end

local function CheckExpansionLayout(dots, cluster, view, selected)
	assert(#dots <= 12)
	for index, dot in ipairs(dots) do
		assert(dot.expanded and dot.row and dot.key == dot.row.name and dot.clusterKey == cluster.key)
		assert(dot.x >= 10 and dot.y >= 10 and dot.x <= view.width - 10 and dot.y <= view.height - 10)
		assert((dot.x - cluster.x)^2 + (dot.y - cluster.y)^2 >= 24^2 - 0.001)
		if selected then assert((dot.x - selected.x)^2 + (dot.y - selected.y)^2 >= 26^2 - 0.001) end
		for previous = 1, index - 1 do
			assert((dot.x - dots[previous].x)^2 + (dot.y - dots[previous].y)^2 >= 22^2 - 0.001)
		end
		Near(dot.sourceX, dot.row.x * view.width)
		Near(dot.sourceY, dot.row.y * view.height)
	end
end

QT:RegisterTest("expanded cluster dots retain true source positions with bounded alphabetical pages", function()
	local a = Fixture()
	local cluster = Cluster(a, 25)
	local dots, info = a:LayoutPlayerLocationClusterExpansion(cluster, geometry, 1)
	Equal(#dots, 12)
	Equal(info.page, 1)
	Equal(info.pages, 3)
	Equal(info.total, 25)
	Equal(info.first, 1)
	Equal(info.last, 12)
	Equal(dots[1].row.name, "Peer001")
	Equal(dots[12].row.name, "Peer012")
	CheckExpansionLayout(dots, cluster, geometry)
	local beforeX, beforeY = cluster.members[1].x, cluster.members[1].y
	dots, info = a:LayoutPlayerLocationClusterExpansion(cluster, geometry, 2)
	Equal(dots[1].row.name, "Peer013")
	Equal(dots[12].row.name, "Peer024")
	dots, info = a:LayoutPlayerLocationClusterExpansion(cluster, geometry, 999)
	Equal(info.page, 3)
	Equal(info.first, 25)
	Equal(#dots, 1)
	Equal(dots[1].row.name, "Peer025")
	Near(cluster.members[1].x, beforeX)
	Near(cluster.members[1].y, beforeY)
	dots, info = a:LayoutPlayerLocationClusterExpansion(cluster, geometry, -10)
	Equal(info.page, 1)
	Equal(#dots, 12)
end)

QT:RegisterTest("cluster expansion stays separated and inside all four viewport corners", function()
	local a = Fixture()
	for _, xy in ipairs({ { 0.012, 0.02 }, { 0.988, 0.02 }, { 0.012, 0.98 }, { 0.988, 0.98 } }) do
		local cluster = Cluster(a, 25, xy[1], xy[2])
		local dots = a:LayoutPlayerLocationClusterExpansion(cluster, geometry, 1)
		Equal(#dots, 12)
		CheckExpansionLayout(dots, cluster, geometry)
	end
end)

QT:RegisterTest("small viewports reduce cluster page capacity without overlapping or clipping dots", function()
	local a = Fixture()
	local view = { mapID = 1, width = 80, height = 80 }
	local cluster = Cluster(a, 25, 0.5, 0.5, view)
	local dots, info = a:LayoutPlayerLocationClusterExpansion(cluster, view, 1)
	assert(#dots > 0 and #dots < 12)
	Equal(info.pageSize, #dots)
	Equal(info.pages, math.ceil(25 / #dots))
	CheckExpansionLayout(dots, cluster, view)
	local tiny = { mapID = 1, width = 22, height = 22 }
	dots, info = a:LayoutPlayerLocationClusterExpansion(cluster, tiny, 1)
	Equal(#dots, 0)
	Equal(info.page, 0)
	assert(not a:TogglePlayerLocationClusterExpansion(cluster, tiny))
end)

QT:RegisterTest("expanded clusters avoid the separate selected player and retain its identity", function()
	local a = Fixture()
	local cluster = Cluster(a, 30)
	local selected = { row = Row("Selected"), x = 500, y = 252, key = "Selected", selected = true }
	assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
	local dots, current, info = a:GetPlayerLocationClusterExpansion({ selected, cluster }, geometry)
	Equal(current, cluster)
	Equal(#dots, 12)
	Equal(info.total, 30)
	CheckExpansionLayout(dots, cluster, geometry, selected)
	Near(selected.x, 500)
	Near(selected.y, 252)
	assert(selected.selected)
end)

QT:RegisterTest("one active cluster toggles collapses pages and supplies fresh expansion tokens", function()
	local a = Fixture()
	local cluster = Cluster(a, 25)
	assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
	local dots, current, info = a:GetPlayerLocationClusterExpansion({ cluster }, geometry)
	Equal(current, cluster)
	local token = info.token
	assert(token and token == a.playerLocationClusterExpansion)
	assert(a:ChangePlayerLocationClusterPage(cluster, geometry, 1))
	dots, _, info = a:GetPlayerLocationClusterExpansion({ cluster }, geometry)
	Equal(info.page, 2)
	Equal(info.token, token)
	Equal(dots[1].row.name, "Peer013")
	assert(a:ChangePlayerLocationClusterPage(cluster, geometry, 20))
	dots, _, info = a:GetPlayerLocationClusterExpansion({ cluster }, geometry)
	Equal(info.page, 3)
	Equal(#dots, 1)
	assert(not a:ChangePlayerLocationClusterPage(cluster, geometry, 1))
	assert(not a:TogglePlayerLocationClusterExpansion(cluster, geometry))
	Equal(a:GetPlayerLocationClusterExpansion({ cluster }, geometry), nil)
	assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
	local _, _, reopened = a:GetPlayerLocationClusterExpansion({ cluster }, geometry)
	assert(reopened.token ~= token)
	Equal(reopened.page, 1)
	local other = Cluster(a, 26, 0.8, 0.5)
	assert(a:TogglePlayerLocationClusterExpansion(other, geometry))
	local _, active = a:GetPlayerLocationClusterExpansion({ cluster, other }, geometry)
	Equal(active, other)
end)

QT:RegisterTest("cluster expansion clears on exact membership change instead of retaining withdrawn players", function()
	local a = Fixture()
	local cluster = Cluster(a, 25)
	assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
	a:ChangePlayerLocationClusterPage(cluster, geometry, 2)
	local remaining = {}
	for index = 1, 24 do remaining[index] = cluster.members[index] end
	local markers = a:BuildPlayerLocationMapMarkers(remaining, geometry)
	Equal(a:GetPlayerLocationClusterExpansion(markers, geometry), nil)
	Equal(a.playerLocationClusterExpansion, nil)
	assert(a:TogglePlayerLocationClusterExpansion(markers[1], geometry))
	local dots, _, info = a:GetPlayerLocationClusterExpansion(markers, geometry)
	Equal(info.page, 1)
	Equal(info.total, 24)
	for _, dot in ipairs(dots) do assert(dot.row.name ~= "Peer025") end
	Equal(a:GetPlayerLocationClusterExpansion({}, geometry), nil)
end)

QT:RegisterTest("cluster expansion rows always come from current admitted observations", function()
	local a = Fixture()
	local old = Cluster(a, 3)
	assert(a:TogglePlayerLocationClusterExpansion(old, geometry))
	local updated = Cluster(a, 3, 0.501, 0.5)
	local dots, current = a:GetPlayerLocationClusterExpansion({ updated }, geometry)
	Equal(current, updated)
	Equal(dots[1].row, updated.members[1])
	assert(dots[1].row ~= old.members[1])
	Near(dots[1].sourceX, 501)
	assert(a.playerLocationClusterExpansion.members == nil)
end)

QT:RegisterTest("cluster expansion retires on map geometry identity pan zoom and viewport changes", function()
	local a = Fixture()
	local cluster = Cluster(a, 3)
	for _, field in ipairs({ "mapID", "width", "height", "canvasLeft", "canvasTop", "canvasWidth", "canvasHeight", "parent" }) do
		local view = {}
		for key, value in pairs(geometry) do view[key] = value end
		assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
		view[field] = field == "parent" and {} or (view[field] or 0) + 1
		Equal(a:GetPlayerLocationClusterExpansion({ cluster }, view), nil)
		Equal(a.playerLocationClusterExpansion, nil)
	end
end)

QT:RegisterTest("cluster expansion cannot survive visibility opt out restrictions disable or logout", function()
	local mutations = {
		function(a) a.options.showPlayerLocations = false end,
		function(a) a.options.clusterPlayerLocations = false end,
		function(a) a.isEnabled = false end,
		function(a) a.blocked = true end,
		function(a) a.isLoggingOut = true end,
	}
	for _, mutate in ipairs(mutations) do
		local a = Fixture()
		local cluster = Cluster(a, 3)
		assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
		mutate(a)
		Equal(a:GetPlayerLocationClusterExpansion({ cluster }, geometry), nil)
		assert(not a:TogglePlayerLocationClusterExpansion(cluster, geometry))
		Equal(a.playerLocationClusterExpansion, nil)
	end
end)

QT:RegisterTest("find player retires active cluster expansion even when the requested location is unavailable", function()
	local a = Fixture()
	local cluster = Cluster(a, 3)
	assert(a:TogglePlayerLocationClusterExpansion(cluster, geometry))
	assert(not a:FindPlayerOnMap("Absent"))
	Equal(a.playerLocationClusterExpansion, nil)
end)

QT:RegisterTest("optional world map clustering defaults on and disabling restores individual selected dots", function()
	local a = Fixture()
	local rows = { Row("A"), Row("B", 0.501), Row("C", 0.502) }
	local markers = a:GetPlayerLocationMapMarkers(rows, geometry, 128)
	Equal(#markers, 1)
	Equal(#markers[1].members, 3)
	assert(a:TogglePlayerLocationClusterExpansion(markers[1], geometry))
	a.rows.B = rows[2]
	a.playerMapSelection = { name = "B", mapID = 1, expires = 120 }
	a.options.clusterPlayerLocations = false
	markers = a:GetPlayerLocationMapMarkers(rows, geometry, 128)
	Equal(#markers, 3)
	Equal(markers[1].row.name, "B")
	assert(markers[1].selected)
	Near(markers[1].x, 501)
	Equal(a.playerLocationClusterExpansion, nil)
	for _, marker in ipairs(markers) do assert(marker.row and not marker.members) end
	a.options.clusterPlayerLocations = true
	markers = a:GetPlayerLocationMapMarkers(rows, geometry, 128)
	Equal(#markers, 2)
	assert(markers[1].selected and #markers[2].members == 2)
end)
