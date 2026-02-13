--!strict
local Plugin = script.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("./PluginGui/Colors")
local ToolTypes = require("./ToolTypes")

type ToolDefinition = ToolTypes.ToolDefinition
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- Back header shown at the top of the active tool view
local function ToolHeader(props: {
	ToolName: string,
	OnGoBack: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Colors.GREY,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
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
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 8),
		}),
		BackButton = e("TextButton", {
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = if isHovered then Colors.ACTION_BLUE else Colors.GREY,
			Text = "\u{25C0}",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			LayoutOrder = 1,
			[React.Event.MouseButton1Click] = props.OnGoBack,
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
		}),
		ToolName = e("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = props.ToolName,
			TextColor3 = Colors.WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.SourceSansBold,
			TextSize = 18,
			LayoutOrder = 2,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
	})
end

-- Full-panel view when a tool is active
local function ActiveToolView(props: {
	Tool: ToolDefinition,
	OnGoBack: () -> (),
	GetToolSetting: (toolId: string, key: string) -> any,
	SetToolSetting: (toolId: string, key: string, value: any) -> (),
})
	local tool = props.Tool

	local toolSettingsProps: ToolSettingsProps = {
		GetSetting = function(key: string): any
			return props.GetToolSetting(tool.Id, key)
		end,
		SetSetting = function(key: string, value: any)
			props.SetToolSetting(tool.Id, key, value)
		end,
		LayoutOrder = 2,
	}

	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(1, 0),
		BorderSizePixel = 0,
		BackgroundColor3 = Colors.BLACK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.OFFWHITE,
	}, {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 40),
		}),
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Header = e(ToolHeader, {
			ToolName = tool.Name,
			OnGoBack = props.OnGoBack,
			LayoutOrder = 1,
		}),
		Settings = tool.RenderSettings and tool.RenderSettings(toolSettingsProps),
		NoSettings = not tool.RenderSettings and e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Text = tool.Description .. "\n\nClick on parts in the viewport to use this tool.",
			TextColor3 = Colors.OFFWHITE,
			TextWrapped = true,
			Font = Enum.Font.SourceSans,
			TextSize = 16,
			LayoutOrder = 2,
		}),
	})
end

-- Search bar for the tool list
local function SearchBar(props: {
	SearchText: string,
	OnSearchChanged: (string) -> (),
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 2),
		}),
		TextBox = e("TextBox", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Colors.GREY,
			TextColor3 = Colors.WHITE,
			PlaceholderText = "Search tools...",
			PlaceholderColor3 = Colors.OFFWHITE,
			Text = props.SearchText,
			Font = Enum.Font.SourceSans,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			[React.Change.Text] = function(rbx: TextBox)
				props.OnSearchChanged(rbx.Text)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}),
	})
end

local function ToolListItem(props: {
	Tool: ToolDefinition,
	IsPinned: boolean,
	OnSelect: () -> (),
	OnTogglePin: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)

	local bgColor = if isHovered then Colors.GREY else Colors.BLACK

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = bgColor,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
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
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 4),
		}),
		PinButton = e("TextButton", {
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Text = if props.IsPinned then "\u{2605}" else "\u{2606}",
			TextColor3 = if props.IsPinned then Color3.fromRGB(255, 200, 0) else Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 18,
			LayoutOrder = 1,
			[React.Event.MouseButton1Click] = props.OnTogglePin,
		}),
		NameButton = e("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = props.Tool.Name,
			TextColor3 = Colors.WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.SourceSans,
			TextSize = 18,
			AutoButtonColor = false,
			LayoutOrder = 2,
			[React.Event.MouseButton1Click] = props.OnSelect,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
		Arrow = e("TextLabel", {
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Text = "\u{25B6}",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 12,
			LayoutOrder = 3,
		}),
	})
end

local function SectionDivider(props: {
	Text: string,
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Line = e("Frame", {
			Size = UDim2.new(1, -12, 0, 1),
			Position = UDim2.new(0, 6, 0.5, 0),
			BackgroundColor3 = Colors.OFFWHITE,
			BorderSizePixel = 0,
		}),
		Label = e("TextLabel", {
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Colors.BLACK,
			BorderSizePixel = 0,
			Text = "  " .. props.Text .. "  ",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
		}),
	})
