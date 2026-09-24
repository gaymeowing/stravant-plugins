-- plugins
-- module containing info for every plugin

local watchDirectory = require("@scripts/watchDirectory")
local startsWith = require("@scripts/startsWith")
local endsWith = require("@scripts/endsWith")
local toml = require("@batteries/toml")
local task = require("@lute/task")
local fs = require("@lute/fs")

export type PluginChangedCallback = (oldName: string, newName: string?) -> ()
export type TestsChangedCallback = (hasTests: boolean) -> ()
--- Fired for filesystem changes under a plugin directory (`relativePath` from the plugin root).
export type FilesChangedCallback = (pluginName: string, relativePath: string) -> ()

type function freezeTable(t: type): type
	if t.tag == "table" then
		local properties = t:properties()

		for _, value in properties do
			if value.write and not value.read then
				value.read = value.write
			end
			value.write = nil
		end

		local frozenTable = types.newtable(properties)
		local indexer = t:readindexer() or t:writeindexer()

		if indexer then
			frozenTable:setreadindexer(indexer.index, indexer.result)
		end
		return frozenTable
	end
	return t
end

type StoredPluginInfo = {
	totalTests: number,
	hasTests: boolean,
	version: string,
	name: string,
	id: number?,
}

export type PluginInfo = freezeTable<StoredPluginInfo>

local PLUGIN_CHANGED_CALLBACKS = {} :: { PluginChangedCallback }
local TESTS_CHANGED_CALLBACKS = {} :: { TestsChangedCallback }
local FILES_CHANGED_CALLBACKS = {} :: { FilesChangedCallback }
local NAME_TO_PLUGIN = {} :: { [string]: StoredPluginInfo? }
local ID_TO_PLUGIN = {} :: { [number]: StoredPluginInfo? }
local SEMVER_PATTERN = "%d+%.%d+%.%d+[%a%-]*"
local PLUGINS = {} :: { StoredPluginInfo }
local TOTAL_PLUGIN_CHANGED_CALLBACKS = 0
local TOTAL_TESTS_CHANGED_CALLBACKS = 0
local TOTAL_FILES_CHANGED_CALLBACKS = 0
local HAS_INITIATED = false
local TOTAL_PLUGINS = 0

local function readFile(path: string): string
	local handle = fs.open(path, "r")
	local contents = fs.read(handle)
	fs.close(handle)
	return contents
end

local function isPascalCase(s: string): boolean
	return string.match(s, "^%u%w*$") ~= nil
end

local function isFile(path: string): boolean
	return fs.exists(path) and fs.type(path) == "file"
end

local function isDir(path: string): boolean
	return fs.exists(path) and fs.type(path) == "dir"
end

local function countSpecs(dir: string): number
	local total = 0
	local stack = { dir }

	while #stack > 0 do
		local current = table.remove(stack) :: string
		for _, entry in fs.listdir(current) do
			if entry.type == "file" and endsWith(entry.name, ".spec.luau") then
				total += 1
			elseif entry.type == "dir" and not startsWith(entry.name, ".") then
				table.insert(stack, `{current}/{entry.name}`)
			end
		end
	end
	return total
end

local function VALIDATE_FIELD(
	pluginName: string,
	raw: { [string]: toml.TomlValue },
	fieldName: string,
	expectedType: string,
	expectedPattern: string?
): toml.TomlValue
	local fieldValue = raw[fieldName]

	if fieldValue == nil then
		error(`field '{fieldName}' isn't defined in the PLUGIN.toml for plugin '{pluginName}'`)
	elseif
		(expectedPattern ~= nil and type(fieldValue) == "string" and string.match(fieldValue, expectedPattern) == nil)
		or type(fieldValue) ~= expectedType
	then
		error(`field '{fieldName}' in the PLUGIN.toml for plugin '{pluginName}' is not type '{expectedType}'`)
	end
	return fieldValue
end

local function VALIDATE_OPTIONAL_FIELD(
	pluginName: string,
	raw: { [string]: toml.TomlValue },
	fieldName: string,
	expectedType: string,
	expectedPattern: string?
): toml.TomlValue?
	local fieldValue = raw[fieldName]

	if fieldValue == nil then
		return nil
	elseif
		(expectedPattern ~= nil and type(fieldValue) == "string" and string.match(fieldValue, expectedPattern) == nil)
		or type(fieldValue) ~= expectedType
	then
		error(`field '{fieldName}' in the PLUGIN.toml for plugin '{pluginName}' is not type '{expectedType}'`)
	end
	return fieldValue
