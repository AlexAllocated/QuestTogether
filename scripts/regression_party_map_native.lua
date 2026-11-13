-- Standalone offline boundary checks. Never load this through /qt test: the
-- sandbox substitutes native globals and cannot prove actual WoW taint safety.
local root = arg[1] or "."
local function Harness()
	local h = { calls = {}, errors = {}, hooks = {}, tainted = {}, inaccessible = {}, restricted = false }
	local env = setmetatable({}, { __index = _G })
	env._G = env
	local q = {}; env.QuestTogether = q
	function q:CanAccessValue(value) return not h.inaccessible[value] end
	function q:CanAccessTable(value) return type(value) == "table" and not h.inaccessible[value] end
	function q:CanAccessForeignFrame(frame, shown)
		return type(frame) == "table" and not frame.forbidden and not h.inaccessible[frame]
			and (not shown or frame.shown == true)
	end
	function q:IsRuntimeRestricted() return h.restricted end
	function q:IsWorkBlocked() return h.restricted end
	function q:SafeToNumber(value)
		return not h.inaccessible[value] and type(value) == "number" and value == value and value or nil
	end
	function q:RecordDiagnosticError(kind, reason) h.errors[#h.errors + 1] = { kind, reason } end
	env.issecurevariable = function(object, key)
		return not h.tainted[object] or not h.tainted[object][key]
	end
	env.GetBuildInfo = function() return h.version or "1.60.1", h.build or "70888" end
	env.hooksecurefunc = function(object, key, callback)
		assert(object == h.pin and key == "UpdateShownUnits")
		if h.hookFails then error("hook failure") end
		h.hooks[#h.hooks + 1] = callback
	end
	env.C_Map = { GetMapDisplayInfo = function(id) assert(id == 1455); return h.hideIcons == true end }
	env.UnitPositionFrameUpdateSecureMixin = { SetAppearanceField = function() error("raw mixin invoked") end }
	local canvas = { shown = true }
	function canvas:GetWidth() return h.width or 800 end
	function canvas:GetHeight() return 600 end
	local map = { shown = true }
	function map:IsVisible() return h.visible ~= false end
	function map:GetMapID() return h.mapID or 1455 end
	function map:GetCanvas() return canvas end
	function map:GetCanvasScale() return 2 end
	local provider = { unitPinSizes = { player = 27, party = 11, raid = 8 } }
	local pin = { shown = true, dataProvider = provider }
	function pin:GetMap() return h.foreignMap or map end
	function pin:GetFrameLevel() return h.frameLevel or 103 end
	function pin:SetAppearanceField(category, field, value)
		assert((category == "party" or category == "raid") and field == "shouldShow" and type(value) == "boolean")
		h.calls[#h.calls + 1] = { category, value }
		if h.writeFails == category then error("native write failure") end
	end
	function pin:UpdateShownUnits() error("adapter called insecure native helper") end
	function map:EnumeratePinsByTemplate(template)
		assert(template == "GroupMembersPinTemplate")
		local at = 0
		return function()
			at = at + 1
			if at == 1 and not h.noPin then return pin end
			if at == 2 and h.duplicatePin then return h.duplicatePin end
		end
	end
	function q:GetLocationPinSurface(surface)
		assert(surface == "map")
		return { parent = {}, mapID = 1455, width = 400, height = 300 }
	end
	env.WorldMapFrame = map
	h.qt, h.env, h.pin, h.map, h.provider = q, env, pin, map, provider
	local file = root .. "/PartyMapNative.lua"
	local chunk
	if _VERSION == "Lua 5.1" then chunk = assert(loadfile(file)); setfenv(chunk, env)
	else chunk = assert(loadfile(file, "t", env)) end
	chunk()
	return h
end

for _, build in ipairs({ "70888", 70888, "70938", 70938 }) do
	local h = Harness()
	h.build = build
	local c = assert(h.qt:GetPartyMapNativeContext(), "Audited build refused: " .. tostring(build))
	assert(h.qt:SetPartyMapNativeVisibility(c, false, false))
	assert(h.qt:SetPartyMapNativeVisibility(c, true, true))
	assert(#h.calls == 4 and #h.errors == 0)
end
for _, info in ipairs({ { "1.60.1", "70939" }, { "1.60.2", "70938" }, { "12.0.0", "70938" } }) do
	local h = Harness()
	h.version, h.build = info[1], info[2]
	assert(not h.qt:GetPartyMapNativeContext())
	assert(#h.calls == 0 and #h.hooks == 0 and #h.errors == 0)
end
print("PASS: exact audited builds accept numeric/string identifiers; other versions and builds remain inert")

do
	local h = Harness()
	local c = assert(h.qt:GetPartyMapNativeContext())
	assert(c.pin == h.pin and c.map == h.map and c.parent and c.mapID == 1455)
	assert(c.width == 800 and c.height == 600 and c.canvasScale == 2 and c.showParty and c.showRaid)
	assert(c.frameLevel == 103)
	assert(#h.hooks == 1 and #h.calls == 0)
	assert(h.qt:SetPartyMapNativeVisibility(c, false, false))
	assert(#h.calls == 2 and not h.calls[1][2] and not h.calls[2][2])
	assert(h.qt:SetPartyMapNativeVisibility(c, false, false) and #h.calls == 2)
	local again = assert(h.qt:GetPartyMapNativeContext())
	assert(#h.hooks == 1 and again.nativeRevision == c.nativeRevision)
	h.hooks[1]()
	assert(#h.calls == 2, "native observer must only mark dirty")
	assert(h.qt:GetPartyMapNativeContext().nativeRevision == c.nativeRevision + 1)
	assert(h.qt:SetPartyMapNativeVisibility(c, false, false) and #h.calls == 4)
	assert(h.provider.unitPinSizes.party == 11 and h.provider.unitPinSizes.raid == 8
		and h.provider.unitPinSizes.player == 27, "provider policy was mutated")
end
print("PASS: native context is flat, owned observation is idempotent, and suppression never changes provider/self policy")

do
	local h = Harness()
	local c = assert(h.qt:GetPartyMapNativeContext())
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == true)
	h.mapID = 1415
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == false, "old-map positions remained current")
	h.mapID, h.visible = nil, false
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == false, "inherited UI hiding remained current")
	h.visible, h.map.shown = true, false
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == false, "closed map remained current")
	h.map.shown, h.restricted = true, true
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == false, "restricted context remained current")
	h.restricted, h.pin.forbidden = false, true
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == false, "forbidden native pin remained current")
	h.pin.forbidden = nil
	assert(h.qt:IsPartyMapNativeContextCurrent(c) == true)
	assert(h.qt:IsPartyMapNativeContextCurrent({}) == false)
	assert(h.qt:IsPartyMapNativeContextCurrent(nil) == false)
	assert(#h.calls == 0 and #h.hooks == 1 and #h.errors == 0, "currentness checks had integration side effects")
end
print("PASS: read-only currentness retires old maps, hidden UI, restricted and forbidden contexts with strict boolean results")

do
	local h = Harness()
	local c = assert(h.qt:GetPartyMapNativeContext())
	assert(h.qt:SetPartyMapNativeVisibility(c, false, false))
	h.restricted = true
	assert(not h.qt:GetPartyMapNativeContext())
	assert(not h.qt:SetPartyMapNativeVisibility(c, false, false) and #h.calls == 2)
	assert(h.qt:SetPartyMapNativeVisibility(c, c.showParty, c.showRaid) and #h.calls == 4)
	assert(h.calls[3][2] and h.calls[4][2])
	assert(h.qt:SetPartyMapNativeVisibility(c, true, true) and #h.calls == 4)
	h.foreignMap = {}
	assert(not h.qt:SetPartyMapNativeVisibility(c, true, true) and #h.calls == 4)
end
print("PASS: restricted state permits only captured-policy restoration and refuses reassigned native pins")

for _, scenario in ipairs({ "build", "raw", "tainted", "forbidden", "secret", "missing", "duplicate", "hidden", "size", "level", "live-tests" }) do
	local h = Harness()
	if scenario == "build" then h.build = "70889"
	elseif scenario == "raw" then h.pin.SetAppearanceField = h.env.UnitPositionFrameUpdateSecureMixin.SetAppearanceField
	elseif scenario == "tainted" then h.tainted[h.pin] = { SetAppearanceField = true }
	elseif scenario == "forbidden" then h.pin.forbidden = true
	elseif scenario == "secret" then h.inaccessible[h.provider.unitPinSizes] = true
	elseif scenario == "missing" then h.noPin = true
	elseif scenario == "duplicate" then h.duplicatePin = { shown = true }
	elseif scenario == "hidden" then h.hideIcons = true
	elseif scenario == "size" then h.width = 0
	elseif scenario == "level" then h.frameLevel = 1.5
	else h.qt.isRunningTests = true end
	assert(not h.qt:GetPartyMapNativeContext(), scenario)
	assert(#h.calls == 0 and #h.hooks == 0 and #h.errors == 0, scenario)
end
print("PASS: unsupported, tainted, inaccessible, ambiguous and live-test boundaries leave native markers untouched")

do
	local h = Harness()
	local c = assert(h.qt:GetPartyMapNativeContext())
	h.writeFails = "raid"
	assert(not h.qt:SetPartyMapNativeVisibility(c, false, false))
	assert(h.qt:GetPartyMapNativeStatus().failed and #h.errors == 1)
	assert(#h.calls == 2)
	assert(not h.qt:SetPartyMapNativeVisibility(c, true, true))
	assert(#h.calls == 4 and h.calls[3][1] == "party" and h.calls[3][2], "partial suppression was not restored")
	for _ = 1, 3 do
		assert(not h.qt:GetPartyMapNativeContext())
		assert(not h.qt:SetPartyMapNativeVisibility(c, false, false))
		assert(not h.qt:SetPartyMapNativeVisibility(c, true, true))
	end
	assert(#h.calls == 4, "failed native operation was repeatedly invoked")
	h.writeFails = nil
	assert(not h.qt:SetPartyMapNativeVisibility(c, true, true) and #h.calls == 4,
		"failed delegate must wait for a concrete state change before retry")
	h.restricted = true
	assert(h.qt:SetPartyMapNativeVisibility(c, true, true) and #h.calls == 5,
		"restoration was blocked by the replacement failure latch")
	assert(h.calls[5][1] == "raid" and h.calls[5][2], "successful party restoration was redundantly repeated")
	h.hooks[1]()
	assert(h.qt:SetPartyMapNativeVisibility(c, true, true) and #h.calls == 7,
		"native policy revisions stopped after failure")
	assert(#h.errors == 1)
end
print("PASS: partial writes are restored after failure; repeated failures stop until native policy or restrictions change")

do
	local h = Harness()
	local c = assert(h.qt:GetPartyMapNativeContext())
	assert(h.qt:SetPartyMapNativeVisibility(c, false, false))
	h.writeFails, h.restricted = "party", true
	assert(not h.qt:SetPartyMapNativeVisibility(c, true, true))
	assert(#h.calls == 4 and h.calls[4][1] == "raid" and h.calls[4][2],
		"a failed party restore must not prevent independent raid restoration")
	h.writeFails, h.restricted = nil, false
	assert(h.qt:SetPartyMapNativeVisibility(c, true, true) and #h.calls == 5)
	local forged = { pin = c.pin, map = c.map, showParty = false, showRaid = false }
	h.restricted = true
	assert(not h.qt:SetPartyMapNativeVisibility(forged, false, false) and #h.calls == 5)
	c.showParty, c.showRaid = false, false
	assert(not h.qt:SetPartyMapNativeVisibility(c, false, false) and #h.calls == 5)
end
print("PASS: failed restoration retries after restrictions end, and presentation contexts cannot forge restoration authority")

do
	local h = Harness()
	local c = assert(h.qt:GetPartyMapNativeContext())
	h.tainted[h.pin] = { SetAppearanceField = true }
	assert(not h.qt:SetPartyMapNativeVisibility(c, false, false) and #h.calls == 0)
	h.tainted[h.pin] = nil
	h.pin.forbidden = true
	assert(not h.qt:SetPartyMapNativeVisibility(c, false, false) and #h.calls == 0)
end
print("PASS: every native mutation rechecks provenance and forbidden state")
print("OFFLINE ONLY: native secureMixin and combat/taint behavior still require a live acceptance check")
