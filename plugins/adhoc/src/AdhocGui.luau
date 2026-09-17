local Plugin = script.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Checkbox = require("./PluginGui/Checkbox")
local Colors = require("./PluginGui/Colors")
local ToolTypes = require("./ToolTypes")

type ToolDefinition = ToolTypes.ToolDefinition
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- Back header shown at the top of the active tool view — entire row is clickable
local function ToolHeader(props: {
	ToolName: string,
	OnGoBack: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = if isHovered then Colors.ACTION_BLUE else Colors.GREY,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder,
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
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
		BackArrow = e("TextLabel", {
			Size = UDim2.fromOffset(16, 24),
			BackgroundTransparency = 1,
			Text = "\u{25C0}",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			LayoutOrder = 1,
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
		LayoutOrder = 3,
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
		Description = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = tool.Description,
			TextColor3 = Colors.OFFWHITE,
			TextWrapped = true,
			Font = Enum.Font.SourceSans,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
			}),
		}),
		Settings = tool.RenderSettings and tool.RenderSettings(toolSettingsProps),
		TargetLocked = (tool.OnClicked or tool.OnViewChanged) and e(Checkbox, {
			Label = "Allow targeting locked",
			Checked = props.GetToolSetting(tool.Id, "TargetLocked") == true,
			Changed = function(checked: boolean)
				props.SetToolSetting(tool.Id, "TargetLocked", checked)
			end,
			LayoutOrder = 100,
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
			ZIndex = 2,
		}),
	})
end

-- Modal overlay explaining how to request a new tool
local function AddToolModal(props: {
	OnClose: () -> (),
})
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.BLACK,
		BackgroundTransparency = 0.3,
		ZIndex = 10,
		Active = true, -- Block input to elements below
	}, {
		Card = e("Frame", {
			Size = UDim2.new(1, -24, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Colors.GREY,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
			}),
			ListLayout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
			Title = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = "Submit an Idea",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 1,
				ZIndex = 11,
			}),
			Step1 = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				RichText = true,
				Text = '<font color="#4dabf7"><b>1.</b></font>  Click "Review this Asset" on the Creator Store or Toolbox plugin page to post a review with your idea for a new tool or change to an existing one. Be as detailed as you can!',
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
				ZIndex = 11,
			}),
			Step2 = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				RichText = true,
				Text = '<font color="#4dabf7"><b>2.</b></font>  AI coder quickly implements your idea.',
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 3,
				ZIndex = 11,
			}),
			Step3 = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				RichText = true,
				Text = '<font color="#4dabf7"><b>3.</b></font>  Plugin is updated to include your idea or change.',
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 4,
				ZIndex = 11,
			}),
			Hint = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Text = "Tip: You can delete your review and submit a new one to make another request.",
				TextColor3 = Colors.OFFWHITE,
				Font = Enum.Font.SourceSansItalic,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 5,
				ZIndex = 11,
			}),
			CloseButton = e("TextButton", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = Colors.ACTION_BLUE,
				AutoButtonColor = true,
				Text = "Got it",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 16,
				LayoutOrder = 6,
				ZIndex = 11,
				[React.Event.MouseButton1Click] = props.OnClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			}),
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
	local showAddModal, setShowAddModal = React.useState(false)
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

	children.SearchDivider = e("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, {
		Line = e("Frame", {
			Size = UDim2.new(1, -12, 0, 1),
			Position = UDim2.new(0, 6, 0, 0),
			BackgroundColor3 = Colors.OFFWHITE,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),
	})

	children.AddToolButton = searchText == "" and e("TextButton", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Colors.ACTION_BLUE,
		AutoButtonColor = true,
		Text = "+ Suggest a Tool",
		TextColor3 = Colors.WHITE,
		Font = Enum.Font.SourceSans,
		TextSize = 16,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		[React.Event.MouseButton1Click] = function()
			setShowAddModal(true)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
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

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		List = e("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.fromScale(1, 0),
			BorderSizePixel = 0,
			BackgroundColor3 = Colors.BLACK,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Colors.OFFWHITE,
		}, children),
		Modal = showAddModal and e(AddToolModal, {
			OnClose = function()
				setShowAddModal(false)
			end,
		}),
	})
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
