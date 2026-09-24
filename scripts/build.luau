local addBaseGlobIgnorePaths = require("@scripts/baseGlobIgnorePaths")
local watchDirectory = require("@scripts/watchDirectory")
local richterm = require("@batteries/richterm")
local packages = require("@scripts/packages")
local plugins = require("@scripts/plugins")
local process = require("@std/process")
local rojo = require("@scripts/rojo")
local json = require("@std/json")
local task = require("@std/task")
local fs = require("@std/fs")

local warning = richterm.combine(richterm.bold, richterm.yellow)
local failure = richterm.combine(richterm.bold, richterm.red)
local info = richterm.cyan
local muted = richterm.dim

local OUTPUT_EXTENSION = "rbxmx"

local function pluginOutput(plugin: plugins.PluginInfo): string
	return `{plugin.name}.{OUTPUT_EXTENSION}`
end

local function writeJson(path: string, value: any)
	fs.writeStringToFile(path, json.serialize(value) .. "\n")
end

local function pluginTree(
	srcPath: string,
	pluginGuiPath: string,
	packagesPath: string,
	loaderPath: string?,
	testRunnerPath: string?
): rojo.Tree
	local tree = rojo.tree("Folder")
	local src = tree:addScript("Src", srcPath)
	src:addScript("PluginGui", pluginGuiPath)
	tree.Packages = packages.tree(packagesPath)

	if loaderPath ~= nil then
		tree:addScript("Loader", loaderPath)
	end
	if testRunnerPath ~= nil then
		tree:addScript("TestRunner", testRunnerPath)
	end

	return tree
end

local function writePluginProjects(plugin: plugins.PluginInfo)
	local name = plugin.name

	local defaultProject = rojo.project(name)
	addBaseGlobIgnorePaths(defaultProject, true, "../../")
	defaultProject.tree = pluginTree("src", "../../libraries/PluginGui", "../../Packages", "loader.server.luau", nil)
	defaultProject:write(`plugins/{name}/default.project.json`)

	if plugin.hasTests then
		local testProject = rojo.project(`{name}-runtests`)
		addBaseGlobIgnorePaths(testProject, nil, "../../")
		testProject.tree = pluginTree(
			"src",
			"../../libraries/PluginGui",
			"../../Packages",
			"../../scripts/test/runtests.server.luau",
			"../../scripts/test/TestRunner.luau"
		)
		testProject:write(`plugins/{name}/test.project.json`)
	end
end

local function writeRootProject(pluginList: { plugins.PluginInfo })
	local project = rojo.project("stravant-plugins")
	addBaseGlobIgnorePaths(project)
	local tree = project.tree
	local src = tree:addClass("Src", "Folder")
	src:addScript("PluginGui", "libraries/PluginGui")
	tree.Packages = packages.tree("Packages")

	for _, plugin in pluginList do
		local name = plugin.name
		tree[name] =
			pluginTree(`plugins/{name}/src`, "libraries/PluginGui", "Packages", `plugins/{name}/loader.server.luau`)
	end

	project:write("default.project.json")
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

