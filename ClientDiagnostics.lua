-- SPDX-License-Identifier: GPL-3.0-only
-- Informational only. Runtime admission never consumes these strings.
local QT = _G.QuestTogether
local Access = QT.NativeAccess
local Accessible = Access.Value
local function BuildDiagnostic(value)
	if not Accessible(value) then
		return "unknown"
	end
	if type(value) == "number" then
		if value ~= value or value < 0 or value > 999999999999 then
			return "unknown"
		end
		value = tostring(value)
	end
	if type(value) ~= "string" or #value > 32 or not value:match("^%d[%d%.]*$") then
		return "unknown"
	end
	return value
end
function QT:GetClientBuildDiagnostics()
	local read = Access.Read(_G, "GetBuildInfo")
	if type(read) ~= "function" then
		return "unknown", "unknown"
	end
	local ok, version, build = pcall(read)
	if ok then
		return BuildDiagnostic(version), BuildDiagnostic(build)
	end
	return "unknown", "unknown"
end
