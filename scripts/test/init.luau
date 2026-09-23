local process = require("@std/process")
local fs = require("@std/fs")
local json = require("@std/json")
local task = require("@std/task")
local server = require("@lute/net/server")
local richterm = require("@batteries/richterm")

local PORT = 38741
local CONNECT_TIMEOUT = 30
local RUN_TIMEOUT = 120

local PROJECT_PATH = "test.project.json"
local BUILD_PATH = "RunTests.rbxmx"

local pluginNames = {}
for _, entry in fs.listDirectory("plugins") do
	if entry.type == "dir" and string.match(entry.name, "^[A-Z][A-Za-z0-9]*$") then
		table.insert(pluginNames, entry.name)
	end
end
table.sort(pluginNames)

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

local function studioPluginsDir(): string
	local localAppData = process.env.LOCALAPPDATA
	if localAppData ~= nil and localAppData ~= "" then
		return `{localAppData}/Roblox/Plugins`
	end
	return `{process.homedir()}/Documents/Roblox/Plugins`
end

local function packagesTree(projectRelativePath: string): { [string]: any }
	local fsPath = "Packages"
	if not fs.exists(fsPath) then
		return {
			["$path"] = {
				optional = projectRelativePath,
			},
		}
	end

	local tree: { [string]: any } = {
		["$className"] = "Folder",
	}

	for _, entry in fs.listDirectory(fsPath) do
		local name = entry.name
		if string.sub(name, 1, 1) == "." then
			continue
		end

		if name == "_Index" and entry.type == "dir" then
			local indexTree: { [string]: any } = {
				["$className"] = "Folder",
			}
			for _, scopeEntry in fs.listDirectory(`{fsPath}/_Index`) do
				if scopeEntry.type ~= "dir" then
					continue
				end
				local scopePath = `{fsPath}/_Index/{scopeEntry.name}`
				local scopeTree: { [string]: any } = {
					["$className"] = "Folder",
				}
				for _, packageEntry in fs.listDirectory(scopePath) do
					local packageName = packageEntry.name
					local packagePath = `{scopePath}/{packageName}`
					local projectPackagePath = `{projectRelativePath}/_Index/{scopeEntry.name}/{packageName}`
					if packageEntry.type == "dir" then
						local srcPath = `{packagePath}/src`
						if fs.exists(srcPath) and fs.type(srcPath) == "dir" then
							scopeTree[packageName] = {
								["$path"] = `{projectPackagePath}/src`,
							}
						else
							scopeTree[packageName] = {
								["$path"] = projectPackagePath,
							}
						end
					elseif packageEntry.type == "file" then
						local baseName = string.match(packageName, "^(.*)%.luau?$")
						if baseName ~= nil then
							scopeTree[baseName] = {
								["$path"] = `{projectRelativePath}/_Index/{scopeEntry.name}/{packageName}`,
							}
						end
					end
				end
				indexTree[scopeEntry.name] = scopeTree
			end
			tree._Index = indexTree
		elseif entry.type == "file" then
			local baseName = string.match(name, "^(.*)%.luau?$")
			if baseName ~= nil then
				tree[baseName] = {
					["$path"] = `{projectRelativePath}/{name}`,
				}
			end
		end
	end

	return tree
end

local function writeTestProject(names: { string })
	-- Each plugin mounts as RunTests/<Name>/ (src contents), sibling to Packages,
	-- so script.Parent.Parent.Packages and PluginGui's ../../Packages both resolve.
	local tree: { [string]: any } = {
		["$className"] = "Folder",
		Packages = packagesTree("Packages"),
		Loader = {
			["$path"] = "scripts/test/runtests.server.luau",
		},
		TestRunner = {
			["$path"] = "scripts/test/TestRunner.luau",
		},
	}
	for _, name in names do
		tree[name] = {
			["$path"] = `plugins/{name}/src`,
			PluginGui = {
				["$path"] = "libraries/PluginGui",
			},
		}
	end

	fs.writeStringToFile(PROJECT_PATH, json.serialize({
		name = "RunTests",
		globIgnorePaths = {
			"Packages/_Index/**/examples",
			"Packages/_Index/**/benchmarks",
			"Packages/_Index/**/bin",
			"**/place.project.json",
			"**/benchmarks.project.json",
		},
		tree = tree,
	}) .. "\n")
end

local function installedTestPluginPath(): string
	return `{studioPluginsDir()}/RunTests.rbxmx`
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
	process.exit(exitCode)
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
		elseif not seen[pluginName] then
			seen[pluginName] = true
			table.insert(selected, pluginName)
		end
	end
end

local toTest = {}
for _, pluginName in selected do
	if hasTests(pluginName) then
		table.insert(toTest, pluginName)
	end
end

if #toTest == 0 then
	print("No plugins with tests to run.")
	process.exit(0)
end

local filter = "all"

local ready = false
local doneSummary: {
	passed: number,
	failed: number,
	total: number,
	plugins: {
		{
			name: string,
			passed: number,
			failed: number,
			total: number,
		}
	},
}? =
	nil
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
				if not ready then
					print("Connected!\n\nRunning tests...")
				end
				ready = true
				websocket:send(json.serialize({
					type = "run",
					filter = filter,
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
				local name = message.name or "?"
				local status = message.status or "?"
				local duration = tonumber(message.duration) or 0
				local timeText = richterm.dim(`({duration}ms)`)
				if status == "pass" then
					print(`\t\t{richterm.combine(richterm.bold, richterm.green)("PASS")} {name} {timeText}`)
				else
					print(`\t\t{richterm.combine(richterm.bold, richterm.red)("FAIL")} {name} {timeText}`)
					if message.error then
						for _, line in string.split(tostring(message.error), "\n") do
							if line ~= "" then
								print(`\t\t{richterm.italic(line)}`)
							end
						end
					end
				end
			elseif messageType == "screenshot" then
				local name = message.name or "screenshot"
				if message.success then
					print(`\t\t{richterm.cyan("SCREENSHOT")}\t{name}`)
				else
					print(`\t\t{richterm.yellow("SCREENSHOT")}\t{name} {richterm.dim("(failed)")}`)
				end
			elseif messageType == "done" then
				local plugins = {}
				if type(message.plugins) == "table" then
					for _, entry in message.plugins :: { any } do
						if type(entry) == "table" then
							table.insert(plugins, {
								name = tostring(entry.name or "?"),
								passed = tonumber(entry.passed) or 0,
								failed = tonumber(entry.failed) or 0,
								total = tonumber(entry.total) or 0,
							})
						end
					end
				end
				doneSummary = {
					passed = tonumber(message.passed) or 0,
					failed = tonumber(message.failed) or 0,
					total = tonumber(message.total) or 0,
					plugins = plugins,
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
local build = process.run({ "rojo", "build", PROJECT_PATH, "-o", BUILD_PATH })
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

local summary = doneSummary
if summary == nil then
	if not closed and os.clock() >= runDeadline then
		print(`\nTimed out waiting for test results after {RUN_TIMEOUT}s.`)
	else
		print("\nConnection to Studio lost before results.")
	end
	finish(1)
end

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
