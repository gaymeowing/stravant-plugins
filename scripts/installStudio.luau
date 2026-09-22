-- Installs Roblox Studio on macOS and signs in with a .ROBLOSECURITY cookie.
-- Usage: lute scripts/installStudio.luau
-- Env: ROBLOX_COOKIE

local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")
local net = require("@std/net")
local task = require("@std/task")

local function xmlEscape(value: string): string
	return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function copyTree(src: string, dest: string)
	local entryType = fs.type(src)
	if entryType == "dir" then
		if not fs.exists(dest) then
			fs.createDirectory(dest, { makeParents = true })
		end
		for _, entry in fs.listDirectory(src) do
			copyTree(`{src}/{entry.name}`, `{dest}/{entry.name}`)
		end
		return
	end

	local parent = dest:match("^(.*)/[^/]+$")
	if parent and not fs.exists(parent) then
		fs.createDirectory(parent, { makeParents = true })
	end
	fs.copy(src, dest)
end

local home = `{process.homedir()}`
local cookie = (process.env.ROBLOX_COOKIE :: string):match("^%s*(.-)%s*$") :: string
if cookie:match("WARNING:") then
	cookie = (cookie:match("WARNING:[^_]*_(.+)$") or cookie)
end

io.write("Writing Studio login cookie to preferences\n")
local prefsDir = `{home}/Library/Preferences`
if not fs.exists(prefsDir) then
	fs.createDirectory(prefsDir, { makeParents = true })
end
local cookieValue = `SEC::,EXP::<9999-01-01T00:00:00Z>,COOK::<{cookie}>`
fs.writeStringToFile(
	`{prefsDir}/com.roblox.RobloxStudioBrowser.plist`,
	table.concat({
		`<?xml version="1.0" encoding="UTF-8"?>`,
		`<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">`,
		`<plist version="1.0">`,
		`<dict>`,
		`\t<key>roblox.com..ROBLOSECURITY</key>`,
		`\t<string>{xmlEscape(cookieValue)}</string>`,
		`</dict>`,
		`</plist>`,
		``,
	}, "\n")
)

local dmg = "/tmp/RobloxStudio.dmg"
io.write("Downloading Studio DMG\n")
local response = net.request("https://setup.rbxcdn.com/mac/RobloxStudio.dmg")
if not response.ok then
	error(`Failed to download Studio DMG (HTTP {response.status})`)
end
fs.writeStringToFile(dmg, response.body)

io.write("Mounting DMG\n")
local attach = process.run({ "hdiutil", "attach", dmg, "-nobrowse", "-readonly" })
if not attach.ok then
	error(attach.stderr)
end

local volume: string? = nil
for line in string.gmatch(attach.stdout :: string, "[^\r\n]+") do
	local mount = line:match("(/Volumes/.+)$")
	if mount then
		volume = mount:match("^%s*(.-)%s*$")
	end
end
if volume == nil then
	error("Could not find mounted Studio volume")
end

local installerSrc: string? = nil
for _, entry in fs.listDirectory(volume) do
	if entry.type == "dir" and entry.name:match("%.app$") then
		installerSrc = `{volume}/{entry.name}`
		break
	end
end
if installerSrc == nil then
	error(`No .app on volume {volume}`)
end

local installer = "/Applications/RobloxStudioInstaller.app"
io.write(`Installing from {installerSrc}\n`)
if fs.exists(installer) then
	fs.removeDirectory(installer, { recursive = true })
end
copyTree(installerSrc, installer)

io.write("Running Studio installer\n")
local opened = process.run({ "open", "-W", installer })
if not opened.ok then
	error(opened.stderr)
end

local studioApp = "/Applications/RobloxStudio.app"
local studioBin = `{studioApp}/Contents/MacOS/RobloxStudio`
local found = false
for _ = 1, 480 do
	if fs.exists(studioBin) then
		found = true
		break
	end
	task.wait(1)
end
if not found then
	error("Timed out waiting for RobloxStudio.app")
end

io.write(`Studio installed at {studioApp}\n`)
process.run({ "pkill", "-x", "RobloxStudio" })
task.wait(2)

local pluginsDir = `{home}/Documents/Roblox/Plugins`
if not fs.exists(pluginsDir) then
	fs.createDirectory(pluginsDir, { makeParents = true })
end

local autoSaves = `{home}/Documents/ROBLOX/AutoSaves`
if fs.exists(autoSaves) then
	fs.removeDirectory(autoSaves, { recursive = true })
end

process.run({ "hdiutil", "detach", volume })
if fs.exists(dmg) then
	fs.remove(dmg)
end
if fs.exists(installer) then
	fs.removeDirectory(installer, { recursive = true })
end

io.write("Roblox Studio install complete\n")
