--!strict

local Src = script.Parent
local Packages = Src.Parent.Packages
local React = require(Packages.React)

local Colors = require("./PluginGui/Colors")
local HelpGui = require("./PluginGui/HelpGui")
local SubPanel = require("./PluginGui/SubPanel")
local PluginGui = require("./PluginGui/PluginGui")
local OperationButton = require("./PluginGui/OperationButton")
local ChipForToggle = require("./PluginGui/ChipForToggle")
local Settings = require("./Settings")
local PluginGuiTypes = require("./PluginGui/Types")

local e = React.createElement

local function createNextOrder()
	local order = 0
	return function()
		order += 1
		return order
	end
end

local function RotateDirectionPanel(props: {
	Settings: Settings.MaterialFlipSettings,
	UpdatedSettings: () -> (),
	LayoutOrder: number?,
})
	local current = props.Settings.RotateDirection

	local function makeChip(text: string, direction: Settings.RotateDirection, layoutOrder: number)
		return e(ChipForToggle, {
			Text = text,
			IsCurrent = current == direction,
			LayoutOrder = layoutOrder,
			OnClick = function()
				props.Settings.RotateDirection = direction
				props.UpdatedSettings()
			end,
		})
	end

	return e(SubPanel, {
		Title = "Rotate Direction",
		LayoutOrder = props.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, {
		Chips = e(HelpGui.WithHelpIcon, {
			LayoutOrder = 1,
			Subject = e("Frame", {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, {
				ListLayout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),
				Clockwise = makeChip("Clockwise", "Clockwise", 1),
				CounterClockwise = makeChip("Counter", "CounterClockwise", 2),
			}),
			Help = e(HelpGui.BasicTooltip, {
				HelpRichText = "Which direction the material rotates around the clicked face.",
			}),
		}),
	})
end

local function CloseButton(props: {
	HandleAction: (string) -> (),
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		CancelButton = e(OperationButton, {
			Text = "Close <i>MaterialFlip</i>",
			Color = Colors.DARK_RED,
			Disabled = false,
			Height = 30,
			OnClick = function()
				props.HandleAction("cancel")
			end,
		}),
	})
end

local MATERIALFLIP_CONFIG: PluginGuiTypes.PluginGuiConfig = {
	PluginName = "MaterialFlip",
	PendingText = "...",
	TutorialElement = nil,
}

local function MaterialFlipGui(props: {
	GuiState: PluginGuiTypes.PluginGuiMode,
	CurrentSettings: Settings.MaterialFlipSettings,
	UpdatedSettings: () -> (),
	HandleAction: (string) -> (),
	Panelized: boolean,
})
	local currentSettings = props.CurrentSettings
	local nextOrder = createNextOrder()
	return e(PluginGui, {
		Config = MATERIALFLIP_CONFIG,
		State = {
			Mode = props.GuiState,
			Settings = currentSettings,
			UpdatedSettings = props.UpdatedSettings,
			HandleAction = props.HandleAction,
			Panelized = props.Panelized,
		},
	}, {
		RotateDirectionPanel = e(RotateDirectionPanel, {
			Settings = currentSettings,
			UpdatedSettings = props.UpdatedSettings,
			LayoutOrder = nextOrder(),
		}),
		CloseButton = e(CloseButton, {
			HandleAction = props.HandleAction,
			LayoutOrder = nextOrder(),
		}),
	})
end

return MaterialFlipGui
