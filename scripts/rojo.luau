-- rojo
-- rojo utility module

local json = require("@std/json")
local fs = require("@std/fs")

type ProjectNodePrototype = {
	--- Ensure `key` is a classed instance. Returns the child node.
	addClass: (node: Tree | Project, key: string, className: string) -> Tree,
	--- Mount a file/dir at `key`. Returns the child node.
	addScript: (node: Tree | Project, key: string, path: string) -> Tree,
	--- Serialize this tree/project to `path` as JSON.
	write: (node: Tree | Project, path: string, pretty: boolean?) -> (),
	__index: ProjectNodePrototype,
}

type ProjectPrototype = setmetatable<{
	__index: ProjectNodePrototype,
}, ProjectNodePrototype>

--- Tree node as used in Rojo project files (`$path` / `$className` + children).
export type Tree = setmetatable<{
	["$className"]: string?,
	["$path"]: string?,
}, ProjectNodePrototype> & {
	[string]: Tree, -- this has to be done like this otherwise the type solver will kick & scream
}

--- Rojo project (`name` / `globIgnorePaths` / `tree`).
export type Project = setmetatable<{
	globIgnorePaths: { string },
	emitLegacyScripts: boolean,
	name: string,
	tree: Tree,
}, ProjectPrototype>

local project_node = {} :: ProjectNodePrototype
project_node.__index = project_node

local project = setmetatable({}, project_node) :: ProjectPrototype
project.__index = project_node

local function targetTree(node: Tree | Project): Tree
	if getmetatable(node :: any) == project then
		return node.tree
	end
	return node :: Tree
end

function project_node.addScript(node, key, path)
	local parent = targetTree(node)
	local child = setmetatable({
		["$path"] = path,
	}, project_node) :: Tree
	parent[key] = child
	return child
end

function project_node.addClass(node, key, className)
	local parent = targetTree(node)
	local existing = parent[key]
	local child: Tree

	if type(existing) == "table" then
		child = existing :: Tree
		child["$className"] = className

		-- allows for keys being plain tables
		if getmetatable(child) ~= project_node then
			setmetatable(child, project_node)
		end
	else
		child = setmetatable({
			["$className"] = className,
		}, project_node) :: Tree
		parent[key] = child
	end
	return child :: any
end

function project_node.write(node, path)
	fs.writeStringToFile(path, json.serialize(node :: any) .. "\n")
end

local rojo = {}

function rojo.tree(className: string?): Tree
	return setmetatable({
		["$className"] = className
	}, project_node) :: any
end

function rojo.project(name: string, className: string?, emitLegacyScripts: boolean?): Project
	return setmetatable({
		emitLegacyScripts = emitLegacyScripts or false,
		tree = rojo.tree(className or "Folder"),
		globIgnorePaths = {},
		name = name,
	}, project) :: Project
end

do
	table.freeze(project_node)
	table.freeze(project)
end

return table.freeze(rojo)
