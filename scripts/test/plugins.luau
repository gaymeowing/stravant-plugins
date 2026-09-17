local json = require("@std/json")
local fs = require("@std/fs")

export type Plugin = {
	name: string,
	output: string,
}

local KEY_ORDER = {
	"$className",
	"$path",
	"$optional",
	"$properties",
	"optional",
	"name",
	"globIgnorePaths",
	"tree",
	"Src",
	"PluginGui",
	"Packages",
	"Loader",
	"TestRunner",
	"Workspace",
	"ServerScriptService",
	"Plugin",
	"version",
	"tasks",
	"label",
	"type",
	"command",
	"args",
	"options",
	"cwd",
	"group",
	"kind",
	"isDefault",
	"problemMatcher",
	"runOptions",
	"runOn",
	"presentation",
	"reveal",
	"panel",
	"showReuseMessage",
	"clear",
}

local keyRank = {} :: { [string]: number }
for index, key in KEY_ORDER do
	keyRank[key] = index
end

local function sortedKeys(object: json.Object): { string }
	local keys = {} :: { string }
	for key in object do
		if type(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local rankA = keyRank[a] or 1000
		local rankB = keyRank[b] or 1000
		if rankA ~= rankB then
			return rankA < rankB
		end
		return a < b
	end)
	return keys
end

local function encode(value: json.Value, depth: number): string
	local valueType = type(value)
	if valueType == "boolean" then
		return if value then "true" else "false"
	elseif valueType == "number" then
		return tostring(value)
	elseif valueType == "string" then
		return json.serialize(value)
	elseif valueType ~= "table" then
		error(`cannot encode {valueType}`)
	end

	local indent = string.rep("\t", depth)
	local inner = indent .. "\t"
	local asObject = json.asObject(value)
	if asObject ~= nil then
		local keys = sortedKeys(asObject)
		if #keys == 0 then
			return "{}"
		end
		local parts = { "{\n" }
		for index, key in keys do
			table.insert(parts, inner)
			table.insert(parts, json.serialize(key))
			table.insert(parts, ": ")
			table.insert(parts, encode(asObject[key], depth + 1))
			if index < #keys then
				table.insert(parts, ",\n")
			else
				table.insert(parts, "\n")
			end
		end
		table.insert(parts, indent)
		table.insert(parts, "}")
		return table.concat(parts)
	end

	local array = value :: json.Array
	if #array == 0 then
		return "[]"
	end
	local parts = { "[\n" }
	for index, child in array do
		table.insert(parts, inner)
		table.insert(parts, encode(child, depth + 1))
		if index < #array then
			table.insert(parts, ",\n")
		else
			table.insert(parts, "\n")
		end
	end
	table.insert(parts, indent)
	table.insert(parts, "]")
	return table.concat(parts)
end

local function obj(props: { [string]: json.Value }): json.Object
	return json.object(props)
end

local function pluginTree(
	srcPath: string,
	pluginGuiPath: string,
	packagesPath: string,
	loaderPath: string?,
	testRunnerPath: string?
): json.Object
	local tree = {
		["$className"] = "Folder",
		Src = obj({
			["$path"] = srcPath,
			PluginGui = obj({
				["$path"] = pluginGuiPath,
			}),
		}),
		Packages = obj({
			["$path"] = obj({
				optional = packagesPath,
			}),
		}),
	} :: { [string]: json.Value }

	if loaderPath ~= nil then
		tree.Loader = obj({
			["$path"] = loaderPath,
		})
	end
	if testRunnerPath ~= nil then
		tree.TestRunner = obj({
			["$path"] = testRunnerPath,
		})
	end

	return obj(tree)
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

local function list(): { Plugin }
	local existing = cached
	if existing ~= nil then
		return existing
	end
	local discovered = discover()
	cached = discovered
	return discovered
end

local function pluginProject(plugin: Plugin): json.Object
	return obj({
		name = plugin.name,
		globIgnorePaths = { "**/*.spec.luau" },
		tree = pluginTree("src", "../../libraries/PluginGui", "../../Packages", "loader.server.luau", nil),
	})
end

local function runtestsProject(plugin: Plugin): json.Object
	return obj({
		name = `{plugin.name}-runtests`,
		tree = pluginTree(
			"src",
			"../../libraries/PluginGui",
			"../../Packages",
			"../../scripts/test/runtests.server.luau",
			"../../scripts/test/TestRunner.luau"
		),
	})
