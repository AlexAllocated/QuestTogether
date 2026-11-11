-- Offline only. Exercise actual startup and native on-demand loading contracts.
local root = arg[1] or "."
local f = assert(io.open(root .. "/scripts/test.lua"))
local source = f:read("*a"); f:close()
assert((loadstring or load)(assert(source:match("^(.-)local clientChecks ="))))()

local metadata = {}
for _, name in ipairs({ "QuestTogether", "QuestTogether_Tests" }) do
	metadata[name] = {}
	for line in io.lines(root .. "/" .. name .. ".toc") do
		local key, value = line:match("^## ([^:]+):%s*(.-)%s*$")
		if key then metadata[name][key] = value end
	end
end
local expectedModules = assert(tonumber(metadata.QuestTogether_Tests["X-QT-TestModules"]))

local function LoadManifest(name, failure)
	local ns, errors = {}, {}
	for line in io.lines(root .. "/" .. name .. ".toc") do
		local path = line:match("^%s*(.-)%s*$")
		if path:match("%.lua$") then
			local chunk, err = loadfile(root .. "/" .. path)
			if path == "scripts/regression_keybindings.lua" then
				if failure == "missingModule" then chunk, err = nil, "injected missing file"
				elseif failure == "chunkError" then chunk = function() error("injected module error") end end
			end
			-- Native loading reports a Lua error and can continue with later TOC
			-- files. The final marker alone cannot certify those earlier chunks.
			local ok, reason = false, err
			if chunk then ok, reason = pcall(chunk, name, ns) end
			if not ok then
				if not failure then error(reason, 0) end
				errors[#errors + 1] = { path = path, reason = reason }
			end
		end
	end
	return errors
end

local function ColdStart(legacy)
	QuestTogether, QuestTogetherDB, C_AddOns, LoadAddOn, GetAddOnMetadata = nil, nil, nil, nil, nil
	LoadManifest("QuestTogether")
	local q = QuestTogether
	assert(q.tests == nil and q.CreateTestAddon == nil and q.LibChev.SelfTests == nil,
		"ordinary startup must not compile or register tests")
	q:InitializeDatabase()
	q:EnsureRuntimeStateStore()
	q.isInitialized = true
	local control = { mode = "missing", calls = 0, restricted = false }
	q.IsRuntimeRestricted = function() return control.restricted end
	q.Print = function() end
	local function GetMetadata(name, field)
		if field == "Version" then
			if control.mode == "missingVersion" then return nil end
			if name == "QuestTogether_Tests" and control.mode == "mismatch" then return "0.0.0" end
		end
		return metadata[name] and metadata[name][field]
	end
	local function Load(name)
		assert(name == "QuestTogether_Tests")
		control.calls = control.calls + 1
		if control.mode == "missing" then return false, "MISSING" end
		if control.mode == "error" then error("native refused") end
		if control.mode == "partial" or control.nativeLoaded then return true end
		control.errors = LoadManifest(name,
			(control.mode == "chunkError" or control.mode == "missingModule") and control.mode or nil)
		-- An addon already marked loaded does not rerun its TOC on another call,
		-- even when individual chunks failed. Recovery requires a fresh UI load.
		control.nativeLoaded = true
		return true
	end
	if legacy then
		GetAddOnMetadata, LoadAddOn = GetMetadata, Load
	else
		C_AddOns = { GetAddOnMetadata = GetMetadata, LoadAddOn = Load }
	end
	return q, control
end

local q, control = ColdStart()
for _, failure in ipairs({ "missing", "error", "partial", "mismatch", "missingVersion" }) do
	control.mode = failure
	local before = control.calls
	local ok = pcall(q.EnsureTestSuiteLoaded, q)
	assert(not ok and not q.testSuiteLoaded, failure .. " must not report ready")
	assert(control.calls == before + ((failure == "mismatch" or failure == "missingVersion") and 0 or 1))
end
local before = control.calls
control.restricted = true
assert(not pcall(q.EnsureTestSuiteLoaded, q) and control.calls == before,
	"restricted UI must not try native addon loading")

for _, failure in ipairs({ "chunkError", "missingModule" }) do
	q, control = ColdStart()
	control.mode = failure
	assert(not pcall(q.EnsureTestSuiteLoaded, q) and not q.testSuiteLoaded,
		"later chunks must not certify an earlier module failure: " .. failure)
	assert(q.testSuiteCompletedModuleCount == expectedModules - 1)
	assert(not q.testSuiteCompletedModules["scripts/regression_keybindings.lua"])
	assert(#control.errors == 2 and control.errors[2].path == "scripts/test_complete.lua",
		"the completion marker must reject the incomplete inventory")
	local success, passed, failed, result = q:RunTests(false, false)
	assert(not success and passed == 0 and failed == 1 and result.status == "aborted",
		"an incomplete companion must not report an empty or partial success")
	assert(not pcall(q.RecordTestModule, q, "Tests.lua"), "duplicate module completion must fail")
end

local registered
for _, legacy in ipairs({ false, true }) do
	q, control = ColdStart(legacy)
	control.mode = "success"
	assert(q:EnsureTestSuiteLoaded() and #q.tests > 1000 and q.LibChev.SelfTests,
		"explicit test request must register the complete companion with the private library")
	assert(q.testSuiteCompletedModuleCount == expectedModules)
	registered = #q.tests
	local tests = q.tests
	before = control.calls
	assert(q:EnsureTestSuiteLoaded() and control.calls == before and q.tests == tests,
		"repeat commands must not load or register a second time")
	assert(not pcall(q.RecordTestModule, q, "late.lua"), "completion outside loading must fail")
end
print("On-demand startup, failures, module completeness, restrictions and modern/legacy loading passed ("
	.. registered .. " cases across " .. expectedModules .. " modules).")
