-- A partially loaded companion must never be mistaken for a successful test run.
local QT = assert(_G.QuestTogether)
assert(QT.testSuiteLoading and type(QT.tests) == "table" and #QT.tests > 0)
assert(type(QT.GetDebugTestOptions) == "function")
assert(type(QT.LibChev.SelfTests) == "function" and QT.testSuiteCompletedModules["Tests.lua"])
assert(QT.testSuiteCompletedModuleCount == QT.testSuiteExpectedModules,
	"QuestTogether test companion did not complete every declared module")
QT.testSuiteLoading = nil
QT.testSuiteLoaded = true
