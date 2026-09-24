-- Creates a draft GitHub release per plugin whose PLUGIN.toml Version has no
-- matching `{Name}@{Version}` release yet (luauberries-style).
-- Usage: lute scripts/createReleases.luau
-- Env: GH_TOKEN

local plugins = require("@scripts/plugins")
local process = require("@std/process")
local json = require("@std/json")
local fs = require("@std/fs")

local REPO_URL = "https://github.com/gaymeowing/stravant-plugins"
local COMMIT_URL = `{REPO_URL}/commits/`
local PULL_URL = `{REPO_URL}/pull/`

local function reverse<V>(t: { V }): { V }
	local length = #t
	for index = 1, length // 2 do
		local swapIndex = (length - index) + 1
		t[index], t[swapIndex] = t[swapIndex], t[index]
	end
    return t
end

local function releaseExists(tag: string): boolean
	local result = process.run({ "gh", "release", "view", tag })
	return result.ok
end

local function commitFromTag(tag: string): string?
	local result = process.run({ "git", "show-ref", "--hash", tag })
	if not result.ok then
		return nil
	end
	return (result.stdout :: string):match("%x+")
end

local function latestReleaseTag(pluginName: string): string?
	local result = process.run({ "git", "tag", "--sort=-creatordate", "-l", `{pluginName}@*` })
	if not result.ok then
		return nil
	end
	return (result.stdout :: string):match("[^\r\n]+")
end

local function commitUnixTime(commit: string): number?
	local result = process.run({
		"git",
		"show",
		"--pretty=format:%ad",
		"--date=unix",
		"--no-patch",
		commit,
	})
	if not result.ok then
		return nil
	end
	return tonumber((result.stdout :: string):match("%d+"))
end

local function lastReleasedCommitTime(pluginName: string): number?
	local tag = latestReleaseTag(pluginName)
	if tag ~= nil then
		local commit = commitFromTag(tag)
		if commit ~= nil then
			return commitUnixTime(commit)
		end
	end

	local result = process.run({
		"git",
		"log",
		"--pretty=format:%H",
		"-n1",
		"--",
		`plugins/{pluginName}`,
	})
	if not result.ok then
		return nil
	end
	local commit = (result.stdout :: string):match("%x+")
	if commit == nil then
		return nil
	end
	return commitUnixTime(commit)
end


local function commitsAfter(pluginName: string, afterUnix: number): { string }
	local result = process.run({
		"git",
		"log",
		`--after={afterUnix}`,
		"--no-merges",
		"--author-date-order",
		"--pretty=format:%H",
		"--",
		`plugins/{pluginName}`,
	})
	if not result.ok or result.stdout == "" then
		return {}
	end
	local commits = {} :: { string }
	for hash in string.gmatch(result.stdout :: string, "%x+") do
		table.insert(commits, hash)
	end
	-- git log is newest-first; release notes read oldest-first
	return reverse(commits)
end

local function commitInfo(commit: string): (string, string)
	local result = process.run({
		"git",
		"show",
		"-s",
		"--format=%an%n%s",
		commit,
	})
	if not result.ok then
		return "unknown", commit
	end
	local author, title = string.match(result.stdout :: string, "^([^\r\n]+)\r?\n([^\r\n]*)")
	return author or "unknown", title or commit
end

