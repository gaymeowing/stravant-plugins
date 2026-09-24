-- watch directory
-- recursively watches a directory tree (lute's fs.watch is not recursive)

local startsWith = require("@scripts/startsWith")
local task = require("@lute/task")
local fs = require("@lute/fs")

export type ChangeCallback = (dir: string, filename: string, event: fs.WatchEvent) -> ()

local DEFAULT_DEBOUNCE_SEC = 0.08

local function isDir(path: string): boolean
	return fs.exists(path) and fs.type(path) == "dir"
end

type PendingChange = {
	dir: string,
	filename: string,
	event: fs.WatchEvent,
}

--- Watch `path` and all current/future subdirectories (skips dot-dirs).
--- FS events are trailing-debounced on a reused timer thread, then flushed to `onChange`.
--- Returns a disconnect function — keep it reachable or GC closes the watchers.
local function watchDirectory(path: string, onChange: ChangeCallback, debounce: number?): () -> ()
	local pendingByPath = {} :: { [string]: PendingChange }
	local handles = {} :: { [string]: fs.WatchHandle }
	local watched = {} :: { [string]: boolean }
	local pendingOrder = {} :: { string }
	local disconnected = false
	local lastEventAt = 0
	local awoken = false

	debounce = debounce or DEFAULT_DEBOUNCE_SEC

	local timer = coroutine.create(function()
		while true do
			coroutine.yield()
			if disconnected then
				break
			end
			while awoken and not disconnected do
				local remaining = (debounce :: any) - (os.clock() - lastEventAt)
				if remaining > 0 then
					task.wait(remaining)
				else
					awoken = false
					local order = pendingOrder
					local byPath = pendingByPath
					pendingOrder = {}
					pendingByPath = {}
					-- Flush off this timer thread — yielding fs/process in onChange
					-- breaks lute (listdir returns a string, isDir lies, etc.).
					task.spawn(function()
						for _, key in order do
							if disconnected then
								break
							end
							local change = byPath[key]
							onChange(change.dir, change.filename, change.event)
						end
					end)
				end
			end
			if disconnected then
				break
			end
		end
	end)

	do
		local ok, err = coroutine.resume(timer)
		if not ok then
			error(err)
		end
	end

	local function kickTimer()
		lastEventAt = os.clock()
		awoken = true
		if coroutine.status(timer) == "suspended" then
			task.defer(timer)
		end
	end

	local function enqueue(dir: string, filename: string, event: fs.WatchEvent)
		local key = `{dir}/{filename}`
		if not pendingByPath[key] then
			table.insert(pendingOrder, key)
		end
		pendingByPath[key] = {
			filename = filename,
			event = event,
			dir = dir,
		}
		kickTimer()
	end

	local function unwatchTree(dir: string)
		local prefix = `{dir}/`
		local toClose = {} :: { string }
		if watched[dir] then
			table.insert(toClose, dir)
		end
		for watchedDir in watched do
			if startsWith(watchedDir, prefix) then
				table.insert(toClose, watchedDir)
			end
		end

		for _, watchedDir in toClose do
			local handle = handles[watchedDir]
			if handle ~= nil then
				handle:close()
				handles[watchedDir] = nil
			end
			watched[watchedDir] = nil
		end

		local keptOrder = {} :: { string }
		for _, key in pendingOrder do
			if key == dir or startsWith(key, prefix) then
				pendingByPath[key] = nil
			else
				table.insert(keptOrder, key)
			end
		end
		pendingOrder = keptOrder
	end

	local function watch(dir: string)
		if disconnected or watched[dir] or not isDir(dir) then
			return
		end
		watched[dir] = true

		handles[dir] = fs.watch(dir, function(filename: string, event: fs.WatchEvent)
			if disconnected then
				return
			end
			local childPath = `{dir}/{filename}`
			if isDir(childPath) then
				watch(childPath)
			elseif watched[childPath] then
				unwatchTree(childPath)
			end
			enqueue(dir, filename, event)
		end)

		for _, entry in fs.listdir(dir) do
			if entry.type == "dir" and not startsWith(entry.name, ".") then
				watch(`{dir}/{entry.name}`)
			end
		end
	end

	watch(path)

	return function()
		if disconnected then
			return
		end

		disconnected = true
		awoken = true

		if coroutine.status(timer) == "suspended" then
			task.defer(timer)
		end

		for _, handle in handles do
			handle:close()
		end
	end
end

return watchDirectory
