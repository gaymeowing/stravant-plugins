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
	onOutput: ((message: string) -> ())?,
	onResult: ((result: {
		name: string,
		status: "pass" | "fail",
		error: string?,
		duration: number,
	}) -> ())?,
}

export type RunSummary = {
	passed: number,
	failed: number,
	total: number,
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

local function run(src: Instance, pluginInstance: Plugin, filter: string, hooks: RunHooks?): RunSummary
	local screenshot = if hooks then hooks.screenshot else nil
	local onOutput = if hooks then hooks.onOutput else nil
	local onResult = if hooks then hooks.onResult else nil

	local passed = 0
	local failed = 0
	local total = 0

	local function emitResult(name: string, status: "pass" | "fail", duration: number, err: string?)
		if onResult then
			onResult({
				name = name,
				status = status,
				error = err,
				duration = duration,
			})
		end
	end

	local testModules = src:QueryDescendants("ModuleScript")
	for _, testModule in testModules do
		local moduleName = testModule.Name
		if string.sub(moduleName, -5) == ".spec" then
			moduleName = string.sub(moduleName, 1, -6)
		else
			continue
		end

		local ok, testFn = pcall(require, testModule)
		if not ok then
			failed += 1
			total += 1
			emitResult(moduleName .. " (load)", "fail", 0, tostring(testFn))
			continue
		end

		if type(testFn) ~= "function" then
			failed += 1
			total += 1
			emitResult(moduleName .. " (load)", "fail", 0, "Test module did not return a function")
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

		local registerOk, registerErr = pcall(testFn, t)
		if not registerOk then
			failed += 1
			total += 1
			emitResult(moduleName .. " (register)", "fail", 0, tostring(registerErr))
			continue
		end

		for _, testEntry in tests do
			local fullName = moduleName .. " > " .. testEntry.name
			if filter ~= "all" and not string.find(fullName, filter, 1, true) then
				continue
			end

			total += 1
			local startTime = os.clock()
			local runOk, runErr = pcall(testEntry.fn)
			local duration = math.round((os.clock() - startTime) * 1000)

			if runOk then
				passed += 1
				emitResult(fullName, "pass", duration, nil)
			else
				failed += 1
				emitResult(fullName, "fail", duration, tostring(runErr))
			end
		end
	end

	if onOutput then
		onOutput(`Finished: {passed} passed, {failed} failed, {total} total`)
	end

	return {
		passed = passed,
		failed = failed,
		total = total,
	}
end

return {
	run = run,
	createExpect = createExpect,
}
