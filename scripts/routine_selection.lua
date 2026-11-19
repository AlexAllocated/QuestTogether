-- Offline-only test selection. Production and the live test companion never load this file.
local stress = {
	["mesh public discovery covers a population beyond direct neighbors with authenticated relays"] = true,
	["network v3 completes party logs and a diagnostic report while movement remains active"] = true,
	["mesh two hundred simultaneous clients retain bounded progressive discovery"] = true,
}

return function(cases, index, count)
	if index == nil and count == nil then index, count = 1, 1 end
	index, count = tonumber(index), tonumber(count)
	assert(index and count and index % 1 == 0 and count % 1 == 0
		and count >= 1 and count <= 3 and index >= 1 and index <= count, "invalid routine batch")
	local selected, names, found, total, expected = {}, {}, 0, 0, 0
	for _, case in ipairs(cases) do
		assert(not names[case.name], "duplicate routine test: " .. case.name)
		names[case.name] = true
		if stress[case.name] then
			assert(case.offline == true, "a stress selection must not remove a live regression")
			found = found + 1
			selected[case.name] = { fn = case.fn, include = false }
		else
			total = total + 1
			local include = (total - 1) % count + 1 == index
			selected[case.name] = { fn = case.fn, include = include }
			if include then expected = expected + 1 end
		end
	end
	assert(found == 3, "update routine coverage when a stress scenario changes")
	assert(expected > 0, "routine batch must contain tests")
	return function(case)
		-- Nested runner fixtures own a different registry. Their existing live/
		-- offline filter must run unchanged instead of inheriting this partition.
		-- libchev snapshots descriptors before selection; table identity changes.
		local entry = selected[case.name]
		if entry and entry.fn == case.fn then return entry.include end
		return true
	end, expected, total, index, count
end