end

-- Tool list view (no tool selected)
local function ToolListView(props: {
	AllTools: { ToolDefinition },
	PinnedTools: { string },
	OnSelectTool: (string) -> (),
	OnTogglePin: (string) -> (),
})
	local searchText, setSearchText = React.useState("")
	local layoutOrder = 0
	local function nextOrder(): number
		layoutOrder += 1
		return layoutOrder
	end

	-- Build pinned set for quick lookup
	local pinnedSet: { [string]: boolean } = {}
	for _, id in props.PinnedTools do
		pinnedSet[id] = true
	end

	-- Filter tools by search
	local searchLower = searchText:lower()
	local function matchesSearch(tool: ToolDefinition): boolean
		if searchText == "" then
			return true
		end
		return tool.Name:lower():find(searchLower, 1, true) ~= nil
			or tool.Description:lower():find(searchLower, 1, true) ~= nil
	end

	-- Separate pinned and unpinned
	local pinnedTools: { ToolDefinition } = {}
	local unpinnedTools: { ToolDefinition } = {}
	for _, tool in props.AllTools do
		if matchesSearch(tool) then
			if pinnedSet[tool.Id] then
				table.insert(pinnedTools, tool)
			else
				table.insert(unpinnedTools, tool)
			end
		end
	end

	-- Build children
	local children: { [string]: any } = {}

	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	children.Padding = e("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 40),
	})

	children.SearchBar = e(SearchBar, {
		SearchText = searchText,
		OnSearchChanged = setSearchText,
		LayoutOrder = nextOrder(),
	})

	-- Pinned tools
	for _, tool in pinnedTools do
		children["Pinned_" .. tool.Id] = e(ToolListItem, {
			Tool = tool,
			IsPinned = true,
			OnSelect = function()
				props.OnSelectTool(tool.Id)
			end,
			OnTogglePin = function()
				props.OnTogglePin(tool.Id)
			end,
			LayoutOrder = nextOrder(),
		})
	end

	-- Section divider if we have both pinned and unpinned
	if #pinnedTools > 0 and #unpinnedTools > 0 then
		children.Divider = e(SectionDivider, {
			Text = "All Tools",
			LayoutOrder = nextOrder(),
		})
	end

	-- Unpinned tools
	for _, tool in unpinnedTools do
		children["Tool_" .. tool.Id] = e(ToolListItem, {
			Tool = tool,
			IsPinned = false,
			OnSelect = function()
				props.OnSelectTool(tool.Id)
			end,
			OnTogglePin = function()
				props.OnTogglePin(tool.Id)
			end,
			LayoutOrder = nextOrder(),
		})
	end

	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(1, 0),
		BorderSizePixel = 0,
		BackgroundColor3 = Colors.BLACK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.OFFWHITE,
	}, children)
end

local function AdhocGui(props: {
	AllTools: { ToolDefinition },
	ActiveToolId: string?,
	PinnedTools: { string },
	ToolSettings: { [string]: { [string]: any } },
	Active: boolean,
	Panelized: boolean,
	CurrentSettings: any,
	UpdatedSettings: () -> (),
	HandleAction: (string) -> (),
	OnSelectTool: (string) -> (),
	OnGoBack: () -> (),
	OnTogglePin: (string) -> (),
	GetToolSetting: (toolId: string, key: string) -> any,
	SetToolSetting: (toolId: string, key: string, value: any) -> (),
})
	-- Find active tool
	local activeTool: ToolDefinition? = nil
	if props.ActiveToolId then
		for _, tool in props.AllTools do
			if tool.Id == props.ActiveToolId then
				activeTool = tool
				break
			end
		end
	end

	if activeTool then
		return e(ActiveToolView, {
			Tool = activeTool,
			OnGoBack = props.OnGoBack,
			GetToolSetting = props.GetToolSetting,
			SetToolSetting = props.SetToolSetting,
		})
	else
		return e(ToolListView, {
			AllTools = props.AllTools,
			PinnedTools = props.PinnedTools,
			OnSelectTool = props.OnSelectTool,
			OnTogglePin = props.OnTogglePin,
		})
	end
end

return AdhocGui