end

local function readPluginInfo(pluginName: string): (string, number?)
	local raw = toml.deserialize(readFile(`plugins/{pluginName}/PLUGIN.toml`))
	local version = VALIDATE_FIELD(pluginName, raw, "Version", "string", SEMVER_PATTERN) :: string
	local id = VALIDATE_OPTIONAL_FIELD(pluginName, raw, "Id", "number") :: number?
	return version, id
end

local function loadPlugin(name: string): StoredPluginInfo
	local src = `plugins/{name}/src`
	local totalTests = if isDir(src) then countSpecs(src) else 0
	local version, id = readPluginInfo(name)
	return table.freeze({
		hasTests = totalTests > 0,
		totalTests = totalTests,
		version = version,
		name = name,
		id = id,
	}) :: StoredPluginInfo
end

local function emitPluginChanged(oldName: string, newName: string?)
	for _, callback in PLUGIN_CHANGED_CALLBACKS do
		task.defer(callback, oldName, newName)
	end
end

local function emitTestsChanged(hasTests: boolean)
	for _, callback in TESTS_CHANGED_CALLBACKS do
		task.defer(callback, hasTests)
	end
end

local function emitFilesChanged(pluginName: string, relativePath: string)
	for _, callback in FILES_CHANGED_CALLBACKS do
		task.defer(callback, pluginName, relativePath)
	end
end

local function swapRemoveAt(index: number)
	local last = PLUGINS[TOTAL_PLUGINS]
	PLUGINS[index] = last
	PLUGINS[TOTAL_PLUGINS] = nil
	TOTAL_PLUGINS -= 1
end

local function dropCached(name: string): StoredPluginInfo?
	local key = string.lower(name)
	local previous = NAME_TO_PLUGIN[key]
	if previous == nil then
		return nil
	end

	NAME_TO_PLUGIN[key] = nil
	local id = previous.id
	if id ~= nil and ID_TO_PLUGIN[id] == previous then
		ID_TO_PLUGIN[id] = nil
	end
	local index = table.find(PLUGINS, previous)
	if index ~= nil then
		swapRemoveAt(index)
	end
	return previous
end

local function upsertCached(plugin: StoredPluginInfo)
	local key = string.lower(plugin.name)
	local previous = NAME_TO_PLUGIN[key]
	if previous ~= nil then
		local previousId = previous.id
		if previousId ~= nil and previousId ~= plugin.id and ID_TO_PLUGIN[previousId] == previous then
			ID_TO_PLUGIN[previousId] = nil
		end
		PLUGINS[table.find(PLUGINS, previous) :: number] = plugin
	else
		TOTAL_PLUGINS += 1
		PLUGINS[TOTAL_PLUGINS] = plugin
	end
	NAME_TO_PLUGIN[key] = plugin
	local id = plugin.id
	if id ~= nil then
		ID_TO_PLUGIN[id] = plugin
	end
end

local function addPlugin(name: string)
	if not isPascalCase(name) then
		error(`plugins/{name} must be a PascalCase directory (used as the .rbxmx name)`)
	end

	local previous = NAME_TO_PLUGIN[string.lower(name)]
	local plugin = loadPlugin(name)
	local id = plugin.id

	if previous == nil and id ~= nil then
		local byId = ID_TO_PLUGIN[id]
		if byId ~= nil and byId.name ~= name then
			local oldName = byId.name
			local oldHasTests = byId.hasTests
			dropCached(oldName)
			upsertCached(plugin)
			emitPluginChanged(oldName, name)
			if oldHasTests ~= plugin.hasTests then
				emitTestsChanged(plugin.hasTests)
			end
			return
		end
	end

	upsertCached(plugin)
	emitPluginChanged(name, name)
	if previous == nil or previous.hasTests ~= plugin.hasTests then
		if previous ~= nil or plugin.hasTests then
			emitTestsChanged(plugin.hasTests)
		end
	end
end

