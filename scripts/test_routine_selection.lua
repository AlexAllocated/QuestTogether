local selectRoutine = assert(loadfile("scripts/routine_selection.lua"))()
local LibChev = assert(loadfile("Libs/libchev/libchev.lua"))()
local cases = {
	{ name = "mesh public discovery covers a population beyond direct neighbors with authenticated relays", offline = true },
	{ name = "network v3 completes party logs and a diagnostic report while movement remains active", offline = true },
	{ name = "mesh two hundred simultaneous clients retain bounded progressive discovery", offline = true },
}
for i = 1, 17 do cases[#cases + 1] = { name = "case " .. i, offline = i % 2 == 0, fn = function() end } end
local unbatched, expected, total = selectRoutine(cases)
assert(expected == 17 and total == 17)
for count = 1, 3 do
	local covered, sum = {}, 0
	for index = 1, count do
		local include, size, all = selectRoutine(cases, tostring(index), tostring(count))
		assert(all == 17)
		local run = LibChev.NewTestRun(cases, { include = include })
		assert(run.result.total == size, "real runner snapshot changed assigned coverage")
		sum = sum + size
		local observed = 0
		for _, case in ipairs(cases) do
			local snapshot = {}
			for key, value in pairs(case) do snapshot[key] = value end
			assert(include(snapshot) == include(case), "runner snapshot changed batch selection")
			if include(case) then
				assert(unbatched(case) and not covered[case], "duplicate or excluded case")
				covered[case] = true
				observed = observed + 1
			end
		end
		assert(observed == size)
		assert(include({ name = "nested fixture", offline = true }), "nested registry must retain its own filter")
		assert(include({ name = cases[4].name, fn = function() end }), "nested body must retain its own filter")
	end
	assert(sum == expected)
	for _, case in ipairs(cases) do assert((covered[case] == true) == unbatched(case), "missing case") end
end
for _, args in ipairs({ { 0, 3 }, { 4, 3 }, { 1, 4 }, { 1.5, 3 }, { 1, 0 }, { "bad", 3 }, { 1 }, { false, 3 } }) do
	assert(not pcall(selectRoutine, cases, args[1], args[2]), "invalid batch accepted")
end
cases[1].offline = false
assert(not pcall(selectRoutine, cases))
cases[1].offline = true
table.remove(cases, 1)
assert(not pcall(selectRoutine, cases), "missing stress scenario accepted")
print("Routine batches cover every retained case exactly once, preserve nested selection and reject invalid plans.")
