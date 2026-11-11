-- Loaded only by QuestTogether_Tests. Reuse QT's private pinned utility library;
-- never create a second library instance or put QA definitions in normal startup.
local _, namespace = ...
local QT = assert(_G.QuestTogether, "QuestTogether must load before its test companion")
assert(not QT.testSuiteLoading and not QT.testSuiteLoaded, "QuestTogether test companion already loaded")
local expected = QT:SafeToNumber(namespace.expectedTestModules
	or QT.API.GetAddOnMetadata("QuestTogether_Tests", "X-QT-TestModules"))
assert(expected and expected >= 1 and expected <= 512 and expected == math.floor(expected),
	"QuestTogether test companion has invalid module-count metadata")
QT.testSuiteLoading = true
QT.testSuiteExpectedModules = expected
QT.testSuiteCompletedModules, QT.testSuiteCompletedModuleCount = {}, 0
function QT:RecordTestModule(path)
	assert(self == QT and self.testSuiteLoading == true and self.testSuiteLoaded ~= true,
		"QuestTogether test module completed outside its loading lifetime")
	assert(type(path) == "string" and path ~= "" and not self.testSuiteCompletedModules[path],
		"QuestTogether test module completed twice or has no identity")
	self.testSuiteCompletedModules[path] = true
	self.testSuiteCompletedModuleCount = self.testSuiteCompletedModuleCount + 1
end
namespace.LibChev = assert(QT.LibChev)
