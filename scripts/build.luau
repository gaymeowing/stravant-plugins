local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")
local json = require("@std/json")
local task = require("@std/task")
local lutefs = require("@lute/fs")

export type Plugin = {
	name: string,
	output: string,
}

local function writeJson(path: string, value: any)
	fs.writeStringToFile(path, json.serialize(value) .. "\n")
end

local function pluginTree(
	srcPath: string,
	pluginGuiPath: string,
	packagesPath: string,
	loaderPath: string?,
	testRunnerPath: string?
): { [string]: any }
	local tree: { [string]: any } = {
		["$className"] = "Folder",
		Src = {
			["$path"] = srcPath,
			PluginGui = {
				["$path"] = pluginGuiPath,
			},
		},
		Packages = {
			["$path"] = {
				optional = packagesPath,
			},
		},
	}

	if loaderPath ~= nil then
		tree.Loader = {
			["$path"] = loaderPath,
		}
	end
	if testRunnerPath ~= nil then
		tree.TestRunner = {
			["$path"] = testRunnerPath,
		}
	end

	return tree
end

local plugins = {} :: { Plugin }
for _, entry in fs.listDirectory("plugins") do
	if entry.type ~= "dir" then
		continue
	end
	local name = entry.name
	if string.sub(name, 1, 1) == "." then
		continue
	end
	if string.match(name, "^[A-Z][A-Za-z0-9]*$") == nil then
		error(`plugins/{name} must be a PascalCase directory (used as the .rbxmx name)`)
	end
	if not fs.exists(`plugins/{name}/src`) or fs.type(`plugins/{name}/src`) ~= "dir" then
		error(`plugins/{name} is missing src/`)
	end
	if not fs.exists(`plugins/{name}/loader.server.luau`) then
		error(`plugins/{name} is missing loader.server.luau`)
	end
	table.insert(plugins, {
		name = name,
		output = `{name}.rbxmx`,
	})
end
table.sort(plugins, function(a: Plugin, b: Plugin)
	return a.name < b.name
end)

local function findPlugin(name: string): Plugin?
	local needle = string.lower(name)
	for _, plugin in plugins do
		if string.lower(plugin.name) == needle then
			return plugin
		end
	end
	return nil
end

local function hasTests(plugin: Plugin): boolean
	local function hasSpecIn(dir: string): boolean
		for _, entry in fs.listDirectory(dir) do
			local entryType = entry.type
			local entryName = entry.name
			if entryType == "file" and string.sub(entryName, -10) == ".spec.luau" then
				return true
			elseif entryType == "dir" and string.sub(entryName, 1, 1) ~= "." then
				if hasSpecIn(`{dir}/{entryName}`) then
					return true
				end
			end
		end
		return false
	end

	local src = `plugins/{plugin.name}/src`
	if not fs.exists(src) then
		return false
	end
	return hasSpecIn(src)
end

local function writePluginProjects(plugin: Plugin)
	local name = plugin.name
	writeJson(`plugins/{name}/default.project.json`, {
		name = name,
		globIgnorePaths = {
			"**/*.spec.luau",
			"**/place.project.json",
			"**/benchmarks.project.json",
		},
		tree = pluginTree("src", "../../libraries/PluginGui", "../../Packages", "loader.server.luau", nil),
	})
	if hasTests(plugin) then
		writeJson(`plugins/{name}/test.project.json`, {
			name = `{name}-runtests`,
			globIgnorePaths = {
				"**/place.project.json",
				"**/benchmarks.project.json",
			},
			tree = pluginTree(
				"src",
				"../../libraries/PluginGui",
				"../../Packages",
				"../../scripts/test/runtests.server.luau",
				"../../scripts/test/TestRunner.luau"
			),
		})
	end
end

local function writeRootProject(pluginList: { Plugin })
	local tree: { [string]: any } = {
		["$className"] = "Folder",
		Src = {
			["$className"] = "Folder",
			PluginGui = {
				["$path"] = "libraries/PluginGui",
			},
		},
		Packages = {
			["$path"] = {
				optional = "Packages",
			},
		},
	}

	for _, plugin in pluginList do
		local name = plugin.name
		tree[name] =
			pluginTree(`plugins/{name}/src`, "libraries/PluginGui", "Packages", `plugins/{name}/loader.server.luau`)
	end

	writeJson("default.project.json", {
		name = "stravant-plugins",
		globIgnorePaths = {
			"**/place.project.json",
			"**/benchmarks.project.json",
		},
		tree = tree,
	})
end

local function shellTask(label: string, args: { string }, group: any, extra: { [string]: any }?): { [string]: any }
	local taskDef: { [string]: any } = {
		label = label,
		type = "shell",
		command = "lute",
		args = args,
		options = {
			cwd = "${workspaceFolder}",
		},
		group = group,
		problemMatcher = {},
	}
	if extra ~= nil then
		for key, value in extra do
			if type(key) == "string" then
				taskDef[key] = value
			end
		end
	end
	return taskDef
end

local function writeVscodeTasks(pluginList: { Plugin })
	local tasks = {
		shellTask("Build all", { "scripts/build.luau", "all" }, {
			kind = "build",
			isDefault = true,
		}),
		shellTask("Generate Rojo projects", { "scripts/build.luau", "generate" }, "build", {
			runOptions = {
				runOn = "folderOpen",
			},
			presentation = {
				reveal = "silent",
				panel = "shared",
				showReuseMessage = false,
				clear = false,
			},
		}),
		shellTask("Test all", { "run", "scripts/test", "all" }, "test"),
	}
	for _, plugin in pluginList do
		local name = plugin.name
		table.insert(tasks, shellTask(`Build {name}`, { "scripts/build.luau", name }, "build"))
		table.insert(tasks, shellTask(`Build {name} (watch)`, { "scripts/build.luau", name, "--watch" }, "build"))
		if hasTests(plugin) then
			table.insert(tasks, shellTask(`Test {name}`, { "run", "scripts/test", name }, "test"))
		end
	end
	writeJson(".vscode/tasks.json", {
		version = "2.0.0",
		tasks = tasks,
	})
end

local function writeAllProjects()
	writeRootProject(plugins)
	writeVscodeTasks(plugins)
	for _, plugin in plugins do
		writePluginProjects(plugin)
	end
end

local function usage(): never
	io.write("Usage: lute scripts/build.luau <plugin|all|generate> [--watch] [--out <dir>]\n\nPlugins:\n")
	for _, plugin in plugins do
		io.write(`  {plugin.name}\t{plugin.output}\n`)
	end
	process.exit(1)
	error("unreachable")
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
	writeAllProjects()
	io.write("Wrote default.project.json and per-plugin project files.\n")
	process.exit(0)
end

local function ignoredWatchPath(filename: string): boolean
	return string.match(filename, "%.project%.json$") ~= nil
		or string.match(filename, "%.rbxmx$") ~= nil
		or string.match(filename, "sourcemap%.json$") ~= nil
end

local function rojoBuild(plugin: Plugin): boolean
	writeRootProject(plugins)
	writePluginProjects(plugin)
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

local function watchPlugin(plugin: Plugin)
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
	writeRootProject(plugins)
	for _, plugin in plugins do
		if not rojoBuild(plugin) then
			process.exit(1)
		end
	end
	process.exit(0)
end

local pluginName = target :: string
local plugin = findPlugin(pluginName)
if plugin == nil then
	io.write(`Unknown plugin: {pluginName}\n`)
	usage()
end

if watch then
	watchPlugin(plugin :: Plugin)
elseif not rojoBuild(plugin :: Plugin) then
	process.exit(1)
end
