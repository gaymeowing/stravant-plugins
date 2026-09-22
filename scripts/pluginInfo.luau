-- plugin info
-- gets info for a plugin

local toml = require("@batteries/toml")
local fs = require("@std/fs")

export type PluginInfo = {
	read version: string,
	read id: number,
}

local CACHED_INFOS = {} :: { [string]: PluginInfo }

local function VALIDATE_FIELD(
	raw: toml.Toml,
	fieldName: string,
	expectedType: string,
	expectedPattern: string?
): toml.TomlValue
	local fieldValue = raw[fieldName]

	if fieldValue == nil then
		error(`field '{fieldName}' isn't defined in the PLUGIN.toml for plugin '{plugin}'`)
	elseif
		(expectedPattern and type(fieldValue) == "string" and not string.match(fieldValue, expectedPattern))
		or type(fieldValue) ~= expectedType
	then
		error(`field '{fieldName}' in the PLUGIN.toml for plugin '{plugin}' is not type '{expectedType}'`)
	end
	return fieldValue
end

local function pluginInfo(plugin: string): PluginInfo
	local cached = CACHED_INFOS[plugin]

	if cached then
		return cached
	else
		local fileContents = fs.readFileToString(`plugins/{plugin}/PLUGIN.toml`)

		if not fileContents then
			error(`plugin '{plugin}' doesn't have a PLUGIN.toml`)
		end

		local success, raw = pcall(toml.deserialize, fileContents)

		if not success then
			error(`PLUGIN.toml for plugin '{plugin}' isn't valid TOML\ndeserialization error: {raw}`)
		end

		VALIDATE_FIELD(raw, "version", "semver", "%d+%.%d+%.%d+[%a%-]*")
		VALIDATE_FIELD(raw, "id", "number")

		CACHED_INFOS[plugin] = table.freeze(raw) :: any
		return raw :: any
	end
end

return pluginInfo
