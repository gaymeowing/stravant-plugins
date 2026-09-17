-- OCALE entrypoint: `rocale-cli run --script scripts/test/ocale.luau ...`
_G.__ROACT_17_MOCK_SCHEDULER__ = true

local ServerScriptService = game:GetService("ServerScriptService")

local pluginFolder = ServerScriptService:WaitForChild("Plugin")
local TestRunner = require(pluginFolder:WaitForChild("TestRunner"))

local settingsStore: { [string]: any } = {}

local mockPlugin = {
	GetSetting = function(_self: any, key: string): any
		return settingsStore[key]
	end,
	SetSetting = function(_self: any, key: string, value: any)
		settingsStore[key] = value
	end,
	GetMouse = function(_self: any): any
		return nil
	end,
} :: any

local filter = _G.TEST_FILTER
if type(filter) ~= "string" or filter == "" then
	filter = "all"
end

local summary = TestRunner.run(pluginFolder.Src, mockPlugin :: Plugin, filter, {
	screenshot = function(_name: string?) end,
	onOutput = function(message: string)
		print(message)
	end,
	onResult = function(result)
		if result.status == "pass" then
			print(`PASS  {result.name} ({result.duration}ms)`)
		else
			print(`FAIL  {result.name}`)
			if result.error then
				print(`      {result.error}`)
			end
		end
	end,
})

print(`Results: {summary.passed} passed, {summary.failed} failed, {summary.total} total`)
if summary.failed > 0 then
	error(`{summary.failed} test(s) failed`)
end