end

local function ocaleProject(plugin: Plugin): json.Object
	local name = plugin.name
	return obj({
		name = `{name}-ocale`,
		tree = obj({
			["$className"] = "DataModel",
			Workspace = obj({
				["$className"] = "Workspace",
				["$properties"] = obj({
					Name = "runtests",
				}),
			}),
			ServerScriptService = obj({
				["$className"] = "ServerScriptService",
				Plugin = pluginTree(
					`plugins/{name}/src`,
					"libraries/PluginGui",
					"Packages",
					nil,
					"scripts/test/TestRunner.luau"
				),
			}),
		}),
	})
end

local function rootProject(): json.Object
	local tree = {
		["$className"] = "Folder",
		Src = obj({
			["$className"] = "Folder",
			PluginGui = obj({
				["$path"] = "libraries/PluginGui",
			}),
		}),
		Packages = obj({
			["$path"] = obj({
				optional = "Packages",
			}),
		}),
	} :: { [string]: json.Value }

	for _, plugin in list() do
		local name = plugin.name
		tree[name] = pluginTree(
			`plugins/{name}/src`,
			"libraries/PluginGui",
			"Packages",
			`plugins/{name}/loader.server.luau`
		)
	end

	return obj({
		name = "stravant-plugins",
		tree = obj(tree),
	})
end

local function cwdOptions(): json.Object
	return obj({
		cwd = "${workspaceFolder}",
	})
end

local function shellTask(label: string, args: { string }, group: json.Value, extra: json.Object?): json.Object
	local task = obj({
		label = label,
		type = "shell",
		command = "lute",
		args = args,
		options = cwdOptions(),
		group = group,
		problemMatcher = {},
	})
	if extra ~= nil then
		for key, value in extra do
			if type(key) == "string" then
				task[key] = value
			end
		end
	end
	return task
end

local function writeJson(path: string, value: json.Object)
	fs.writeStringToFile(path, encode(value, 0) .. "\n")
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

local function vscodeTasks(): json.Object
	local tasks = {
		shellTask("Build all", { "scripts/build.luau", "all" }, obj({
			kind = "build",
			isDefault = true,
		})),
		shellTask("Generate Rojo projects", { "scripts/build.luau", "generate" }, "build", obj({
			runOptions = obj({
				runOn = "folderOpen",
			}),
			presentation = obj({
				reveal = "silent",
				panel = "shared",
				showReuseMessage = false,
				clear = false,
			}),
		})),
		shellTask("Test all", { "run", "scripts/test", "all" }, "test"),
	}
	for _, plugin in list() do
		local name = plugin.name
		table.insert(tasks, shellTask(`Build {name}`, { "scripts/build.luau", name }, "build"))
		table.insert(tasks, shellTask(`Build {name} (watch)`, { "scripts/build.luau", name, "--watch" }, "build"))
		if hasTests(plugin) then
			table.insert(tasks, shellTask(`Test {name}`, { "run", "scripts/test", name }, "test"))
		end
	end
	return obj({
		version = "2.0.0",
		tasks = tasks,
	})
end

local function writePluginProjects(plugin: Plugin)
	local name = plugin.name
	writeJson(`plugins/{name}/default.project.json`, pluginProject(plugin))
	if hasTests(plugin) then
		writeJson(`plugins/{name}/runtests.project.json`, runtestsProject(plugin))
		writeJson(`plugins/{name}/ocale.project.json`, ocaleProject(plugin))
	end
end

local function writeRootProject()
	cached = nil
	writeJson("default.project.json", rootProject())
end

local function writeVscodeTasks()
	writeJson(".vscode/tasks.json", vscodeTasks())
end

local function writeAllProjects()
	writeRootProject()
	writeVscodeTasks()
	for _, plugin in list() do
		writePluginProjects(plugin)
	end
end

local function find(name: string): Plugin?
	for _, plugin in list() do
		if plugin.name == name then
			return plugin
		end
	end
	return nil
end

return {
	list = list,
	find = find,
	hasTests = hasTests,
	writePluginProjects = writePluginProjects,
	writeRootProject = writeRootProject,
	writeAllProjects = writeAllProjects,
}
