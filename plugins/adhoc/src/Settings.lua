--!strict

local PluginGuiTypes = require("./PluginGui/Types")

local kSettingsKey = "adhocToolsState"
local InitialPosition = Vector2.new(24, 24)

export type AdhocSettings = PluginGuiTypes.PluginGuiSettings & {
	PinnedTools: { string },
	ToolSettings: { [string]: { [string]: any } },
	LastActiveTool: string?,
}

local function loadSettings(plugin: Plugin): AdhocSettings
	local raw = plugin:GetSetting(kSettingsKey) or {}
	return {
		WindowPosition = Vector2.new(
			raw.WindowPositionX or InitialPosition.X,
			raw.WindowPositionY or InitialPosition.Y
		),
		WindowAnchor = Vector2.new(
			raw.WindowAnchorX or 0,
			raw.WindowAnchorY or 0
		),
		WindowHeightDelta = if raw.WindowHeightDelta ~= nil then raw.WindowHeightDelta else 0,
		HaveHelp = if raw.HaveHelp ~= nil then raw.HaveHelp else true,
		DoneTutorial = if raw.DoneTutorial ~= nil then raw.DoneTutorial else true, -- No tutorial for this plugin
		PinnedTools = raw.PinnedTools or {},
		ToolSettings = raw.ToolSettings or {},
		LastActiveTool = raw.LastActiveTool,
	}
end

local function serializeValue(value: any): any
	if typeof(value) == "Color3" then
		return { value.R, value.G, value.B }
	elseif typeof(value) == "EnumItem" then
		return tostring(value)
	end
	return value
end

local function serializeToolSettings(toolSettings: { [string]: { [string]: any } }): { [string]: { [string]: any } }
	local result = {}
	for toolId, settings in toolSettings do
		local serialized = {}
		for key, value in settings do
			serialized[key] = serializeValue(value)
		end
		result[toolId] = serialized
	end
	return result
end

local function saveSettings(plugin: Plugin, settings: AdhocSettings)
	plugin:SetSetting(kSettingsKey, {
		WindowPositionX = settings.WindowPosition.X,
		WindowPositionY = settings.WindowPosition.Y,
		WindowAnchorX = settings.WindowAnchor.X,
		WindowAnchorY = settings.WindowAnchor.Y,
		WindowHeightDelta = settings.WindowHeightDelta,
		HaveHelp = settings.HaveHelp,
		DoneTutorial = settings.DoneTutorial,
		PinnedTools = settings.PinnedTools,
		ToolSettings = serializeToolSettings(settings.ToolSettings),
		LastActiveTool = settings.LastActiveTool,
	})
end

return {
	Load = loadSettings,
	Save = saveSettings,
}
