-- Builds changed plugins and creates a draft GitHub release for TAG.
-- Usage: lute scripts/createReleases.luau

local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")

local plugins = require("./plugins")

local tag = process.env.TAG :: string

local function isSharedPath(path: string): boolean
	return string.match(path, "^libraries/") ~= nil
		or path == "wally.toml"
		or path == "wally.lock"
		or path == "scripts/build.luau"
		or path == "scripts/plugins.luau"
		or path == "foreman.toml"
end

local function previousTag(): string?
	local result = process.run({ "git", "describe", "--tags", "--abbrev=0", `{tag}^` })
	if not result.ok then
		return nil
	end
	local prev = (result.stdout :: string):match("%S+")
	if prev == nil or prev == "" then
		return nil
	end
	return prev
end

local function changedPluginNames(prev: string?): { string }
	if prev == nil then
		io.write("No previous tag; releasing all plugins\n")
		local names = {}
		for _, plugin in plugins.list() do
			table.insert(names, plugin.name)
		end
		return names
	end

	io.write(`Comparing {prev}...{tag}\n`)
	local diff = process.run({ "git", "diff", "--name-only", `{prev}...{tag}` })
	if not diff.ok then
		error(diff.stderr)
	end

	local files = {}
	for line in string.gmatch(diff.stdout :: string, "[^\r\n]+") do
		if line ~= "" then
			table.insert(files, line)
		end
	end

	for _, path in files do
		if isSharedPath(path) then
			io.write("Shared paths changed; releasing all plugins\n")
			local names = {}
			for _, plugin in plugins.list() do
				table.insert(names, plugin.name)
			end
			return names
		end
	end

	local seen: { [string]: boolean } = {}
	local names = {}
	for _, path in files do
		local name = string.match(path, "^plugins/([^/]+)/")
		if name and not seen[name] and fs.exists(`plugins/{name}`) and fs.type(`plugins/{name}`) == "dir" then
			seen[name] = true
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

local names = changedPluginNames(previousTag())
if #names == 0 then
	io.write("No plugin changes; skipping release\n")
	process.exit(0)
end

io.write("Changed plugins:\n")
for _, name in names do
	io.write(`  {name}\n`)
end

if fs.exists("build") then
	fs.removeDirectory("build", { recursive = true })
end
fs.createDirectory("build", { makeParents = true })

for _, name in names do
	local build = process.run({ "lute", "scripts/build.luau", name, "--out", "build" })
	if not build.ok then
		if build.stdout ~= "" then
			io.write(build.stdout)
		end
		error(build.stderr)
	end
	if build.stdout ~= "" then
		io.write(build.stdout)
	end
end

local assets = {}
for _, entry in fs.listDirectory("build") do
	if entry.type == "file" and entry.name:match("%.rbxmx$") then
		table.insert(assets, `build/{entry.name}`)
	end
end
table.sort(assets)
if #assets == 0 then
	error("No .rbxmx artifacts to upload")
end

local args = {
	"gh",
	"release",
	"create",
	tag,
	"--draft",
	"--generate-notes",
	"--title",
	tag,
}
for _, asset in assets do
	table.insert(args, asset)
end

io.write(`Creating draft release {tag} with {#assets} asset(s)\n`)
local created = process.run(args)
if not created.ok then
	error(created.stderr)
end
if created.stdout ~= "" then
	io.write(created.stdout)
end
