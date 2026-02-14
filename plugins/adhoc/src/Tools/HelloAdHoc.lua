--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local kGreeting = "Hello there! I am AdHoc, your agentic assistant."

local function getToolList(): { { Name: string, Description: string } }
	local tools: { { Name: string, Description: string } } = {}
	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and child ~= script then
			local ok, toolDef = pcall(require, child)
			if ok and type(toolDef) == "table" and toolDef.Name and toolDef.Description then
				table.insert(tools, {
					Name = toolDef.Name,
					Description = toolDef.Description,
				})
			end
		end
	end
	table.sort(tools, function(a, b)
		return a.Name < b.Name
	end)
	return tools
end

local function HelloAdHocSettings(props: ToolSettingsProps)
	local tools = React.useMemo(getToolList, {})

	local children: { [string]: any } = {}

	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	})

	children.Greeting = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = kGreeting,
		TextColor3 = Colors.WHITE,
		TextWrapped = true,
		Font = Enum.Font.SourceSansBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})

	children.CapabilitiesLabel = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "My capabilities (" .. #tools .. " tools):",
		TextColor3 = Colors.OFFWHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	})

	-- Tool list
	local toolListChildren: { [string]: any } = {}
	toolListChildren.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	for i, tool in tools do
		toolListChildren["Tool" .. i] = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			RichText = true,
			Text = "<b>" .. tool.Name .. "</b> — " .. tool.Description,
			TextColor3 = Colors.WHITE,
			TextWrapped = true,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
			}),
		})
	end
	children.ToolList = e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	}, toolListChildren)

	-- Print button
	children.PrintButton = e("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Colors.ACTION_BLUE,
		AutoButtonColor = true,
		Text = "Print to Output",
		TextColor3 = Colors.WHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		BorderSizePixel = 0,
		LayoutOrder = 4,
		[React.Event.MouseButton1Click] = function()
			local lines: { string } = { kGreeting, "", "Capabilities:" }
			for _, tool in tools do
				table.insert(lines, "  " .. tool.Name .. " — " .. tool.Description)
			end
			print(table.concat(lines, "\n"))
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
	})

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local HelloAdHoc: ToolTypes.ToolDefinition = {
	Id = "helloAdHoc",
	Name = "Hello AdHoc",
	Description = "Greet and list capabilities",

	RenderSettings = HelloAdHocSettings,
}

return HelloAdHoc
