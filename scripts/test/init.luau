local addBaseGlobIgnorePaths = require("@scripts/baseGlobIgnorePaths")
local richterm = require("@batteries/richterm")
local packages = require("@scripts/packages")
local plugins = require("@scripts/plugins")
local server = require("@lute/net/server")
local process = require("@std/process")
local rojo = require("@scripts/rojo")
local json = require("@std/json")
local task = require("@std/task")
local fs = require("@std/fs")

type PluginSummary = {
	name: string,
	passed: number,
	failed: number,
	total: number,
}

type DoneSummary = {
	passed: number,
	failed: number,
	total: number,
	plugins: { PluginSummary },
}

local PORT = 38741
local CONNECT_TIMEOUT = 30
local RUN_TIMEOUT = 120

local PROJECT_PATH = "test.project.json"
local BUILD_PATH = "RunTests.rbxmx"

local function studioPluginsDir(): string
	local localAppData = process.env.LOCALAPPDATA
	if localAppData ~= nil and localAppData ~= "" then
		return `{localAppData}/Roblox/Plugins`
	end
	return `{process.homedir()}/Documents/Roblox/Plugins`
end

local function installedTestPluginPath(): string
	return `{studioPluginsDir()}/RunTests.rbxmx`
end

local function writeTestProject(names: { string })
	-- Each plugin mounts as RunTests/<Name>/ (src contents), sibling to Packages,
	-- so script.Parent.Parent.Packages and PluginGui's ../../Packages both resolve.
	local project = rojo.project("RunTests")
	addBaseGlobIgnorePaths(project)
	local tree = project.tree
	tree:addScript("Loader", "scripts/test/runtests.server.luau")
	tree:addScript("TestRunner", "scripts/test/TestRunner.luau")
	tree.Packages = packages.tree()

	for _, name in names do
		local pluginNode = tree:addScript(name, `plugins/{name}/src`)
		pluginNode:addScript("PluginGui", "libraries/PluginGui")
	end
	project:write(PROJECT_PATH)
end

local function installTestPlugin()
	local dir = studioPluginsDir()
	if not fs.exists(dir) then
		fs.createDirectory(dir, { makeParents = true })
	end
	local dest = installedTestPluginPath()
	local copied = process.run({ "cp", BUILD_PATH, dest })
	if not copied.ok then
		error(`Failed to install {BUILD_PATH} → {dest}: {copied.stderr}`)
	end
	print(`\tInstalled → {dest}`)
end

local function uninstallTestPlugin()
	local dest = installedTestPluginPath()
	if fs.exists(dest) then
		fs.remove(dest)
		print(`\tRemoved → {dest}`)
	end
	if fs.exists(BUILD_PATH) then
		fs.remove(BUILD_PATH)
	end
end

local function finish(exitCode: number): never
	uninstallTestPlugin()
	return process.exit(exitCode)
end

local function pluginNamesToTest(): { string }
	local args = process.args
	local secondArg = args[2]
	local selected: { plugins.PluginInfo }

	if secondArg == nil or string.lower(secondArg) == "all" then
		selected = plugins.list()
	else
		selected = {}
		local seen: { [string]: boolean } = {}
		for index = 2, #args do
			local arg = args[index]
			local plugin = plugins.find(arg)
			if plugin == nil then
				print(`Unknown plugin: {arg}`)
				process.exit(1)
			elseif not seen[plugin.name] then
				seen[plugin.name] = true
				table.insert(selected, plugin)
			end
		end
	end

	local names = {} :: { string }
	for _, plugin in selected do
		if plugin.hasTests then
			table.insert(names, plugin.name)
		end
	end
	return names
end

local function parsePluginSummaries(raw: any): { PluginSummary }
	local summaries = {} :: { PluginSummary }
	if type(raw) ~= "table" then
		return summaries
	end
	for _, entry in raw :: { any } do
		if type(entry) == "table" then
			table.insert(summaries, {
				name = tostring(entry.name or "?"),
				passed = tonumber(entry.passed) or 0,
				failed = tonumber(entry.failed) or 0,
				total = tonumber(entry.total) or 0,
			})
		end
	end
	return summaries
