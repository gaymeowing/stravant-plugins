local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")
local json = require("@std/json")
local task = require("@std/task")
local server = require("@lute/net/server")

local plugins = require("@self/plugins")

local PORT = 38741
local CONNECT_TIMEOUT = 30

local function usage(): never
	io.write("Usage: lute run scripts/test <plugin|all> [filter]\n\nPlugins with specs:\n")
	for _, plugin in plugins.list() do
		if plugins.hasTests(plugin) then
			io.write(`  {plugin.name}\n`)
		end
	end
	process.exit(1)
end

if not fs.exists("rokit.toml") or not fs.exists("libraries/PluginGui") then
	io.write("Run this from the stravant-plugins repo root.\n")
	process.exit(1)
end

local args = process.args
local target: string? = nil
local filter = "all"

for index = 2, #args do
	local arg = args[index]
	if target == nil then
		target = arg
	elseif filter == "all" then
		filter = arg
	else
		io.write(`Unknown argument: {arg}\n`)
		usage()
	end
end

if target == nil then
	usage()
end

local function inGithubActions(): boolean
	local value = process.env.GITHUB_ACTIONS
	return value ~= nil and value ~= ""
end

local function envOr(...: string): string?
	for _, key in { ... } do
		local value = process.env[key]
		if value ~= nil and value ~= "" then
			return value
		end
	end
	return nil
end

local function runOcale(plugin: plugins.Plugin): boolean
	plugins.writePluginProjects(plugin)
	local projectPath = `plugins/{plugin.name}/ocale.project.json`
	local universeId = envOr("ROBLOX_UNIVERSE_ID", "TEST_UNIVERSE_ID", "ROBLOX_TEST_UNIVERSE_ID")
	local placeId = envOr("ROBLOX_PLACE_ID", "TEST_PLACE_ID", "ROBLOX_TEST_PLACE_ID")
	local apiKey = envOr("ROBLOX_API_KEY")

	if universeId == nil or placeId == nil or apiKey == nil then
		io.write("OCALE requires ROBLOX_API_KEY and universe/place ids (ROBLOX_UNIVERSE_ID / ROBLOX_PLACE_ID).\n")
		return false
	end

	io.write(`Running {plugin.name} tests via rocale-cli...\n`)
	local command = {
		"rocale-cli",
		"run",
		"-u",
		universeId,
		"-p",
		placeId,
		"--load.project",
		projectPath,
		"--script",
		"scripts/test/ocale.luau",
	}
	if filter ~= "all" then
		table.insert(command, "--lua.globals")
		table.insert(command, `TEST_FILTER={filter}`)
	end

	local result = process.run(command, {
		stdio = "inherit",
	})
	if not result.ok then
		io.write(`rocale-cli failed for {plugin.name} (exit {result.exitcode}).\n`)
		return false
	end
	return true
end

local function encodeMsg(data: { [string]: json.Value }): string
	return json.serialize(json.object(data))
end

local function runStudio(plugin: plugins.Plugin): boolean
	plugins.writePluginProjects(plugin)
	local projectPath = `plugins/{plugin.name}/runtests.project.json`

	local ready = false
	local doneSummary: { passed: number, failed: number, total: number }? = nil
	local studioWs: server.ServerWebSocket? = nil
	local closed = false

	local httpServer = server.serve({
		hostname = "127.0.0.1",
		port = PORT,
		handler = function(request, srv)
			if srv:upgrade(request) then
				return nil
			end
			return {
				status = 404,
				body = "expected websocket",
			}
		end,
		websocket = {
			open = function(ws)
				studioWs = ws
			end,
			message = function(ws, message)
				local text = if type(message) == "buffer" then buffer.tostring(message) else message :: string
				local ok, data = pcall(json.deserialize, text)
				if not ok or type(data) ~= "table" then
					io.write(`Bad message from Studio: {text}\n`)
					return
				end
				local msg = data :: { [string]: any }
				local msgType = msg.type

				if msgType == "ready" then
					ready = true
					ws:send(encodeMsg({
						type = "run",
						filter = filter,
					}))
				elseif msgType == "output" then
					io.write(`  {tostring(msg.message)}\n`)
				elseif msgType == "result" then
					local name = tostring(msg.name or "?")
					local status = tostring(msg.status or "?")
					local duration = tonumber(msg.duration) or 0
					if status == "pass" then
						io.write(`  \27[32mPASS\27[0m  {name} ({duration}ms)\n`)
					else
						io.write(`  \27[31mFAIL\27[0m  {name}\n`)
						if msg.error then
							io.write(`        {tostring(msg.error)}\n`)
						end
					end
				elseif msgType == "screenshot" then
					local name = tostring(msg.name or "screenshot")
					if msg.success then
						io.write(`  \27[36mSCREENSHOT\27[0m  {name}\n`)
					else
						io.write(`  \27[33mSCREENSHOT\27[0m  {name} (failed)\n`)
					end
				elseif msgType == "done" then
					doneSummary = {
						passed = tonumber(msg.passed) or 0,
						failed = tonumber(msg.failed) or 0,
						total = tonumber(msg.total) or 0,
					}
				end
			end,
			close = function(_ws, _code, _message)
				closed = true
			end,
		},
	})

	io.write("Building test runner...\n")
	local build = process.run({ "rojo", "build", projectPath, "-p", "RunTests.rbxmx" })
	if not build.ok then
		if build.stderr ~= "" then
			io.write(build.stderr)
		end
		httpServer.close()
		io.write(`Failed to build {projectPath}\n`)
		return false
	end
	io.write("  Done.\n")
	io.write(`Waiting for Studio on port {PORT} (place must be named runtests)...\n`)

	local waited = 0
	while not ready and waited < CONNECT_TIMEOUT do
		task.wait(0.1)
		waited += 0.1
		if closed and studioWs == nil then
			break
		end
	end

	if not ready then
		httpServer.close()
		io.write(`Timed out waiting for Studio after {CONNECT_TIMEOUT}s.\n`)
		return false
	end

	io.write("Connected!\n\nRunning tests...\n")
	while doneSummary == nil and not closed do
		task.wait(0.1)
	end

	httpServer.close()

	local summary = doneSummary
	if summary == nil then
		io.write("\nConnection to Studio lost before results.\n")
		return false
	end

	io.write("\n")
	if summary.failed > 0 then
		io.write(`Results: \27[32m{summary.passed} passed\27[0m, \27[31m{summary.failed} failed\27[0m, {summary.total} total\n`)
		return false
	end
	io.write(`Results: \27[32m{summary.passed} passed\27[0m, {summary.total} total\n`)
	return true
end

local function runOne(plugin: plugins.Plugin): boolean
	if not plugins.hasTests(plugin) then
		io.write(`Skipping {plugin.name} (no *.spec.luau).\n`)
		return true
	end
	if inGithubActions() then
		return runOcale(plugin)
	end
	return runStudio(plugin)
end

local ok = true
if target == "all" then
	for _, plugin in plugins.list() do
		if not runOne(plugin) then
			ok = false
		end
	end
else
	local plugin = plugins.find(target)
	if plugin == nil then
		io.write(`Unknown plugin: {target}\n`)
		usage()
	end
	ok = runOne(plugin)
end

process.exit(if ok then 0 else 1)
