local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local function cframeToArray(cf: CFrame): { number }
	return { cf:GetComponents() }
end

local function arrayToCFrame(arr: { number }): CFrame
	return CFrame.new(
		arr[1], arr[2], arr[3],
		arr[4], arr[5], arr[6],
		arr[7], arr[8], arr[9],
		arr[10], arr[11], arr[12]
	)
end

local function SaveRow(props: {
	Name: string,
	OnLoad: () -> (),
	OnRename: (newName: string) -> (),
	OnDelete: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)
	local isRenaming, setIsRenaming = React.useState(false)
	local renameBoxRef = React.useRef(nil :: TextBox?)

	-- Focus the rename box when entering rename mode
	React.useEffect(function()
		if isRenaming and renameBoxRef.current then
			renameBoxRef.current:CaptureFocus()
			renameBoxRef.current.SelectionStart = 1
			renameBoxRef.current.CursorPosition = #renameBoxRef.current.Text + 1
		end
	end, { isRenaming })

	if isRenaming then
		return e("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Colors.GREY,
			BorderSizePixel = 0,
			LayoutOrder = props.LayoutOrder,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
			RenameBox = e("TextBox", {
				ref = renameBoxRef,
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = props.Name,
				TextColor3 = Colors.WHITE,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				ClearTextOnFocus = false,
				[React.Event.FocusLost] = function(rbx: TextBox, enterPressed: boolean)
					local newName = rbx.Text
					if newName ~= "" and newName ~= props.Name then
						props.OnRename(newName)
					end
					setIsRenaming(false)
				end,
			}),
		})
	end

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = if isHovered then Colors.GREY else Colors.BLACK,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = props.OnLoad,
		[React.Event.MouseEnter] = function()
			setIsHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setIsHovered(false)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 4),
		}),
		NameLabel = e("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = props.Name,
			TextColor3 = Colors.WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.SourceSans,
			TextSize = 16,
			LayoutOrder = 1,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
		RenameButton = e("TextButton", {
			Size = UDim2.fromOffset(52, 26),
			BackgroundColor3 = Colors.GREY,
			AutoButtonColor = true,
			Text = "Rename",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			LayoutOrder = 2,
			[React.Event.MouseButton1Click] = function()
				setIsRenaming(true)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
		DeleteButton = e("TextButton", {
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Color3.fromRGB(180, 40, 40),
			AutoButtonColor = true,
			Text = "X",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			LayoutOrder = 3,
			[React.Event.MouseButton1Click] = props.OnDelete,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

local function SaveCameraSettings(props: ToolSettingsProps)
	local saves = props.GetSetting("Saves") :: { { Name: string, CFrame: { number } } }

	local children: { [string]: any } = {}

	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	children.SaveButton = e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Colors.ACTION_BLUE,
		AutoButtonColor = true,
		Text = "+ Save Current View",
		TextColor3 = Colors.WHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		[React.Event.MouseButton1Click] = function()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local newSaves = table.clone(saves)
			table.insert(newSaves, 1, {
				Name = "View " .. (#saves + 1),
				CFrame = cframeToArray(camera.CFrame),
			})
			props.SetSetting("Saves", newSaves)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
	})

	if #saves == 0 then
		children.Empty = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "No saved views yet.",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			LayoutOrder = 2,
		})
	end

	for i, save in saves do
		children["Save" .. i] = e(SaveRow, {
			Name = save.Name,
			OnLoad = function()
				local camera = workspace.CurrentCamera
				if camera then
					camera.CFrame = arrayToCFrame(save.CFrame)
				end
			end,
			OnRename = function(newName: string)
				local newSaves = table.clone(saves)
				newSaves[i] = table.clone(save)
				newSaves[i].Name = newName
				props.SetSetting("Saves", newSaves)
			end,
			OnDelete = function()
				local newSaves = table.clone(saves)
				table.remove(newSaves, i)
				props.SetSetting("Saves", newSaves)
			end,
			LayoutOrder = i + 2,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local SaveCamera: ToolTypes.ToolDefinition = {
	Id = "saveCamera",
	Name = "Camera Bookmarks",
	Description = "Save and restore camera positions",

	DefaultSettings = {
		Saves = {},
	},

	RenderSettings = SaveCameraSettings,
}

return SaveCamera