end

local function printResultLine(name: unknown, status: unknown, durationMs: number, err: unknown?)
	local timeText = richterm.dim(`({durationMs}ms)`)
	local label = if status == "pass"
		then richterm.combine(richterm.bold, richterm.green)("PASS")
		else richterm.combine(richterm.bold, richterm.red)("FAIL")
	print(`\t\t{label} {name} {timeText}`)
	if status ~= "pass" and err ~= nil then
		for _, line in string.split(tostring(err), "\n") do
			if line ~= "" then
				print(`\t\t{richterm.italic(line)}`)
			end
		end
	end
end

local toTest = pluginNamesToTest()
if #toTest == 0 then
	print("No plugins with tests to run.")
	process.exit(0)
end

local ready = false
local closed = false
local doneSummary: DoneSummary? = nil
local studioWebsocket: server.ServerWebSocket? = nil

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
				if not ready then
					print("Connected!\n\nRunning tests...")
				end
				ready = true
				websocket:send(json.serialize({
					type = "run",
					filter = "all",
				}))
			elseif messageType == "section" then
				local name = tostring(message.name or "?")
				if message.kind == "suite" then
					print(`\t{richterm.cyan(name)}`)
				else
					print(`\n{richterm.bold(name)}`)
				end
			elseif messageType == "output" then
				print(tostring(message.message))
			elseif messageType == "result" then
				printResultLine(message.name or "?", message.status or "?", tonumber(message.duration) or 0, message.error)
			elseif messageType == "screenshot" then
				local name = message.name or "screenshot"
				if message.success then
					print(`\t\t{richterm.cyan("SCREENSHOT")}\t{name}`)
				else
					print(`\t\t{richterm.yellow("SCREENSHOT")}\t{name} {richterm.dim("(failed)")}`)
				end
			elseif messageType == "done" then
				doneSummary = {
					passed = tonumber(message.passed) or 0,
					failed = tonumber(message.failed) or 0,
					total = tonumber(message.total) or 0,
					plugins = parsePluginSummaries(message.plugins),
				}
			end
		end,
		close = function(_websocket, _code, _message)
			closed = true
		end,
	},
})

print(`Building test runner for: {table.concat(toTest, ", ")}`)
writeTestProject(toTest)

local build = process.system(`rojo build {PROJECT_PATH} -o {BUILD_PATH}`)
if not build.ok then
	if build.stderr ~= "" then
		print(build.stderr)
	end
	httpServer.close()
	print(`Failed to build {PROJECT_PATH}`)
	process.exit(1)
end

installTestPlugin()
print("\tDone. Open any place in Studio (enable Reload Plugins on File Changed if needed).")
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
	finish(1)
end

local runDeadline = os.clock() + RUN_TIMEOUT
while doneSummary == nil and not closed and os.clock() < runDeadline do
	task.wait(0.25)
end

httpServer.close()

if doneSummary == nil then
	if not closed and os.clock() >= runDeadline then
		print(`\nTimed out waiting for test results after {RUN_TIMEOUT}s.`)
	else
		print("\nConnection to Studio lost before results.")
	end
	finish(1)
end

local summary = doneSummary :: DoneSummary

print("")
for _, plugin in summary.plugins do
	local passedText = richterm.green(`{plugin.passed} passed`)
	if plugin.failed > 0 then
		print(
			`{richterm.bold(plugin.name)}: {passedText}, {richterm.red(`{plugin.failed} failed`)}, {plugin.total} total`
		)
	else
		print(`{richterm.bold(plugin.name)}: {passedText}, {plugin.total} total`)
	end
end

if summary.failed > 0 then
	print(
		`Results: {richterm.green(`{summary.passed} passed`)}, {richterm.red(`{summary.failed} failed`)}, {summary.total} total`
	)
	finish(1)
end

print(`Results: {richterm.green(`{summary.passed} passed`)}, {summary.total} total`)
finish(0)
