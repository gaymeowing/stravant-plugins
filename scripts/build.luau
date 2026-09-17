local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")
local task = require("@std/task")
local lutefs = require("@lute/fs")

local plugins = require("./test/plugins")

local function usage(): never
	io.write("Usage: lute scripts/build.luau <plugin|all|generate> [--watch] [--out <dir>]\n\nPlugins:\n")
	for _, plugin in plugins.list() do
		io.write(`  {plugin.name}\t{plugin.output}\n`)
	end
	process.exit(1)
end

if not fs.exists("rokit.toml") or not fs.exists("libraries/PluginGui") then
	io.write("Run this from the stravant-plugins repo root.\n")
	process.exit(1)
end

local args = process.args
local target: string? = nil
local watch = false
local outDir: string? = nil

local index = 2
while index <= #args do
	local arg = args[index]
	if arg == "--watch" then
		watch = true
	elseif arg == "--out" then
		index += 1
		outDir = args[index]
		if outDir == nil then
			io.write("--out requires a directory\n")
			usage()
		end
	elseif target == nil and string.sub(arg, 1, 1) ~= "-" then
		target = arg
	else
		io.write(`Unknown argument: {arg}\n`)
		usage()
	end
	index += 1
end

if target == nil then
	usage()
end

if watch and outDir ~= nil then
	io.write("--watch cannot be combined with --out\n")
	process.exit(1)
end

if target == "generate" then
	if watch then
		io.write("--watch is not valid with generate\n")
		process.exit(1)
	end
	plugins.writeAllProjects()
	io.write("Wrote default.project.json and per-plugin project files.\n")
	process.exit(0)
end

local function ignoredWatchPath(filename: string): boolean
	return string.match(filename, "%.project%.json$") ~= nil
		or string.match(filename, "%.rbxmx$") ~= nil
		or string.match(filename, "sourcemap%.json$") ~= nil
end

local function rojoBuild(plugin: plugins.Plugin): boolean
	plugins.writeRootProject()
	plugins.writePluginProjects(plugin)
	local projectPath = `plugins/{plugin.name}/default.project.json`

	local command: { string }
	if outDir ~= nil then
		if not fs.exists(outDir) then
			fs.createDirectory(outDir, { makeParents = true })
		end
		local outputPath = `{outDir}/{plugin.output}`
		io.write(`Building {outputPath}...\n`)
		command = { "rojo", "build", projectPath, "-o", outputPath }
	else
		io.write(`Building {plugin.output}...\n`)
		command = { "rojo", "build", projectPath, "-p", plugin.output }
	end

	local result = process.run(command)
	if not result.ok then
		if result.stdout ~= "" then
			io.write(result.stdout)
		end
		if result.stderr ~= "" then
			io.write(result.stderr)
		end
		io.write(`Build failed for {plugin.name} (exit {result.exitcode}).\n`)
		return false
	end

	if result.stdout ~= "" then
		io.write(result.stdout)
	end
	io.write("  Done.\n")
	return true
end

local function watchPlugin(plugin: plugins.Plugin)
	if not rojoBuild(plugin) then
		process.exit(1)
	end

	local dirty = false
	local function mark(filename: string)
		if ignoredWatchPath(filename) then
			return
		end
		dirty = true
	end

	lutefs.watch("plugins", mark)
	lutefs.watch("libraries", mark)
	if fs.exists("Packages") then
		lutefs.watch("Packages", mark)
	end

	io.write("Watching for changes (root default.project.json + plugin build).\n")
	while true do
		task.wait(0.2)
		if dirty then
			dirty = false
			rojoBuild(plugin)
		end
	end
end

if target == "all" then
	if watch then
		io.write("--watch requires a single plugin name\n")
		process.exit(1)
	end
	plugins.writeRootProject()
	for _, plugin in plugins.list() do
		if not rojoBuild(plugin) then
			process.exit(1)
		end
	end
	process.exit(0)
end

local plugin = plugins.find(target)
if plugin == nil then
	io.write(`Unknown plugin: {target}\n`)
	usage()
end

if watch then
	watchPlugin(plugin)
elseif not rojoBuild(plugin) then
	process.exit(1)
end
