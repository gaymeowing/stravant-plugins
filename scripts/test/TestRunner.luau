export type ExpectResult = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
}

export type TestContext = {
	test: (name: string, fn: () -> ()) -> (),
	expect: (value: any) -> ExpectResult,
	fail: (message: string) -> (),
	screenshot: (name: string?) -> (),
	plugin: Plugin,
}

export type RunHooks = {
	screenshot: ((name: string?) -> ())?,
	onSection: ((kind: "plugin" | "suite", name: string) -> ())?,
	onResult: ((result: {
		name: string,
		status: "pass" | "fail",
		error: string?,
		duration: number,
	}) -> ())?,
}

export type PluginSummary = {
	name: string,
	passed: number,
	failed: number,
	total: number,
}

export type RunSummary = {
	passed: number,
	failed: number,
	total: number,
	plugins: { PluginSummary },
}

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function createExpect(value: any): ExpectResult
	return {
		toBe = function(expected: any)
			if value ~= expected then
				error(`Expected {tostring(expected)}, got {tostring(value)}`, 2)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(value, expected) then
				error("Expected values to be deeply equal", 2)
			end
		end,
		toBeTruthy = function()
			if not value then
				error(`Expected truthy value, got {tostring(value)}`, 2)
			end
		end,
		toBeFalsy = function()
			if value then
				error(`Expected falsy value, got {tostring(value)}`, 2)
			end
		end,
	}
end

local function callWithTrace(fn: () -> ...any): (boolean, ...any)
	return xpcall(fn, function(err)
		return debug.traceback(tostring(err), 2)
	end)
end

local function resolveModuleName(src: Instance, testModule: ModuleScript): string
	local parts = {}
	local current: Instance? = testModule
	while current ~= nil and current ~= src do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	local fileName = parts[#parts] or testModule.Name
	return if string.sub(fileName, -5) == ".spec" then string.sub(fileName, 1, -6) else fileName
end

local function isUnderPluginGui(src: Instance, testModule: ModuleScript): boolean
	local current: Instance? = testModule.Parent
	while current ~= nil and current ~= src do
		if current.Name == "PluginGui" then
			return true
		end
		current = current.Parent
	end
	return false
end

local function collectPluginSources(root: Instance): { { name: string, src: Instance } }
	local pluginSources = {}
	for _, child in root:GetChildren() do
		if child.Name == "Loader" or child.Name == "TestRunner" or child.Name == "Packages" then
			continue
		end
		table.insert(pluginSources, {
			name = child.Name,
			src = child,
		})
	end
	table.sort(pluginSources, function(a, b)
		return a.name < b.name
	end)
	return pluginSources
end

local function run(root: Instance, pluginInstance: Plugin, filter: string, hooks: RunHooks?): RunSummary
	local screenshot = if hooks then hooks.screenshot else nil
	local onSection = if hooks then hooks.onSection else nil
	local onResult = if hooks then hooks.onResult else nil

	local passed = 0
	local failed = 0
	local total = 0
	local currentPlugin: string? = nil
	local pluginOrder: { string } = {}
	local pluginStats: { [string]: { passed: number, failed: number, total: number } } = {}

	local function emitPlugin(pluginName: string)
		if pluginName == currentPlugin then
			return
		end
		currentPlugin = pluginName
		if onSection then
			onSection("plugin", pluginName)
		end
	end

	local function emitSuite(suiteName: string)
		if onSection then
			onSection("suite", suiteName)
		end
	end

	local function record(pluginName: string, name: string, status: "pass" | "fail", duration: number, err: string?)
		local stats = pluginStats[pluginName]
		if not stats then
			stats = { passed = 0, failed = 0, total = 0 }
			pluginStats[pluginName] = stats
			table.insert(pluginOrder, pluginName)
		end

		stats.total += 1
		total += 1
		if status == "pass" then
			stats.passed += 1
			passed += 1
		else
			stats.failed += 1
			failed += 1
		end

		if onResult then
			onResult({
				name = name,
				status = status,
				error = err,
				duration = duration,
			})
		end
	end

	for _, pluginSource in collectPluginSources(root) do
		local pluginName = pluginSource.name
		local src = pluginSource.src
		local testModules = src:QueryDescendants("ModuleScript")
		table.sort(testModules, function(a, b)
			return a:GetFullName() < b:GetFullName()
		end)

		for _, testModule in testModules do
			if isUnderPluginGui(src, testModule) or string.sub(testModule.Name, -5) ~= ".spec" then
				continue
			end

			local moduleName = resolveModuleName(src, testModule)

			local ok, testFn = callWithTrace(function()
				return (require)(testModule)
			end)
			if not ok then
				emitPlugin(pluginName)
				emitSuite(moduleName)
				record(pluginName, "(load)", "fail", 0, tostring(testFn))
				continue
			end

			if type(testFn) ~= "function" then
				emitPlugin(pluginName)
				emitSuite(moduleName)
				record(pluginName, "(load)", "fail", 0, "Test module did not return a function")
				continue
			end

			local tests: { { name: string, fn: () -> () } } = {}
			local t: TestContext = {
				test = function(name: string, fn: () -> ())
					table.insert(tests, { name = name, fn = fn })
				end,
				expect = createExpect,
				fail = function(message: string)
					error(message, 2)
				end,
				screenshot = function(name: string?)
					if screenshot then
						screenshot(name)
					end
				end,
				plugin = pluginInstance,
			}

			local registerOk, registerErr = callWithTrace(function()
				testFn(t)
				return true
			end)
			if not registerOk then
				emitPlugin(pluginName)
				emitSuite(moduleName)
				record(pluginName, "(register)", "fail", 0, tostring(registerErr))
				continue
			end

			local matched: { { name: string, fn: () -> () } } = {}
			for _, testEntry in tests do
				local fullName = moduleName .. " > " .. testEntry.name
				if filter == "all" or string.find(fullName, filter, 1, true) then
					table.insert(matched, testEntry)
				end
			end
			if #matched == 0 then
				continue
			end

			emitPlugin(pluginName)
			emitSuite(moduleName)

			for _, testEntry in matched do
				local startTime = os.clock()
				local runOk, runErr = callWithTrace(function()
					testEntry.fn()
					return true
				end)
				local duration = math.round((os.clock() - startTime) * 1000)

				if runOk then
					record(pluginName, testEntry.name, "pass", duration, nil)
				else
					record(pluginName, testEntry.name, "fail", duration, tostring(runErr))
				end
			end
		end
	end

	local plugins: { PluginSummary } = {}
	for _, name in pluginOrder do
		local stats = pluginStats[name]
		table.insert(plugins, {
			name = name,
			passed = stats.passed,
			failed = stats.failed,
			total = stats.total,
		})
	end

	return {
		passed = passed,
		failed = failed,
		total = total,
		plugins = plugins,
	}
end
return {
	run = run,
	createExpect = createExpect,
}