local function removePlugin(name: string): boolean
	local previous = dropCached(name)
	if previous == nil then
		return false
	end

	local oldId = previous.id
	if oldId ~= nil then
		for _, entry in fs.listdir("plugins") do
			if entry.type ~= "dir" then
				continue
			end
			local newName = entry.name
			if
				NAME_TO_PLUGIN[string.lower(newName)] ~= nil
				or not isPascalCase(newName)
				or not isDir(`plugins/{newName}/src`)
				or not isFile(`plugins/{newName}/loader.server.luau`)
				or not isFile(`plugins/{newName}/PLUGIN.toml`)
			then
				continue
			end
			local plugin = loadPlugin(newName)
			if plugin.id ~= oldId then
				continue
			end
			upsertCached(plugin)
			emitPluginChanged(name, newName)
			if previous.hasTests ~= plugin.hasTests then
				emitTestsChanged(plugin.hasTests)
			end
			return true
		end
	end

	emitPluginChanged(name, nil)
	if previous.hasTests then
		emitTestsChanged(false)
	end
	return true
end

local function updatePluginTests(name: string)
	local existing = NAME_TO_PLUGIN[string.lower(name)]
	if existing == nil then
		return
	end

	local src = `plugins/{name}/src`
	local totalTests = if isDir(src) then countSpecs(src) else 0
	if existing.totalTests == totalTests then
		return
	end

	local hasTests = totalTests > 0
	local hadTests = existing.hasTests
	upsertCached(table.freeze({
		name = existing.name,
		totalTests = totalTests,
		hasTests = hasTests,
		version = existing.version,
		id = existing.id,
	}) :: StoredPluginInfo)
	if hadTests ~= hasTests then
		emitTestsChanged(hasTests)
	end
end

local function isGeneratedPath(relativePath: string): boolean
	return endsWith(relativePath, ".project.json")
		or endsWith(relativePath, ".rbxmx")
		or endsWith(relativePath, ".rbxm")
end

--- Warns about missing layout files. Returns true when the layout is complete.
local function warnMissingLayout(name: string): boolean
	local ok = true
	if not isDir(`plugins/{name}/src`) then
		print(`[PLUGINS]: plugin '{name}' is missing its 'src' directory`)
		ok = false
	end
	if not isFile(`plugins/{name}/loader.server.luau`) then
		print(`[PLUGINS]: plugin '{name}' is missing its loader script (loader.server.luau)`)
		ok = false
	end
	if not isFile(`plugins/{name}/PLUGIN.toml`) then
		print(`[PLUGINS]: plugin '{name}' is missing its PLUGIN.toml`)
		ok = false
	end
	return ok
end

local WATCH_DISCONNECTS = {} :: { () -> () }

