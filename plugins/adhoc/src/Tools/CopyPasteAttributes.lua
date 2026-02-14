--!strict
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

type SerializedValue = string | number | boolean | { [string]: any }
type AttributeSet = {
	Name: string,
	Attributes: { [string]: SerializedValue },
}

-- Serialize an attribute value for storage via plugin:SetSetting
local function serializeAttribute(value: any): SerializedValue?
	local t = typeof(value)
	if t == "string" or t == "number" or t == "boolean" then
		return value
	elseif t == "Color3" then
		return { _type = "Color3", R = value.R, G = value.G, B = value.B }
	elseif t == "Vector3" then
		return { _type = "Vector3", X = value.X, Y = value.Y, Z = value.Z }
	elseif t == "Vector2" then
		return { _type = "Vector2", X = value.X, Y = value.Y }
	elseif t == "BrickColor" then
		return { _type = "BrickColor", Number = value.Number }
	elseif t == "CFrame" then
		return { _type = "CFrame", Components = { value:GetComponents() } }
	elseif t == "UDim" then
		return { _type = "UDim", Scale = value.Scale, Offset = value.Offset }
	elseif t == "UDim2" then
		return {
			_type = "UDim2",
			XScale = value.X.Scale,
			XOffset = value.X.Offset,
			YScale = value.Y.Scale,
			YOffset = value.Y.Offset,
		}
	elseif t == "NumberRange" then
		return { _type = "NumberRange", Min = value.Min, Max = value.Max }
	elseif t == "Rect" then
		return {
			_type = "Rect",
			MinX = value.Min.X,
			MinY = value.Min.Y,
			MaxX = value.Max.X,
			MaxY = value.Max.Y,
		}
	else
		warn("[CopyPasteAttributes] Unsupported attribute type: " .. t)
		return nil
	end
end

-- Deserialize a stored attribute value back to its Roblox type
local function deserializeAttribute(data: SerializedValue): any
	if type(data) ~= "table" then
		return data
	end
	local tbl = data :: { [string]: any }
	local t = tbl._type
	if t == "Color3" then
		return Color3.new(tbl.R, tbl.G, tbl.B)
	elseif t == "Vector3" then
		return Vector3.new(tbl.X, tbl.Y, tbl.Z)
	elseif t == "Vector2" then
		return Vector2.new(tbl.X, tbl.Y)
	elseif t == "BrickColor" then
		return BrickColor.new(tbl.Number)
	elseif t == "CFrame" then
		local c = tbl.Components :: { number }
		return CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	elseif t == "UDim" then
		return UDim.new(tbl.Scale, tbl.Offset)
	elseif t == "UDim2" then
		return UDim2.new(tbl.XScale, tbl.XOffset, tbl.YScale, tbl.YOffset)
	elseif t == "NumberRange" then
		return NumberRange.new(tbl.Min, tbl.Max)
	elseif t == "Rect" then
		return Rect.new(tbl.MinX, tbl.MinY, tbl.MaxX, tbl.MaxY)
	else
		return data
	end
end

-- Copy all attributes from an instance into a serialized set
local function copyAttributes(instance: Instance): { [string]: SerializedValue }
	local attrs: { [string]: SerializedValue } = {}
	for name, value in instance:GetAttributes() do
		local serialized = serializeAttribute(value)
		if serialized ~= nil then
			attrs[name] = serialized
		end
	end
	return attrs
end

-- Paste a serialized attribute set onto an instance
local function pasteAttributes(instance: Instance, attrs: { [string]: SerializedValue })
	for name, data in attrs do
		local value = deserializeAttribute(data)
		instance:SetAttribute(name, value)
	end
end

-- Count entries in a dictionary
local function countAttributes(attrs: { [string]: SerializedValue }): number
	local count = 0
	for _ in attrs do
		count += 1
	end
	return count
end

