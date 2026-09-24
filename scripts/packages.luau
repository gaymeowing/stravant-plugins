-- packages
-- Rojo tree for Wally Packages/ (single tree, rebuilt on Packages changes)

local watchDirectory = require("@scripts/watchDirectory")
local startsWith = require("@scripts/startsWith")
local task = require("@lute/task")
local fs = require("@lute/fs")
local rojo = require("./rojo")

export type ChangedCallback = () -> ()

local CHANGED_CALLBACKS = {} :: { ChangedCallback }
local TOTAL_CHANGED_CALLBACKS = 0
local WATCHING = false
local REBUILD_SCHEDULED = false
local PENDING_NOTIFY = false
-- One tree per project-relative Packages path (`Packages` vs `../../Packages`).
local TREES: { [string]: rojo.Tree } = {}
local DISCONNECTS = {} :: { () -> () }

local function isDir(path: string): boolean
	return fs.exists(path) and fs.type(path) == "dir"
end

local function emitChanged()
	for _, callback in CHANGED_CALLBACKS do
		task.defer(callback)
	end
end

local function build(projectRelativePath: string): rojo.Tree
	local fsPath = "Packages"
	local tree = rojo.tree("Folder")

	for _, entry in fs.listdir(fsPath) do
		local name = entry.name
		if startsWith(name, ".") then
			continue
		end

		if name == "_Index" and entry.type == "dir" then
			local indexTree = tree:addClass("_Index", "Folder")
			for _, scopeEntry in fs.listdir(`{fsPath}/_Index`) do
				if scopeEntry.type ~= "dir" then
					continue
				end
				local scopePath = `{fsPath}/_Index/{scopeEntry.name}`
				local scopeTree = indexTree:addClass(scopeEntry.name, "Folder")
				for _, packageEntry in fs.listdir(scopePath) do
					local packageName = packageEntry.name
					local packagePath = `{scopePath}/{packageName}`
					local projectPackagePath = `{projectRelativePath}/_Index/{scopeEntry.name}/{packageName}`
					if packageEntry.type == "dir" then
						local srcPath = `{packagePath}/src`
						if isDir(srcPath) then
							scopeTree:addScript(packageName, `{projectPackagePath}/src`)
						else
							scopeTree:addScript(packageName, projectPackagePath)
						end
					elseif packageEntry.type == "file" then
						local baseName = string.match(packageName, "^(.*)%.luau?$")
						if baseName ~= nil then
							scopeTree:addScript(baseName, `{projectRelativePath}/_Index/{scopeEntry.name}/{packageName}`)
						end
					end
				end
			end
		elseif entry.type == "file" then
			local baseName = string.match(name, "^(.*)%.luau?$")
			if baseName ~= nil then
				tree:addScript(baseName, `{projectRelativePath}/{name}`)
			end
		end
	end

	return tree
end

local function rebuild()
	for relativePath in TREES do
		TREES[relativePath] = build(relativePath)
	end
	if PENDING_NOTIFY then
		PENDING_NOTIFY = false
		emitChanged()
	end
end

local function scheduleRebuild()
	PENDING_NOTIFY = true
	if REBUILD_SCHEDULED then
		return
	end
	REBUILD_SCHEDULED = true
	task.defer(function()
		REBUILD_SCHEDULED = false
		rebuild()
	end)
end

local function keepWatch(disconnect: () -> ())
	table.insert(DISCONNECTS, disconnect)
end

local function deepWatch(path: string)
	if not isDir(path) then
		return
	end
	keepWatch(watchDirectory(path, function(_dir: string, _filename: string, _event: fs.WatchEvent)
		scheduleRebuild()
	end))
end

local indexWatchStarted = false

local function ensureIndexWatch()
	if indexWatchStarted then
		return
	end
	if not isDir("Packages/_Index") then
		return
	end
	indexWatchStarted = true
	deepWatch("Packages/_Index")
end

local function ensureWatching()
	if WATCHING then
		return
	end
	WATCHING = true

	-- Top-level redirects (React.lua, …); deep-watch only _Index for package sources.
	if isDir("Packages") then
		local handle = fs.watch("Packages", function(filename: string, _event: fs.WatchEvent)
			scheduleRebuild()
			if filename == "_Index" then
				ensureIndexWatch()
			end
		end)
		keepWatch(function()
			handle:close()
		end)
	end
	ensureIndexWatch()
end

local function ensureTree(projectRelativePath: string): rojo.Tree
	-- Do not start watchers here — open fs.watch handles keep lute's event loop
	-- alive and one-shot builds never exit. Watching starts via onChanged.
	local existing = TREES[projectRelativePath]
	if existing == nil then
		existing = build(projectRelativePath)
		TREES[projectRelativePath] = existing
	end
	return existing
end

local packages = {}

function packages.tree(projectRelativePath: string?): rojo.Tree
	return ensureTree(projectRelativePath or "Packages")
end

function packages.onChanged(callback: ChangedCallback): () -> ()
	ensureWatching()
	TOTAL_CHANGED_CALLBACKS += 1
	CHANGED_CALLBACKS[TOTAL_CHANGED_CALLBACKS] = callback

	return function()
		local index = table.find(CHANGED_CALLBACKS, callback)
		if index then
			CHANGED_CALLBACKS[index] = CHANGED_CALLBACKS[TOTAL_CHANGED_CALLBACKS]
			CHANGED_CALLBACKS[TOTAL_CHANGED_CALLBACKS] = nil
			TOTAL_CHANGED_CALLBACKS -= 1
		end
	end
end

return table.freeze(packages)