local function handlePluginPathChange(name: string, pluginRelativePath: string?)
	local existing = NAME_TO_PLUGIN[string.lower(name)]
	if not isDir(`plugins/{name}`) then
		if existing ~= nil then
			removePlugin(name)
		end
		return
	end

	-- Layout roots only — ordinary src/* deletes must not remove the plugin.
	local layoutPath = pluginRelativePath == nil
		or pluginRelativePath == "src"
		or pluginRelativePath == "loader.server.luau"
		or pluginRelativePath == "PLUGIN.toml"

	if layoutPath and not warnMissingLayout(name) then
		if existing ~= nil then
			removePlugin(name)
		end
		return
	end

	if pluginRelativePath ~= nil and endsWith(pluginRelativePath, ".spec.luau") then
		updatePluginTests(name)
		return
	end

	-- Ordinary src edits only need emitFilesChanged (already fired). Re-load
	-- PLUGIN.toml / layout when the plugin appears or metadata paths change.
	local metadataChange = pluginRelativePath == nil
		or pluginRelativePath == "PLUGIN.toml"
		or pluginRelativePath == "loader.server.luau"
		or pluginRelativePath == "src"
		or (
			not startsWith(pluginRelativePath, "src/")
			and not startsWith(pluginRelativePath, "src\\")
		)

	if metadataChange and isPascalCase(name) and warnMissingLayout(name) then
		addPlugin(name)
	end
end

local function watchPlugin(name: string)
	local root = `plugins/{name}`
	local prefix = `plugins/{name}/`
	table.insert(
		WATCH_DISCONNECTS,
		watchDirectory(root, function(dir: string, filename: string, _event: fs.WatchEvent)
			local fullPath = `{dir}/{filename}`
			local relative = if startsWith(fullPath, prefix) then string.sub(fullPath, #prefix + 1) else filename
			if isGeneratedPath(relative) then
				return
			end
			emitFilesChanged(name, relative)
			handlePluginPathChange(name, relative)
		end)
	)
end

local WATCHING = false

local function discover()
	for _, entry in fs.listdir("plugins") do
		if entry.type ~= "dir" or startsWith(entry.name, ".") then
			continue
		end
		local name = entry.name
		if isPascalCase(name) and warnMissingLayout(name) then
			addPlugin(name)
		end
	end
end

local function ensureWatching()
	if WATCHING then
		return
	end
	WATCHING = true

	-- top-level plugin create/delete only (lute watch is not recursive)
	local rootHandle = fs.watch("plugins", function(filename: string, _event: fs.WatchEvent)
		if startsWith(filename, ".") or string.find(filename, "[/\\]") ~= nil then
			return
		end
		if isDir(`plugins/{filename}`) then
			watchPlugin(filename)
			handlePluginPathChange(filename, nil)
		else
			handlePluginPathChange(filename, nil)
		end
	end)
	table.insert(WATCH_DISCONNECTS, function()
		rootHandle:close()
	end)

	for _, plugin in PLUGINS do
		watchPlugin(plugin.name)
	end
end

-- lute forbids yielding during require; first method call runs init after the module returns.
-- Discovery only — open watches keep lute alive, so watching starts via on* callbacks.
local function ensureReady()
	if not HAS_INITIATED then
		HAS_INITIATED = true
		discover()
	end
end

local plugins = {}

function plugins.onPluginChanged(callback: PluginChangedCallback): () -> ()
	ensureReady()
	ensureWatching()
	TOTAL_PLUGIN_CHANGED_CALLBACKS += 1
	PLUGIN_CHANGED_CALLBACKS[TOTAL_PLUGIN_CHANGED_CALLBACKS] = callback

	return function()
		local index = table.find(PLUGIN_CHANGED_CALLBACKS, callback)
		if index then
			PLUGIN_CHANGED_CALLBACKS[index] = PLUGIN_CHANGED_CALLBACKS[TOTAL_PLUGIN_CHANGED_CALLBACKS]
			PLUGIN_CHANGED_CALLBACKS[TOTAL_PLUGIN_CHANGED_CALLBACKS] = nil
			TOTAL_PLUGIN_CHANGED_CALLBACKS -= 1
		end
	end
end

function plugins.onTestsChanged(callback: TestsChangedCallback): () -> ()
	ensureReady()
	ensureWatching()
	TOTAL_TESTS_CHANGED_CALLBACKS += 1
	TESTS_CHANGED_CALLBACKS[TOTAL_TESTS_CHANGED_CALLBACKS] = callback

	return function()
		local index = table.find(TESTS_CHANGED_CALLBACKS, callback)
		if index then
			TESTS_CHANGED_CALLBACKS[index] = TESTS_CHANGED_CALLBACKS[TOTAL_TESTS_CHANGED_CALLBACKS]
			TESTS_CHANGED_CALLBACKS[TOTAL_TESTS_CHANGED_CALLBACKS] = nil
			TOTAL_TESTS_CHANGED_CALLBACKS -= 1
		end
	end
end

function plugins.onFilesChanged(callback: FilesChangedCallback): () -> ()
	ensureReady()
	ensureWatching()
	TOTAL_FILES_CHANGED_CALLBACKS += 1
	FILES_CHANGED_CALLBACKS[TOTAL_FILES_CHANGED_CALLBACKS] = callback

	return function()
		local index = table.find(FILES_CHANGED_CALLBACKS, callback)
		if index then
			FILES_CHANGED_CALLBACKS[index] = FILES_CHANGED_CALLBACKS[TOTAL_FILES_CHANGED_CALLBACKS]
			FILES_CHANGED_CALLBACKS[TOTAL_FILES_CHANGED_CALLBACKS] = nil
			TOTAL_FILES_CHANGED_CALLBACKS -= 1
		end
	end
end

function plugins.find(name: string): PluginInfo?
	ensureReady()
	return NAME_TO_PLUGIN[string.lower(name)]
end

function plugins.get(name: string): PluginInfo
	ensureReady()
	local plugin = NAME_TO_PLUGIN[string.lower(name)]

	if not plugin then
		error(`plugin '{name}' doesn't exist`)
	end
	return plugin
end

function plugins.list(): { PluginInfo }
	ensureReady()
	return PLUGINS :: any
end

return table.freeze(plugins)
