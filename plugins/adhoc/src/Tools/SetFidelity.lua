--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local RENDER_FIDELITY_OPTIONS = {
	"Automatic",
	"Precise",
	"Performance",
}

local COLLISION_FIDELITY_OPTIONS = {
	"Default",
	"Hull",
	"Box",
	"PreciseConvexDecomposition",
}

-- A row of toggle-style buttons for picking an enum value
local function EnumPicker(props: {
	Label: string,
	Options: { string },
	Value: string,
	OnChanged: (value: string) -> (),
	LayoutOrder: number?,
})
	local buttons: { [string]: any } = {}

	buttons.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	for i, option in props.Options do
		local isSelected = option == props.Value
		buttons[option] = e("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = if isSelected then Colors.ACTION_BLUE else Colors.GREY,
			AutoButtonColor = not isSelected,
			Text = option,
			TextColor3 = if isSelected then Colors.WHITE else Colors.OFFWHITE,
			Font = if isSelected then Enum.Font.SourceSansBold else Enum.Font.SourceSans,
			TextSize = 13,
			BorderSizePixel = 0,
			LayoutOrder = i,
			[React.Event.MouseButton1Click] = function()
				props.OnChanged(option)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Label = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = props.Label,
			TextColor3 = Colors.OFFWHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			LayoutOrder = 1,
		}),
		Buttons = e("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, buttons),
	})
end

local function SetFidelitySettings(props: ToolSettingsProps)
	local renderFidelity = props.GetSetting("RenderFidelity") :: string
	local collisionFidelity = props.GetSetting("CollisionFidelity") :: string

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		RenderPicker = e(EnumPicker, {
			Label = "RenderFidelity",
			Options = RENDER_FIDELITY_OPTIONS,
			Value = renderFidelity,
			OnChanged = function(value: string)
				props.SetSetting("RenderFidelity", value)
			end,
			LayoutOrder = 1,
		}),
		CollisionPicker = e(EnumPicker, {
			Label = "CollisionFidelity",
			Options = COLLISION_FIDELITY_OPTIONS,
			Value = collisionFidelity,
			OnChanged = function(value: string)
				props.SetSetting("CollisionFidelity", value)
			end,
			LayoutOrder = 2,
		}),
		ApplyButton = e("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Colors.ACTION_BLUE,
			AutoButtonColor = true,
			Text = "Apply to All Parts",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 16,
			BorderSizePixel = 0,
			LayoutOrder = 3,
			[React.Event.MouseButton1Click] = function()
				local id = ChangeHistoryService:TryBeginRecording("Set Fidelity")
				if not id then
					return
				end
				local renderEnum = (Enum.RenderFidelity :: any)[renderFidelity]
				local collisionEnum = (Enum.CollisionFidelity :: any)[collisionFidelity]
				local count = 0
				for _, desc in workspace:GetDescendants() do
					if desc:IsA("TriangleMeshPart") or desc:IsA("PartOperation") then
						desc.RenderFidelity = renderEnum
						desc.CollisionFidelity = collisionEnum
						count += 1
					end
				end
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				print("[SetFidelity] Updated " .. count .. " parts")
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

local SetFidelity: ToolTypes.ToolDefinition = {
	Id = "setFidelity",
	Name = "Set Fidelity",
	Description = "Set RenderFidelity and CollisionFidelity on all parts",

	DefaultSettings = {
		RenderFidelity = "Automatic",
		CollisionFidelity = "Default",
	},

	RenderSettings = SetFidelitySettings,
}

return SetFidelity
