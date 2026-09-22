-- Installs Roblox Studio on macOS and signs in with a .ROBLOSECURITY cookie.
-- Usage: lute scripts/installStudio.luau
-- Env: ROBLOX_COOKIE

local process = require("@std/process")
local io = require("@std/io")
local fs = require("@std/fs")
local net = require("@std/net")
local json = require("@std/json")
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

local function cstr(value: string): string
	return value .. "\0"
end

-- Apple Cookies.binarycookies writer (single page).
local function buildBinaryCookies(cookies: { { url: string, name: string, path: string, value: string } }): string
	local cookieBlobs = {}
	local now = os.time()
	local macCreate = now - 978307200
	local macExpiry = now + 86400 * 365 * 10 - 978307200

	for _, cookie in cookies do
		local urlB = cstr(cookie.url)
		local nameB = cstr(cookie.name)
		local pathB = cstr(cookie.path)
		local valueB = cstr(cookie.value)
		local headerLen = 56
		local urlOff = headerLen
		local nameOff = urlOff + #urlB
		local pathOff = nameOff + #nameB
		local valueOff = pathOff + #pathB
		local size = headerLen + #urlB + #nameB + #pathB + #valueB
		table.insert(
			cookieBlobs,
			table.concat({
				string.pack("<I4", size),
				string.pack("<I4", 0),
				string.pack("<I4", 1), -- Secure
				string.pack("<I4", 0),
				string.pack("<I4", urlOff),
				string.pack("<I4", nameOff),
				string.pack("<I4", pathOff),
				string.pack("<I4", valueOff),
				string.rep("\0", 8),
				string.pack("<d", macExpiry),
				string.pack("<d", macCreate),
				urlB,
				nameB,
				pathB,
				valueB,
			})
		)
	end

	local num = #cookieBlobs
	local cookieOffset = 12 + 4 * num
	local offsetParts = { string.pack(">I4", 0x00000100), string.pack("<I4", num) }
	local running = cookieOffset
	for _, blob in cookieBlobs do
		table.insert(offsetParts, string.pack("<I4", running))
		running += #blob
	end
	table.insert(offsetParts, string.pack("<I4", 0))
	for _, blob in cookieBlobs do
		table.insert(offsetParts, blob)
	end
	local page = table.concat(offsetParts)

	local checksum = 0
	for i = 1, #page, 4 do
		checksum = bit32.band(checksum + string.byte(page, i), 0xffffffff)
	end

	-- Empty binary plist metadata (`{}`)
	local emptyBplist =
		"bplist00\xd0\x08\x00\x00\x00\x00\x00\x00\x01\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x09"

	return table.concat({
		"cook",
		string.pack(">I4", 1),
		string.pack(">I4", #page),
		page,
		string.pack(">I4", checksum),
		string.char(0x07, 0x17, 0x20, 0x05, 0x00, 0x00, 0x00, 0x4b),
		emptyBplist,
	})
end

local function writeStudioCookie(cookie: string)
	local home = `{process.homedir()}`

	-- Legacy StudioBrowser plist (still read as a fallback by some tooling).
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

	-- Modern Studio auth: ~/Library/HTTPStorages/com.Roblox.RobloxStudio.binarycookies
	local cookies: { { url: string, name: string, path: string, value: string } } = {
		{ url = ".roblox.com", name = ".ROBLOSECURITY", path = "/", value = cookie },
	}

	local auth = net.request("https://users.roblox.com/v1/users/authenticated", {
		headers = {
			Cookie = `.ROBLOSECURITY={cookie}`,
			["User-Agent"] = "Roblox/Studio",
		},
	})
	if auth.ok then
		local user = json.deserialize(auth.body) :: { id: number? }
		if type(user.id) == "number" then
			local userId = tostring(user.id)
			io.write(`Authenticated as user {userId}\n`)
			table.insert(cookies, {
				url = ".roblox.com",
				name = "/RobloxStudioAuth/userid",
				path = "/",
				value = userId,
			})
			table.insert(cookies, {
				url = ".roblox.com",
				name = `/RobloxStudioAuth/.ROBLOSECURITY{userId}`,
				path = "/",
				value = cookie,
			})
		end
	else
		io.write(
			`Warning: cookie rejected by users.roblox.com ({auth.status}); writing storage anyway\n`
		)
	end

	local httpStorages = `{home}/Library/HTTPStorages`
	if not fs.exists(httpStorages) then
		fs.createDirectory(httpStorages, { makeParents = true })
	end
	fs.writeStringToFile(`{httpStorages}/com.Roblox.RobloxStudio.binarycookies`, buildBinaryCookies(cookies))
	io.write("Wrote Studio HTTPStorages binarycookies\n")

	-- Modern Studio also reads SharedROBLOSECURITYForStudio from the login
	-- keychain (acct+label set, svce empty). Missing → Authenticated:NO / -25300.
	local keychainAccount = "https://www.roblox.com/:SharedROBLOSECURITYForStudio"
	process.run({ "security", "delete-generic-password", "-a", keychainAccount })
	local added = process.run({
		"security",
		"add-generic-password",
		"-a",
		keychainAccount,
		"-s",
		"",
		"-l",
		keychainAccount,
		"-w",
		cookie,
		"-A", -- allow all apps; avoids interactive keychain prompts on CI
		"-U",
	})
	if not added.ok then
		error(`Failed to write Studio keychain cookie: {added.stderr}`)
	end
	io.write("Wrote Studio keychain SharedROBLOSECURITYForStudio\n")
end

local home = `{process.homedir()}`
-- Keep the full browser cookie value, including `_|WARNING:…|_`. Stripping that
-- prefix makes users.roblox.com / Studio reject it with 401.
local cookie = (process.env.ROBLOX_COOKIE :: string):match("^%s*(.-)%s*$") :: string
cookie = cookie:gsub("^%.ROBLOSECURITY=", "")
cookie = cookie:gsub("^ROBLOSECURITY=", "")

io.write("Validating ROBLOX_COOKIE\n")
local authCheck = net.request("https://users.roblox.com/v1/users/authenticated", {
	headers = {
		Cookie = `.ROBLOSECURITY={cookie}`,
		["User-Agent"] = "Roblox/Studio",
	},
})
if not authCheck.ok then
	error(`ROBLOX_COOKIE is invalid or expired (HTTP {authCheck.status}): {authCheck.body}`)
end
local authUser = json.deserialize(authCheck.body) :: { id: number?, name: string? }
io.write(`Cookie ok (user {authUser.name or authUser.id})\n`)

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

io.write("Writing Studio login cookie\n")
writeStudioCookie(cookie)

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
