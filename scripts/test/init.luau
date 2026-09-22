local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")
local json = require("@std/json")
local task = require("@std/task")
local server = require("@lute/net/server")

local plugins = require("@self/../plugins")

local PORT = 38741
local CONNECT_TIMEOUT = 30
local CI_CONNECT_TIMEOUT = 180

local function usage(): never
	io.write("Usage: lute run scripts/test <plugin|all> [filter]\n\nPlugins with specs:\n")
	for _, plugin in plugins.list() do
		if plugins.hasTests(plugin) then
			io.write(`  {plugin.name}\n`)
		end
	end
	process.exit(1)
end

if not fs.exists("foreman.toml") or not fs.exists("libraries/PluginGui") then
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

local function inCi(): boolean
	local value = process.env.GITHUB_ACTIONS or process.env.CI
	return value ~= nil and value ~= ""
end

local function isWindows(): boolean
	local runner = process.env.RUNNER_OS
	if runner ~= nil then
		return runner == "Windows"
	end
	local uname = process.run({ "uname", "-s" })
	if uname.ok then
		return string.find(uname.stdout, "MINGW") ~= nil or string.find(uname.stdout, "Msys") ~= nil
	end
	return false
end

local function isMac(): boolean
	local runner = process.env.RUNNER_OS
	if runner ~= nil then
		return runner == "macOS"
	end
	local uname = process.run({ "uname", "-s" })
	return uname.ok and string.find(uname.stdout, "Darwin") ~= nil
end

local function localAppData(): string
	local value = process.env.LOCALAPPDATA
	if value ~= nil and value ~= "" then
		return value
	end
	return `{process.homedir()}/AppData/Local`
end

local function pluginsDir(): string
	if isWindows() then
		return `{localAppData()}/Roblox/Plugins`
	end
	return `{process.homedir()}/Documents/Roblox/Plugins`
end

local function encodeMsg(data: { [string]: json.Value }): string
	return json.serialize(data)
end

local function writeRuntestsPlace(): string
	local projectPath = "scripts/test/runtests-place.project.json"
	local placePath = "scripts/test/runtests.rbxl"
	fs.writeStringToFile(
		projectPath,
		json.serialize({
			name = "runtests",
			tree = {
				["$className"] = "DataModel",
				Workspace = {
					["$className"] = "Workspace",
					["$properties"] = {
						Name = "runtests",
					},
				},
				HttpService = {
					["$className"] = "HttpService",
					["$properties"] = {
						HttpEnabled = true,
					},
				},
			},
		}) .. "\n"
	)
	local build = process.run({ "rojo", "build", projectPath, "-o", placePath })
	if not build.ok then
		if build.stderr ~= "" then
			io.write(build.stderr)
		end
		error(`Failed to build {placePath}`)
	end
	return placePath
end

local function findStudioExe(): string?
	if isMac() then
		local mac = "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio"
		if fs.exists(mac) then
			return mac
		end
		return nil
	end
	if not isWindows() then
		return nil
	end
	local versionsDir = `{localAppData()}/Roblox/Versions`
	if not fs.exists(versionsDir) then
		return nil
	end
	local best: string? = nil
	for _, entry in fs.listDirectory(versionsDir) do
		if entry.type ~= "dir" then
			continue
		end
		local candidate = `{versionsDir}/{entry.name}/RobloxStudioBeta.exe`
		if fs.exists(candidate) then
			best = candidate
		end
	end
	return best
end

local function killStudio()
	if isWindows() then
		process.run({ "taskkill", "/IM", "RobloxStudioBeta.exe", "/F" })
	elseif isMac() then
		process.run({ "pkill", "-x", "RobloxStudio" })
	end
end

local function absPath(path: string): string
	if string.match(path, "^[A-Za-z]:[\\/]") or string.sub(path, 1, 1) == "/" or string.sub(path, 1, 1) == "\\" then
		return path
	end
	return `{process.cwd()}/{path}`
end

local function winPath(path: string): string
	return (string.gsub(absPath(path), "/", "\\"))
end

local function installTestPlugin(rbxmxPath: string)
	local dir = pluginsDir()
	if not fs.exists(dir) then
		fs.createDirectory(dir, { makeParents = true })
	end
	local dest = `{dir}/RunTests.rbxmx`
	if isWindows() then
		local result = process.run({ "cmd", "/c", `copy /Y "{winPath(rbxmxPath)}" "{winPath(dest)}"` })
		if not result.ok then
			error(`Failed to copy {rbxmxPath} → {dest}: {result.stderr}`)
		end
	else
		local result = process.run({ "cp", absPath(rbxmxPath), dest })
		if not result.ok then
			error(`Failed to copy {rbxmxPath} → {dest}: {result.stderr}`)
		end
	end
	io.write(`Installed test plugin → {dest}\n`)
