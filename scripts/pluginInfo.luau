-- plugin info
-- gets info for a plugin

local toml = require("@batteries/toml")
local fs = require("@std/fs")

export type PluginInfo = {
	read version: string,
	read id: number,
}

local CACHED_INFOS = {} :: { [string]: PluginInfo? }

local function VALIDATE_FIELD(
	pluginName: string,
	raw: toml.Toml,
	fieldName: string,
	expectedType: string,
	expectedPattern: string?
): toml.TomlValue
	local fieldValue = raw[fieldName]

	if fieldValue == nil then
		error(`field '{fieldName}' isn't defined in the PLUGIN.toml for plugin '{pluginName}'`)
	elseif
		(expectedPattern and type(fieldValue) == "string" and not string.match(fieldValue, expectedPattern))
		or type(fieldValue) ~= expectedType
	then
		error(`field '{fieldName}' in the PLUGIN.toml for plugin '{pluginName}' is not type '{expectedType}'`)
	end
	return fieldValue
end

local function pluginInfo(pluginName: string): PluginInfo
	local cached = CACHED_INFOS[pluginName]

	if cached then
		return cached
	end

	local fileContents = fs.readFileToString(`plugins/{pluginName}/PLUGIN.toml`)

	if not fileContents then
		error(`plugin '{pluginName}' doesn't have a PLUGIN.toml`)
	end

	local raw = toml.deserialize(fileContents)

	VALIDATE_FIELD(pluginName, raw, "version", "semver", "%d+%.%d+%.%d+[%a%-]*")
	VALIDATE_FIELD(pluginName, raw, "id", "number")

	local info = table.freeze(raw) :: any
	CACHED_INFOS[pluginName] = info
	return info
end

return pluginInfo
