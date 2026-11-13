-- Native world-map boundary. This never owns a Blizzard pin, provider table or
-- map-pool registration. Only the authored secure-mixin appearance setter may
-- mutate the native pin, with primitive category/field/boolean arguments.
local QT = _G.QuestTogether
local state = {
	pins = setmetatable({}, { __mode = "k" }),
	contexts = setmetatable({}, { __mode = "k" }),
}

local function Accessible(value)
	return QT:CanAccessValue(value)
end
local function Read(object, key)
	if not Accessible(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return nil end
	if type(object) == "table" and not QT:CanAccessTable(object) then return nil end
	local ok, value = pcall(function() return object[key] end)
	if ok and Accessible(value) then return value end
end
local function Frame(object, shown)
	return Accessible(object) and QT:CanAccessForeignFrame(object, shown) and object or nil
end
local function Method(object, name, ...)
	local method = Read(object, name)
	if type(method) ~= "function" then return false end
	return pcall(method, object, ...)
end
local function Trusted(object, name)
	if not Accessible(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return nil end
	if type(object) == "table" and not QT:CanAccessTable(object) then return nil end
	if not Accessible(issecurevariable) or type(issecurevariable) ~= "function" then return nil end
	local ok, secure = pcall(issecurevariable, object, name)
	if not ok or not Accessible(secure) or secure ~= true then return nil end
	local value = Read(object, name)
	return type(value) == "function" and value or nil
end
local function Restricted()
	return QT:IsRuntimeRestricted() or QT:IsWorkBlocked("foreign_frame_mutation")
end
local function Supported()
	if state.supported ~= nil then return state.supported end
	local buildInfo = Trusted(_G, "GetBuildInfo")
	if not buildInfo then return false end
	local ok, version, build = pcall(buildInfo)
	state.supported = ok and Accessible(version) and Accessible(build)
		and version == "1.60.1"
		-- The group provider, map canvas, unit-position secure delegate and its
		-- XML registration are unchanged in the source-audited 70938 build.
		and (build == "70888" or build == 70888 or build == "70938" or build == 70938)
	return state.supported
end
local function Setter(pin)
	if not Frame(pin) or Trusted(_G, "issecurevariable") ~= issecurevariable then return nil end
	local source = Read(_G, "UnitPositionFrameUpdateSecureMixin")
	local raw = source and Trusted(source, "SetAppearanceField")
	local wrapped = Trusted(pin, "SetAppearanceField")
	-- The raw Lua mixin is not an entrypoint. XML secureMixin installs a
	-- distinct native delegate on each frame; a plain mixin copy is unsupported.
	return raw and wrapped and wrapped ~= raw and wrapped or nil
end
local function Fail(reason)
	if state.failed then return end
	state.failed, state.reason = true, reason
	if QT.RecordDiagnosticError then
		QT:RecordDiagnosticError("party_map_native", reason .. "; replacement suspended; native restoration pending")
	end
end
local function Positive(value)
	local number = QT:SafeToNumber(value)
	return number and number > 0 and number < 1000000 and number or nil
end
local function BooleanSize(provider, category)
	-- ShouldShowUnit calls GetUnitPinSizesTable, which can create native state.
	-- Read only the already-initialized table, then discard it after flattening.
	local sizes = Read(provider, "unitPinSizes")
	local value = sizes and QT:SafeToNumber(Read(sizes, category))
	if not value or value < 0 or value > 10000 then return nil end
	return value > 0
end
local function Observe(pin, setter)
	local record = state.pins[pin]
	if record then return record.setter == setter and record or nil end
	local hook = Trusted(_G, "hooksecurefunc")
	if not hook or not Trusted(pin, "UpdateShownUnits") then return nil end
	record = { setter = setter, revision = 0, applied = {}, failures = {} }
	-- This posthook never mutates native objects, even in combat. The next
	-- existing presentation refresh observes its revision and reapplies policy.
	local ok = pcall(hook, pin, "UpdateShownUnits", function()
		record.revision = record.revision + 1
	end)
	if not ok then Fail("visibility_observer_failed"); return nil end
	state.pins[pin] = record
	return record
end

function QT:GetPartyMapNativeContext()
	if self ~= QT or self.isRunningTests then return nil end
	state.stage = "capability"
	if state.failed or Restricted() or not Supported() then return nil end
	state.stage = "map_visibility"
	local map = Frame(Read(_G, "WorldMapFrame"), true)
	if not map then return nil end
	local okVisible, visible = Method(map, "IsVisible")
	if not okVisible or not Accessible(visible) or visible ~= true then return nil end
	state.stage = "map_geometry"
	local surface = self:GetLocationPinSurface("map")
	if type(surface) ~= "table" then return nil end
	local mapID = self:SafeToNumber(surface.mapID)
	if not mapID or mapID < 1 or mapID % 1 ~= 0 then return nil end
	state.stage = "map_display_policy"
	local displayInfo = Trusted(Read(_G, "C_Map"), "GetMapDisplayInfo")
	if not displayInfo then return nil end
	local okDisplay, hidden = pcall(displayInfo, mapID)
	if not okDisplay or not Accessible(hidden) or type(hidden) ~= "boolean" or hidden then return nil end
	state.stage = "canvas"
	local okCanvas, canvas = Method(map, "GetCanvas")
	if not okCanvas or not Frame(canvas, true) then return nil end
	local okWidth, width = Method(canvas, "GetWidth")
	local okHeight, height = Method(canvas, "GetHeight")
	local okScale, scale = Method(map, "GetCanvasScale")
	width, height, scale = Positive(width), Positive(height), Positive(scale)
	if not okWidth or not okHeight or not okScale or not width or not height or not scale then return nil end
	state.stage = "native_pin"
	local enumerate = Trusted(map, "EnumeratePinsByTemplate")
	if not enumerate then return nil end
	local ok, iterator, iteratorState, previous = pcall(enumerate, map, "GroupMembersPinTemplate")
	if not ok or not Accessible(iterator) or type(iterator) ~= "function"
		or not Accessible(iteratorState) or not Accessible(previous) then return nil end
	if type(iteratorState) == "table" and not self:CanAccessTable(iteratorState) then return nil end
	local pin
	-- The native provider has exactly one permanent pin. A second match or an
	-- invalid iterator refuses takeover instead of hiding an ambiguous surface.
	for _ = 1, 2 do
		local nextOK, candidate = pcall(iterator, iteratorState, previous)
		if not nextOK or not Accessible(candidate) then return nil end
		if candidate == nil then break end
		if pin or not Frame(candidate, true) then return nil end
		pin, previous = candidate, candidate
	end
	if not pin then return nil end
	local okMap, nativeMap = Method(pin, "GetMap")
	if not okMap or not Accessible(nativeMap) or nativeMap ~= map then return nil end
	state.stage = "appearance_delegate"
	local setter = Setter(pin)
	local okLevel, frameLevel = Method(pin, "GetFrameLevel")
	frameLevel = self:SafeToNumber(frameLevel)
	if not okLevel or not frameLevel or frameLevel < 0 or frameLevel > 1000000 or frameLevel % 1 ~= 0 then return nil end
	local provider = Read(pin, "dataProvider")
	local party, raid = BooleanSize(provider, "party"), BooleanSize(provider, "raid")
	if not setter or type(party) ~= "boolean" or type(raid) ~= "boolean" then return nil end
	local record = Observe(pin, setter)
	if not record or Restricted() or not Frame(pin, true) then return nil end
	local context = {
		pin = pin, map = map, parent = canvas, mapID = mapID, width = width, height = height,
		canvasScale = scale, frameLevel = frameLevel, showParty = party, showRaid = raid,
		nativeRevision = record.revision, surface = surface,
	}
	-- Keep restoration authority private, so a modified presentation context
	-- cannot expand the restricted-state operation beyond its captured policy.
	state.contexts[context] = { pin = pin, map = map, party = party, raid = raid }
	state.stage = "ready"
	return context
end

function QT:SetPartyMapNativeVisibility(context, showParty, showRaid)
	if self ~= QT or self.isRunningTests or not state.supported
		or type(context) ~= "table" or type(showParty) ~= "boolean" or type(showRaid) ~= "boolean" then
		return false
	end
	local captured = state.contexts[context]
	if not captured or context.pin ~= captured.pin or context.map ~= captured.map then return false end
	local pin, record = captured.pin, state.pins[captured.pin]
	if not record or not Frame(pin) then return false end
	local restoring = showParty == captured.party and showRaid == captured.raid
	-- The only restricted-state write is restoring the captured native policy.
	-- It crosses the authored secure delegate, not an insecure helper or a
	-- securecallfunction bypass. Callers retain this context until restoration
	-- succeeds even if they have already hidden stale replacement artwork.
	local restricted = Restricted() and true or false
	if (state.failed or restricted) and not restoring then return false end
	local okMap, nativeMap = Method(pin, "GetMap")
	if not okMap or not Accessible(nativeMap) or nativeMap ~= captured.map then return false end
	local setter = Setter(pin)
	if setter ~= record.setter then return false end
	local function Apply(category, value)
		local applied = record.applied[category]
		if applied and applied.value == value and applied.revision == record.revision then return true end
		local failure = record.failures[category]
		-- A failed delegate is not retried on every presentation refresh. A
		-- compensating restore, native policy update, or restriction transition
		-- provides a concrete reason to try again with the same proven delegate.
		if failure and failure.value == value and failure.revision == record.revision
			and failure.restricted == restricted then return false end
		if Setter(pin) ~= setter then Fail("visibility_delegate_changed"); return false end
		local revision = record.revision
		local ok = pcall(setter, pin, category, "shouldShow", value)
		if not ok then
			record.applied[category] = nil -- A throw may follow a partial native write.
			record.failures[category] = { value = value, revision = revision, restricted = restricted }
			Fail(category .. "_visibility_failed")
			return false
		end
		record.applied[category] = { value = value, revision = revision }
		record.failures[category] = nil
		return record.revision == revision
	end
	local okParty = Apply("party", showParty)
	-- On restoration, still restore the other category when the first fails.
	-- On suppression, stop immediately rather than hide additional native dots.
	if not okParty and not restoring then return false end
	local okRaid = Apply("raid", showRaid)
	return okParty and okRaid
end

-- Cheap read-only retirement check for the existing per-frame geometry owner.
-- Never render one map's units on another map while waiting for the paced tick.
function QT:IsPartyMapNativeContextCurrent(context)
	if self ~= QT or self.isRunningTests or Restricted() then return false end
	local captured = state.contexts[context]
	if not captured or not Frame(captured.map, true) or not Frame(captured.pin) then return false end
	local okVisible, visible = Method(captured.map, "IsVisible")
	local okMap, mapID = Method(captured.map, "GetMapID")
	return okVisible and Accessible(visible) and visible == true and okMap
		and self:SafeToNumber(mapID) == context.mapID
end

function QT:GetPartyMapNativeStatus()
	return { supported = state.supported == true, failed = state.failed == true, reason = state.reason, stage = state.stage }
end
