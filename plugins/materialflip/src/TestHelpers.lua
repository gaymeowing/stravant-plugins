--!strict

local Settings = require("./Settings")

local function makeTestSettings(): Settings.MaterialFlipSettings
	return {
		WindowPosition = Vector2.new(24, 24),
		WindowAnchor = Vector2.new(0, 0),
		WindowHeightDelta = 0,
		DoneTutorial = true,
		HaveHelp = true,

		RotateDirection = "Clockwise" :: Settings.RotateDirection,
	}
end

return {
	makeTestSettings = makeTestSettings,
}