-- Row component for an attribute set
local function SetRow(props: {
	Name: string,
	AttrCount: number,
	IsSelected: boolean,
	OnSelect: () -> (),
	OnRename: (newName: string) -> (),
	OnDelete: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)
	local isRenaming, setIsRenaming = React.useState(false)
	local renameBoxRef = React.useRef(nil :: TextBox?)

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

	local bgColor = Colors.BLACK
	if props.IsSelected then
		bgColor = Colors.ACTION_BLUE
	elseif isHovered then
		bgColor = Colors.GREY
	end

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = props.OnSelect,
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
		CountBadge = e("TextLabel", {
			Size = UDim2.fromOffset(30, 20),
			BackgroundColor3 = Colors.GREY,
			Text = tostring(props.AttrCount),
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			LayoutOrder = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
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
			LayoutOrder = 3,
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
			LayoutOrder = 4,
			[React.Event.MouseButton1Click] = props.OnDelete,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

local function CopyPasteAttributesSettings(props: ToolSettingsProps)
	local sets = props.GetSetting("Sets") :: { AttributeSet }
	local activeSet = props.GetSetting("ActiveSet") :: number

	local children: { [string]: any } = {}

	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	-- "Copy from Selection" button
	children.CopyButton = e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Colors.ACTION_BLUE,
		AutoButtonColor = true,
		Text = "+ Copy from Selection",
		TextColor3 = Colors.WHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		[React.Event.MouseButton1Click] = function()
			local selected = Selection:Get()
			if #selected == 0 then
				return
			end
			-- Copy from the first selected instance
			local source = selected[1]
			local attrs = copyAttributes(source)
			local newSets = table.clone(sets)
			table.insert(newSets, 1, {
				Name = source.Name .. " Attributes",
				Attributes = attrs,
			})
			props.SetSetting("Sets", newSets)
			-- Adjust active set index since we inserted at 1
			if activeSet > 0 then
				props.SetSetting("ActiveSet", activeSet + 1)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
	})

	-- "Paste to Selection" button (only when a set is active)
	if activeSet > 0 and activeSet <= #sets then
		children.PasteToSelection = e("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Colors.ACTION_BLUE,
			AutoButtonColor = true,
			Text = "Paste to Selection",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 16,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			[React.Event.MouseButton1Click] = function()
				local selected = Selection:Get()
				if #selected == 0 then
					return
				end
				local id = ChangeHistoryService:TryBeginRecording("Paste Attributes to Selection")
				if not id then
					return
				end
				local attrs = sets[activeSet].Attributes
				for _, inst in selected do
					pasteAttributes(inst, attrs)
				end
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})
	end

	-- Empty state
	if #sets == 0 then
		children.Empty = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "No saved attribute sets yet.",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			LayoutOrder = 3,
		})
	end

	-- Set rows
	for i, set in sets do
		children["Set" .. i] = e(SetRow, {
			Name = set.Name,
			AttrCount = countAttributes(set.Attributes),
			IsSelected = i == activeSet,
			OnSelect = function()
				if activeSet == i then
					props.SetSetting("ActiveSet", 0)
				else
					props.SetSetting("ActiveSet", i)
				end
			end,
			OnRename = function(newName: string)
				local newSets = table.clone(sets)
				newSets[i] = table.clone(set)
				newSets[i].Name = newName
				props.SetSetting("Sets", newSets)
			end,
			OnDelete = function()
				local newSets = table.clone(sets)
				table.remove(newSets, i)
				if activeSet == i then
					props.SetSetting("ActiveSet", 0)
				elseif activeSet > i then
					props.SetSetting("ActiveSet", activeSet - 1)
				end
				props.SetSetting("Sets", newSets)
			end,
			LayoutOrder = i + 3,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local CopyPasteAttributes: ToolTypes.ToolDefinition = {
	Id = "copyPasteAttributes",
	Name = "Copy Paste Attributes",
	Description = "Copy and paste attributes between instances",

	DefaultSettings = {
		Sets = {},
		ActiveSet = 0,
	},

	RenderSettings = CopyPasteAttributesSettings,
}

return CopyPasteAttributes