local function writeVscodeTasks(pluginList: { plugins.PluginInfo })
	local tasks = {
		shellTask("Build all", { "scripts/build.luau", "all" }, {
			kind = "build",
			isDefault = true,
		}),
		shellTask("Build all (watch)", { "scripts/build.luau", "all", "--watch" }, "build"),
		shellTask("Generate Rojo projects", { "scripts/build.luau", "generate" }, "build"),
		shellTask("Generate Rojo projects (watch)", { "scripts/build.luau", "generate", "--watch" }, "build", {
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
		if plugin.hasTests then
			table.insert(tasks, shellTask(`Test {name}`, { "run", "scripts/test", name }, "test"))
		end
	end

	writeJson(".vscode/tasks.json", {
		version = "2.0.0",
		tasks = tasks,
	})
end

local function writeAllProjects()
	local pluginList = plugins.list()
	writeRootProject(pluginList)
	writeVscodeTasks(pluginList)
	for _, plugin in pluginList do
		writePluginProjects(plugin)
	end
end

local function usage(): never
	print(
		`{muted("Usage:")} lute scripts/build.luau <plugin|all|generate> [--watch] [--out <dir>] [--use-rbxm]\n\n{muted(
			"Plugins:"
		)}\n`
	)
	for _, plugin in plugins.list() do
		print(`  {richterm.bold(plugin.name)}\t{muted(pluginOutput(plugin))}\n`)
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
	elseif arg == "--use-rbxm" then
		OUTPUT_EXTENSION = "rbxm"
	elseif arg == "--out" then
		index += 1
		outDir = args[index]
		if outDir == nil then
			print(`{warning("--out requires a directory")}\n`)
			usage()
		end
	elseif target == nil and string.sub(arg, 1, 1) ~= "-" then
		target = arg
	else
		print(`{warning(`Unknown argument: {arg}`)}\n`)
		usage()
	end
	index += 1
end

if target == nil then
	usage()
end

if watch and outDir ~= nil then
	print(`{warning("--watch cannot be combined with --out")}\n`)
	process.exit(1)
end

local function ignoredWatchPath(filename: string): boolean
	return string.match(filename, "%.project%.json$") ~= nil
		or string.match(filename, "%.rbxm[x]?$") ~= nil
		or string.match(filename, "sourcemap%.json$") ~= nil
		or string.match(filename, "tasks%.json$") ~= nil
end

local function watchPaths(label: string, onDirty: (dirtyPlugins: { [string]: boolean }, sharedDirty: boolean) -> ())
	local dirtyPlugins: { [string]: boolean } = {}
	local sharedDirty = false
	local flushScheduled = false
	local disconnects = {} :: { () -> () }

	-- watchDirectory already debounces FS storms; just coalesce marks from one flush
	-- (and deferred emitters) into a single rebuild.
	local function scheduleFlush()
		if flushScheduled then
			return
		end
		flushScheduled = true
		task.wait()
			flushScheduled = false
			local batchPlugins = dirtyPlugins
			local batchShared = sharedDirty
			dirtyPlugins = {}
			sharedDirty = false
			if batchShared or next(batchPlugins) ~= nil then
				onDirty(batchPlugins, batchShared)
			end
			if sharedDirty or next(dirtyPlugins) ~= nil then
				scheduleFlush()
			end
	end

	local function markPlugin(name: string)
		dirtyPlugins[name] = true
		scheduleFlush()
	end

	local function markShared()
		sharedDirty = true
		scheduleFlush()
	end

	plugins.onFilesChanged(function(pluginName: string, _relativePath: string)
		markPlugin(pluginName)
	end)

	plugins.onPluginChanged(function(oldName: string, newName: string?)
		if newName == nil or oldName ~= newName then
			markShared()
		else
			markPlugin(newName)
		end
	end)

	table.insert(
		disconnects,
		watchDirectory("libraries", function(_dir: string, filename: string, _event)
			if ignoredWatchPath(filename) then
				return
			end
			markShared()
		end)
	)

	packages.onChanged(markShared)

	print(`{info(label)}\n`)

	while true do
		task.wait()
	end
end

if target == "generate" then
	if outDir ~= nil then
		print(`{warning("--out is not valid with generate")}\n`)
		process.exit(1)
	end
	writeAllProjects()
	print("Wrote default.project.json and per-plugin project files.\n")
	if not watch then
		process.exit(0)
	end
	watchPaths("Watching for changes (regenerating Rojo projects)...", function(dirtyPluginNames, sharedDirty)
		local ok, err = pcall(function()
			if sharedDirty then
				writeAllProjects()
				return
			end

			local pluginList = plugins.list()
			local any = false
			for name in dirtyPluginNames do
				local plugin = plugins.find(name)
				if plugin ~= nil then
					writePluginProjects(plugin)
					any = true
				end
			end
			if any then
				writeRootProject(pluginList)
				writeVscodeTasks(pluginList)
			end
		end)
		if not ok then
			print(`{failure(`Generate failed: {tostring(err)}`)}\n`)
			return
		end
		print("Regenerated.\n")
	end)
end

local function rojoBuild(plugin: plugins.PluginInfo, writeRoot: boolean?): boolean
	local pluginList = plugins.list()
	if writeRoot ~= false then
		writeRootProject(pluginList)
	end
	writePluginProjects(plugin)
	local projectPath = `plugins/{plugin.name}/default.project.json`
	local output = pluginOutput(plugin)

	local outputPath: string
	local result
	if outDir ~= nil then
		if not fs.exists(outDir) then
			fs.createDirectory(outDir, { makeParents = true })
		end
		outputPath = `{outDir}/{output}`
		result = process.system(`rojo build {projectPath} -o {outputPath}`)
	else
		outputPath = output
		result = process.system(`rojo build {projectPath} -p {output}`)
	end

	if not result.ok then
		if result.stdout ~= "" then
			print(richterm.red(result.stdout))
		end
		if result.stderr ~= "" then
			print(richterm.red(result.stderr))
		end
		print(`{failure(`Build failed for {plugin.name} (exit {result.exitcode}).`)}\n`)
		return false
	end

	print(`Built plugin {richterm.bold(`'{plugin.name}'`)} to {outputPath} {muted(`({os.clock()})`)}\n`)
	return true
end

local function pluginsToRebuild(
	watched: { plugins.PluginInfo },
	dirtyPluginNames: { [string]: boolean },
	sharedDirty: boolean
): { plugins.PluginInfo }
	if sharedDirty then
		return watched
	end

	local watchedByName: { [string]: plugins.PluginInfo } = {}
	for _, plugin in watched do
		watchedByName[plugin.name] = plugin
	end

	local rebuild = {}
	for name in dirtyPluginNames do
		local plugin = watchedByName[name]
		if plugin ~= nil then
			table.insert(rebuild, plugin)
		end
	end
	table.sort(rebuild, function(a: plugins.PluginInfo, b: plugins.PluginInfo)
		return a.name < b.name
	end)
	return rebuild
end

local function watchPlugins(watched: { plugins.PluginInfo })
	for _, plugin in watched do
		if not rojoBuild(plugin, true) then
			process.exit(1)
		end
	end

	local label = if #watched == 1
		then `Watching for changes ({watched[1].name} build).`
		else "Watching for changes (rebuilding dirty plugins)."

	watchPaths(label, function(dirtyPluginNames, sharedDirty)
		local rebuild = pluginsToRebuild(watched, dirtyPluginNames, sharedDirty)
		if #rebuild == 0 then
			return
		end
		writeRootProject(plugins.list())
		for _, plugin in rebuild do
			if not rojoBuild(plugin, false) then
				print(`{failure("Build failed; still watching.")}\n`)
				return
			end
		end
	end)
end

if target == "all" then
	local pluginList = plugins.list()
	if watch then
		watchPlugins(pluginList)
		return
	end
	writeRootProject(pluginList)
	for _, plugin in pluginList do
		if not rojoBuild(plugin, false) then
			process.exit(1)
		end
	end
	process.exit(0)
end

local pluginName = target :: string
local plugin = plugins.find(pluginName)
if plugin == nil then
	print(`{warning(`Unknown plugin: {pluginName}`)}\n`)
	usage()
end

if watch then
	watchPlugins({ plugin :: plugins.PluginInfo })
elseif not rojoBuild(plugin :: plugins.PluginInfo, true) then
	process.exit(1)
else
	process.exit(0)
end
