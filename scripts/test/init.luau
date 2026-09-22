local process = require("@std/process")
local fs = require("@std/fs")
local json = require("@std/json")
local task = require("@std/task")
local server = require("@lute/net/server")
local richterm = require("@batteries/richterm")

local PORT = 38741
local CONNECT_TIMEOUT = 30
local RUN_TIMEOUT = 120

local pluginNames = {}
for _, entry in fs.listDirectory("plugins") do
	table.insert(pluginNames, entry.name)
end

local function findPluginName(name: string): string?
	local needle = string.lower(name)
	for _, pluginName in pluginNames do
		if string.lower(pluginName) == needle then
			return pluginName
		end
	end
	return nil
end

local function hasTests(pluginName: string): boolean
	local function hasSpecIn(dir: string): boolean
		for _, entry in fs.listDirectory(dir) do
			if entry.type == "file" and string.sub(entry.name, -10) == ".spec.luau" then
				return true
			elseif entry.type == "dir" and string.sub(entry.name, 1, 1) ~= "." then
				if hasSpecIn(`{dir}/{entry.name}`) then
					return true
				end
			end
		end
		return false
	end

	local src = `plugins/{pluginName}/src`
	if not fs.exists(src) then
		return false
	end
	return hasSpecIn(src)
end

local function writeTestProject(pluginName: string)
	fs.writeStringToFile(`plugins/{pluginName}/test.project.json`, json.serialize({
		name = `{pluginName}-runtests`,
		globIgnorePaths = {
			"**/place.project.json",
			"**/benchmarks.project.json",
		},
		tree = {
			["$className"] = "Folder",
			Src = {
				["$path"] = "src",
				PluginGui = {
					["$path"] = "../../libraries/PluginGui",
				},
			},
			Packages = {
				["$path"] = {
					optional = "../../Packages",
				},
			},
			Loader = {
				["$path"] = "../../scripts/test/runtests.server.luau",
			},
			TestRunner = {
				["$path"] = "../../scripts/test/TestRunner.luau",
			},
		},
	}) .. "\n")
end

local args = process.args
local selected: { string } = {}
local seen: { [string]: boolean } = {}

local secondArg = args[2]

if (secondArg and string.lower(secondArg) == "all") or not secondArg then
	selected = pluginNames
else
	for index = 2, #args do
		local arg = args[index]
		local pluginName = findPluginName(arg)

		if not pluginName then
			print(`Unknown plugin: {arg}`)
			process.exit(1)
		else
			if not seen[pluginName] then
				seen[pluginName] = true
				table.insert(selected, pluginName)
			end
		end
	end
end

local filter = "all"

local function runStudio(pluginName: string): boolean
	writeTestProject(pluginName)
	local projectPath = `plugins/{pluginName}/test.project.json`

	local ready = false
	local doneSummary: { passed: number, failed: number, total: number }? = nil
	local studioWebsocket: server.ServerWebSocket? = nil
	local closed = false

	local httpServer = server.serve({
		hostname = "127.0.0.1",
		port = PORT,
		handler = function(request, netServer)
			if netServer:upgrade(request) then
				return nil
			end
			return {
				status = 404,
				body = "expected websocket",
			}
		end,
		websocket = {
			open = function(websocket)
				studioWebsocket = websocket
			end,
			message = function(websocket, rawMessage)
				local text = if type(rawMessage) == "buffer" then buffer.tostring(rawMessage) else rawMessage :: string
				local data = json.deserialize(text)
				if type(data) ~= "table" then
					print(`Bad message from Studio: {text}`)
					return
				end
				local message = data :: { [string]: any }
				local messageType = message.type

				if messageType == "ready" then
					ready = true
					websocket:send(json.serialize({
						type = "run",
						filter = filter,
					}))
				elseif messageType == "output" then
					print(`\t{message.message}`)
				elseif messageType == "result" then
					local name = message.name or "?"
					local status = message.status or "?"
					local duration = tonumber(message.duration) or 0
					if status == "pass" then
						print(`\t{richterm.green("PASS")}\t{name} ({duration}ms)`)
					else
						print(`\t{richterm.red("FAIL")}\t{name}`)
						if message.error then
							print(`\t\t{message.error}`)
						end
					end
				elseif messageType == "screenshot" then
					local name = message.name or "screenshot"
					if message.success then
						print(`\t{richterm.cyan("SCREENSHOT")}\t{name}`)
					else
						print(`\t{richterm.yellow("SCREENSHOT")}\t{name} (failed)`)
					end
				elseif messageType == "done" then
					doneSummary = {
						passed = tonumber(message.passed) or 0,
						failed = tonumber(message.failed) or 0,
						total = tonumber(message.total) or 0,
					}
				end
			end,
			close = function(_websocket, _code, _message)
				closed = true
			end,
		},
	})

	print("Building test runner...")
	local build = process.run({ "rojo", "build", projectPath, "-o", "RunTests.rbxmx" })
	if not build.ok then
		if build.stderr ~= "" then
			print(build.stderr)
		end
		httpServer.close()
		print(`Failed to build {projectPath}`)
		return false
	end
	print("\tDone. Load RunTests.rbxmx in Studio, then open any place.")
	print(`Waiting for Studio on port {PORT}...`)

	local connectDeadline = os.clock() + CONNECT_TIMEOUT
	while not ready and os.clock() < connectDeadline do
		task.wait(0.25)
		if closed and studioWebsocket == nil then
			break
		end
	end

	if not ready then
		httpServer.close()
		print(`Timed out waiting for Studio after {CONNECT_TIMEOUT}s.`)
		return false
	end

	print("Connected!\n\nRunning tests...")
	local runDeadline = os.clock() + RUN_TIMEOUT
	while doneSummary == nil and not closed and os.clock() < runDeadline do
		task.wait(0.25)
	end

	httpServer.close()

	local summary = doneSummary
	if summary == nil then
		if not closed and os.clock() >= runDeadline then
			print(`\nTimed out waiting for test results after {RUN_TIMEOUT}s.`)
		else
			print("\nConnection to Studio lost before results.")
		end
		return false
	end

	print("")
	if summary.failed > 0 then
		print(
			`Results: {richterm.green(`{summary.passed} passed`)}, {richterm.red(`{summary.failed} failed`)}, {summary.total} total`
		)
		return false
	end
	print(`Results: {richterm.green(`{summary.passed} passed`)}, {summary.total} total`)
	return true
end

local function runOne(pluginName: string): boolean
	if not hasTests(pluginName) then
		print(`Skipping {pluginName} (no *.spec.luau).`)
		return true
	end
	return runStudio(pluginName)
end

local ok = true
for _, pluginName in selected do
	if not runOne(pluginName) then
		ok = false
	end
end

process.exit(if ok then 0 else 1)