end

local function launchStudio(placePath: string): () -> ()
	local studio = findStudioExe()
	if studio == nil then
		if isMac() then
			error("Roblox Studio not found at /Applications/RobloxStudio.app")
		end
		error("Roblox Studio not found under %LOCALAPPDATA%\\Roblox\\Versions")
	end

	if not fs.exists("build") then
		fs.createDirectory("build", { makeParents = true })
	end
	local logPath = absPath("build/studio-output.log")
	fs.writeStringToFile(logPath, "")
	local offset = 0

	local function flushLog()
		if not fs.exists(logPath) then
			return
		end
		local contents = fs.readFileToString(logPath)
		if #contents > offset then
			io.write(string.sub(contents, offset + 1))
			offset = #contents
		end
	end

	io.write(`Launching Studio: {studio}\n`)
	io.write(`Studio stdout/stderr → {logPath}\n`)

	local result
	if isWindows() then
		result = process.run({
			"cmd",
			"/c",
			`start /b "" "{winPath(studio)}" "{winPath(placePath)}" > "{winPath(logPath)}" 2>&1`,
		})
	else
		-- Background the Studio binary so we keep its stdout/stderr (unlike `open -a`).
		result = process.run({
			"sh",
			"-c",
			'"$1" "$2" > "$3" 2>&1 &',
			"_",
			studio,
			absPath(placePath),
			logPath,
		})
	end
	if not result.ok then
		flushLog()
		error(`Failed to launch Studio: {result.stderr}`)
	end

	return flushLog
end

local function runStudio(plugin: plugins.Plugin): boolean
	plugins.writePluginProjects(plugin)
	local projectPath = `plugins/{plugin.name}/test.project.json`

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
	local build = process.run({ "rojo", "build", projectPath, "-o", "RunTests.rbxmx" })
	if not build.ok then
		if build.stderr ~= "" then
			io.write(build.stderr)
		end
		httpServer.close()
		io.write(`Failed to build {projectPath}\n`)
		return false
	end
	io.write("  Done.\n")

	local timeout = CONNECT_TIMEOUT
	local flushStudioLog: (() -> ())? = nil
	if inCi() then
		timeout = CI_CONNECT_TIMEOUT
		local placeOk, placeOrErr = pcall(writeRuntestsPlace)
		if not placeOk then
			httpServer.close()
			io.write(`{placeOrErr}\n`)
			return false
		end
		local placePath = placeOrErr :: string

		killStudio()
		local installOk, installErr = pcall(installTestPlugin, "RunTests.rbxmx")
		if not installOk then
			httpServer.close()
			io.write(`{installErr}\n`)
			return false
		end
		local launchOk, launchResult = pcall(launchStudio, placePath)
		if not launchOk then
			httpServer.close()
			io.write(`{launchResult}\n`)
			return false
		end
		flushStudioLog = launchResult :: () -> ()
		io.write(`Waiting for Studio on port {PORT} (timeout {timeout}s)...\n`)
	else
		io.write(`Waiting for Studio on port {PORT}...\n`)
	end

	local waited = 0
	local lastHeartbeat = 0
	while not ready and waited < timeout do
		task.wait(0.25)
		waited += 0.25
		if flushStudioLog ~= nil then
			flushStudioLog()
			if waited - lastHeartbeat >= 10 then
				lastHeartbeat = waited
				io.write(`[test] still waiting for Studio websocket… {math.floor(waited)}s / {timeout}s\n`)
			end
		end
		if closed and studioWs == nil then
			break
		end
	end

	if flushStudioLog ~= nil then
		flushStudioLog()
	end

	if not ready then
		httpServer.close()
		if inCi() then
			killStudio()
		end
		io.write(`Timed out waiting for Studio after {timeout}s.\n`)
		io.write("Studio likely did not sign in — check ROBLOX_COOKIE / Account Session Protection.\n")
		return false
	end

	io.write("Connected!\n\nRunning tests...\n")
	while doneSummary == nil and not closed do
		task.wait(0.1)
	end

	httpServer.close()
	if inCi() then
		killStudio()
	end

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
