local json = require("@std/json")
local fs = require("@std/fs")

export type Plugin = {
	name: string,
	output: string,
}

local plugins = {}

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

local function discover(): { Plugin }
	local discovered = {} :: { Plugin }
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
		table.insert(discovered, {
			name = name,
			output = `{name}.rbxmx`,
		})
	end
	table.sort(discovered, function(a, b)
		return a.name < b.name
	end)
	return discovered
end

-- listdir yields; lute forbids that during require.
local cached: { Plugin }? = nil

function plugins.list(): { Plugin }
	local existing = cached
	if existing ~= nil then
		return existing
	end
	local discovered = discover()
	cached = discovered
	return discovered
end

local function pluginProject(plugin: Plugin): { [string]: any }
	return {
		name = plugin.name,
		globIgnorePaths = {
			"**/*.spec.luau",
			"**/place.project.json",
			"**/benchmarks.project.json",
		},
		tree = pluginTree("src", "../../libraries/PluginGui", "../../Packages", "loader.server.luau", nil),
	}
end

local function runtestsProject(plugin: Plugin): { [string]: any }
	return {
		name = `{plugin.name}-runtests`,
		-- Keep *.spec.luau — TestRunner discovers and runs them from Src.
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
	}
end

local function rootProject(): { [string]: any }
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

	for _, plugin in plugins.list() do
		local name = plugin.name
		tree[name] = pluginTree(
			`plugins/{name}/src`,
			"libraries/PluginGui",
			"Packages",
			`plugins/{name}/loader.server.luau`
		)
	end

	return {
		name = "stravant-plugins",
		globIgnorePaths = {
			"**/place.project.json",
			"**/benchmarks.project.json",
		},
		tree = tree,
	}
end

local function cwdOptions(): { [string]: any }
	return {
		cwd = "${workspaceFolder}",
	}
end

local function shellTask(label: string, args: { string }, group: any, extra: { [string]: any }?): { [string]: any }
	local task: { [string]: any } = {
		label = label,
		type = "shell",
		command = "lute",
		args = args,
		options = cwdOptions(),
		group = group,
		problemMatcher = {},
	}
	if extra ~= nil then
		for key, value in extra do
			if type(key) == "string" then
				task[key] = value
			end
		end
	end
	return task
end

local function writeJson(path: string, value: any)
	fs.writeStringToFile(path, json.serialize(value) .. "\n")
end

function plugins.hasTests(plugin: Plugin): boolean
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

local function vscodeTasks(): { [string]: any }
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
	for _, plugin in plugins.list() do
		local name = plugin.name
		table.insert(tasks, shellTask(`Build {name}`, { "scripts/build.luau", name }, "build"))
		table.insert(tasks, shellTask(`Build {name} (watch)`, { "scripts/build.luau", name, "--watch" }, "build"))
		if plugins.hasTests(plugin) then
			table.insert(tasks, shellTask(`Test {name}`, { "run", "scripts/test", name }, "test"))
		end
	end
	return {
		version = "2.0.0",
		tasks = tasks,
	}
end

function plugins.writePluginProjects(plugin: Plugin)
	local name = plugin.name
	writeJson(`plugins/{name}/default.project.json`, pluginProject(plugin))
	if plugins.hasTests(plugin) then
		writeJson(`plugins/{name}/test.project.json`, runtestsProject(plugin))
	end
end

function plugins.writeRootProject()
	cached = nil
	writeJson("default.project.json", rootProject())
end

local function writeVscodeTasks()
	writeJson(".vscode/tasks.json", vscodeTasks())
end

function plugins.writeAllProjects()
	plugins.writeRootProject()
	writeVscodeTasks()
	for _, plugin in plugins.list() do
		plugins.writePluginProjects(plugin)
	end
end

function plugins.find(name: string): Plugin?
	for _, plugin in plugins.list() do
		if plugin.name == name then
			return plugin
		end
	end
	return nil
end

return table.freeze(plugins)