local function mergedPullRequestsAfter(
	pluginName: string,
	afterUnix: number
): { { number: number, title: string, author: string } }
	local result = process.run({
		"gh",
		"pr",
		"list",
		"--state",
		"merged",
		"--limit",
		"100",
		"--json",
		"number,title,author,mergedAt,files",
	})
	if not result.ok then
		return {}
	end
	local data = json.deserialize(result.stdout)
	if type(data) ~= "table" then
		return {}
	end

	local pathPrefix = `plugins/{pluginName}/`
	local pulls = {}
	for _, pull in data :: { any } do
		local mergedAt = pull.mergedAt
		if type(mergedAt) ~= "string" then
			continue
		end
		-- mergedAt is ISO8601; compare via gh/git roughly by parsing unix if possible.
		-- Fall back: include if any file touches this plugin and mergedAt sorts after afterUnix via `date`.
		local mergedUnixResult = process.run({ "date", "-u", "-j", "-f", "%Y-%m-%dT%H:%M:%SZ", mergedAt, "+%s" })
		if not mergedUnixResult.ok then
			-- GNU date (ubuntu runners)
			mergedUnixResult = process.run({ "date", "-u", "-d", mergedAt, "+%s" })
		end
		local mergedUnix = tonumber((mergedUnixResult.stdout :: string):match("%d+"))
		if mergedUnix == nil or mergedUnix <= afterUnix then
			continue
		end

		local touchesPlugin = false
		if type(pull.files) == "table" then
			for _, file in pull.files do
				local path = if type(file) == "table" then file.path else nil
				if type(path) == "string" and string.sub(path, 1, #pathPrefix) == pathPrefix then
					touchesPlugin = true
					break
				end
			end
		end
		if not touchesPlugin then
			continue
		end

		local author = "unknown"
		if type(pull.author) == "table" then
			local login = (pull.author :: { login: string? }).login
			if type(login) == "string" then
				author = login
			end
		end

		table.insert(pulls, {
			number = pull.number,
			title = pull.title,
			author = author,
		})
	end
	return pulls
end

local function buildNotes(pluginName: string, afterUnix: number): string
	local lines = { "## What's changed", "" }

	for _, pull in mergedPullRequestsAfter(pluginName, afterUnix) do
		table.insert(lines, `* {pull.title} by @{pull.author} in {PULL_URL}{pull.number}`)
	end

	for _, commit in commitsAfter(pluginName, afterUnix) do
		local author, title = commitInfo(commit)
		table.insert(lines, `* {title} by @{author} in [{commit}]({COMMIT_URL}{commit})`)
	end

	if #lines == 2 then
		table.insert(lines, "* No commits since the previous release.")
	end

	return table.concat(lines, "\n")
end

local function releasePlugin(plugin: plugins.PluginInfo)
	local pluginName = plugin.name
	local version = plugin.version
	local releaseTag = `{pluginName}@{version}`

	print(`Releasing {releaseTag}\n`)

	if fs.exists("build") then
		fs.removeDirectory("build", { recursive = true })
	end
	fs.createDirectory("build", { makeParents = true })

	local build = process.run({ "lute", "scripts/build.luau", pluginName, "--out", "build", "--rbxm" })
	if not build.ok then
		if build.stdout ~= "" then
			print(build.stdout)
		end
		error(build.stderr)
	end
	if build.stdout ~= "" then
		print(build.stdout)
	end

	local asset = `build/{pluginName}.rbxm`
	if not fs.exists(asset) then
		error(`Missing build artifact {asset}`)
	end

	local afterUnix = lastReleasedCommitTime(pluginName) or 0
	local notes = buildNotes(pluginName, afterUnix)
	local notesFile = `build/{pluginName}-notes.md`
	fs.writeStringToFile(notesFile, notes)

	local created = process.run({
		"gh",
		"release",
		"create",
		releaseTag,
		"--draft",
		"--title",
		`{pluginName} v{version}`,
		"--notes-file",
		notesFile,
		asset,
	})
	if not created.ok then
		error(created.stderr)
	end
	if created.stdout ~= "" then
		print(created.stdout)
	end
end

local released = 0
for _, plugin in plugins.list() do
	local version = plugin.version
	local releaseTag = `{plugin.name}@{version}`
	if releaseExists(releaseTag) then
		print(`{releaseTag} already exists; skipping\n`)
		continue
	end
	releasePlugin(plugin)
	released += 1
end

if released == 0 then
	print("No unreleased PLUGIN.toml versions; nothing to do\n")
end
