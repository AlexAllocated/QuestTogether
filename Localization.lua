-- Translate addon-owned presentation only. Received event facts may be rendered
-- locally; identifiers, original wire text and native data remain unchanged.
local _, namespace = ...
namespace.localizations = {}
local aliases = { enGB = "enUS" }
local ok, locale = pcall(function() return GetLocale and GetLocale() or "enUS" end)
namespace.locale = ok and type(locale) == "string" and (aliases[locale] or locale) or "enUS"
function namespace.TranslateForLocale(text, selected)
	if type(text) ~= "string" then return text end
	local dictionary = namespace.localizations[aliases[selected] or selected]
	return dictionary and dictionary[text] or text
end

function namespace.Translate(text)
	return namespace.TranslateForLocale(text, namespace.localizationTestLocale or namespace.locale)
end
