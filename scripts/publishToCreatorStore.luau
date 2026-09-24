local plugins = require("@scripts/plugins")
local process = require("@std/process")
local json = require("@std/json")
local task = require("@std/task")
local net = require("@std/net")
local fs = require("@std/fs")

local apiKey = process.env.ROBLOX_API_KEY :: string
local tag = process.env.TAG :: string

local downloadDir = "build/publish-download"
if fs.exists(downloadDir) then
	fs.removeDirectory(downloadDir, { recursive = true })
end
fs.createDirectory(downloadDir, { makeParents = true })

print(`Downloading .rbxm from release {tag}\n`)
local download = process.run({
	"gh",
	"release",
	"download",
	tag,
	"--dir",
	downloadDir,
	"--pattern",
	"*.rbxm",
})
if not download.ok then
	error(download.stderr)
end

local function pollOperation(operationPath: string)
	local url = if string.find(operationPath, "^https?://", 1) ~= nil
		then operationPath
		else `https://apis.roblox.com/assets/v1/{operationPath}`

	for _ = 1, 60 do
		local response = net.request(url, {
			headers = { ["x-api-key"] = apiKey },
		})
		if response.ok then
			local op = json.deserialize(response.body) :: { [string]: any }
			if op.done == true then
				if op.error ~= nil then
					error(`Upload failed: {json.serialize(op.error)}`)
				end
				return
			end
		end
		task.wait(2)
	end
	error("Timed out waiting for asset operation.")
end

local function publishRbxm(path: string)
	local filename = path:match("([^/\\]+)$") or path
	local name = filename:match("^(.*)%.rbxm$")
	if not name then
		error(`Not an .rbxm: {path}`)
	end
	if not fs.exists(`plugins/{name}`) then
		error(`Unknown plugin: {name}`)
	end

	local info = plugins.get(name)
	local assetId = info.id
	if assetId == nil then
		error(`{name} has no Id in PLUGIN.toml (local-only plugin); skipping Creator Store publish`)
	end
	print(`Publishing {name} → asset {assetId}\n`)
	local response = net.request(`https://apis.roblox.com/assets/v1/assets/{assetId}`, {
		method = "PATCH",
		headers = {
			["x-api-key"] = apiKey,
			["Content-Type"] = "application/json",
		},
		body = json.serialize({
			assetType = "Plugin",
			assetId = assetId,
			displayName = name,
			description = `{name} Studio plugin`,
			fileContent = fs.readFileToString(path),
		}),
	})

	if not response.ok then
		error(`Publish error ({response.status}): {response.body}`)
	end

	local result = json.deserialize(response.body) :: { [string]: any }
	if type(result.path) == "string" and result.path ~= "" then
		pollOperation(result.path)
		return
	end
	if result.done ~= true or result.error ~= nil then
		error(`Publish incomplete: {response.body}`)
	end
end

local found = false
for _, entry in fs.listDirectory(downloadDir) do
	if entry.type == "file" and entry.name:match("%.rbxm$") then
		found = true
		publishRbxm(`{downloadDir}/{entry.name}`)
	end
end

if not found then
	error(`No .rbxm assets on release {tag}`)
end
