--!strict

local InitialPosition = Vector2.new(24, 24)
local kSettingsKey = "materialFlipState"

local PluginGuiTypes = require("./PluginGui/Types")

export type RotateDirection = "Clockwise" | "CounterClockwise"

export type MaterialFlipSettings = PluginGuiTypes.PluginGuiSettings & {
	RotateDirection: RotateDirection,
	PreserveAttachments: boolean,
	PreserveDecals: boolean,
}

local function loadSettings(plugin: Plugin): MaterialFlipSettings
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
		DoneTutorial = if raw.DoneTutorial ~= nil then raw.DoneTutorial else false,
		HaveHelp = if raw.HaveHelp ~= nil then raw.HaveHelp else true,

		----

		RotateDirection = if raw.RotateDirection ~= nil then raw.RotateDirection else "Clockwise",
		PreserveAttachments = if raw.PreserveAttachments ~= nil then raw.PreserveAttachments else true,
		PreserveDecals = if raw.PreserveDecals ~= nil then raw.PreserveDecals else false,
	}
end
local function saveSettings(plugin: Plugin, settings: MaterialFlipSettings)
	plugin:SetSetting(kSettingsKey, {
		WindowPositionX = settings.WindowPosition.X,
		WindowPositionY = settings.WindowPosition.Y,
		WindowAnchorX = settings.WindowAnchor.X,
		WindowAnchorY = settings.WindowAnchor.Y,
		WindowHeightDelta = settings.WindowHeightDelta,
		DoneTutorial = settings.DoneTutorial,
		HaveHelp = settings.HaveHelp,

		----

		RotateDirection = settings.RotateDirection,
		PreserveAttachments = settings.PreserveAttachments,
		PreserveDecals = settings.PreserveDecals,
	})
end

return {
	Load = loadSettings,
	Save = saveSettings,
}
