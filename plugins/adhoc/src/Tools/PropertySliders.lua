--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local Slider = require("../PluginGui/Slider")
local SubPanel = require("../PluginGui/SubPanel")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- Property descriptor: which properties to show for which classes
type UDimPropertyInfo = {
	Name: string,
	Type: "UDim" | "UDim2",
}

type ClassPropertyMap = {
	ClassName: string?,
	IsA: string?,
	Properties: { UDimPropertyInfo },
}

local kPropertyMap: { ClassPropertyMap } = {
	{
		IsA = "GuiObject",
		Properties = {
			{ Name = "Size", Type = "UDim2" },
			{ Name = "Position", Type = "UDim2" },
		},
	},
	{
		ClassName = "UICorner",
		Properties = {
			{ Name = "CornerRadius", Type = "UDim" },
		},
	},
	{
		ClassName = "UIPadding",
		Properties = {
			{ Name = "PaddingBottom", Type = "UDim" },
			{ Name = "PaddingLeft", Type = "UDim" },
			{ Name = "PaddingRight", Type = "UDim" },
			{ Name = "PaddingTop", Type = "UDim" },
		},
	},
	{
		ClassName = "UIListLayout",
		Properties = {
			{ Name = "Padding", Type = "UDim" },
		},
	},
	{
		ClassName = "UIGridLayout",
		Properties = {
			{ Name = "CellPadding", Type = "UDim2" },
			{ Name = "CellSize", Type = "UDim2" },
		},
	},
	{
		ClassName = "UIPageLayout",
		Properties = {
			{ Name = "Padding", Type = "UDim" },
		},
	},
	{
		ClassName = "UITableLayout",
		Properties = {
			{ Name = "CellPadding", Type = "UDim2" },
			{ Name = "CellSize", Type = "UDim2" },
			{ Name = "Padding", Type = "UDim" },
		},
	},
}

-- Discover which UDim/UDim2 properties apply to a given instance
local function getPropertiesForInstance(inst: Instance): { UDimPropertyInfo }
	local result: { UDimPropertyInfo } = {}
	local seen: { [string]: boolean } = {}
	for _, entry in kPropertyMap do
		local matches = false
		if entry.ClassName and inst.ClassName == entry.ClassName then
			matches = true
		elseif entry.IsA and inst:IsA(entry.IsA :: any) then
			matches = true
		end
		if matches then
			for _, prop in entry.Properties do
				if not seen[prop.Name] then
					seen[prop.Name] = true
					table.insert(result, prop)
				end
			end
		end
	end
	return result
end

-- Find properties common to all selected instances
local function getCommonProperties(instances: { Instance }): { UDimPropertyInfo }
	if #instances == 0 then
		return {}
	end
	local first = getPropertiesForInstance(instances[1])
	if #instances == 1 then
		return first
	end
	-- Intersect with properties from remaining instances
	local common: { UDimPropertyInfo } = {}
	for _, prop in first do
		local allHave = true
		for i = 2, #instances do
			local found = false
			for _, otherProp in getPropertiesForInstance(instances[i]) do
				if otherProp.Name == prop.Name and otherProp.Type == prop.Type then
					found = true
					break
				end
			end
			if not found then
				allHave = false
				break
			end
		end
		if allHave then
			table.insert(common, prop)
		end
	end
	return common
end

-- Read a UDim component from an instance property
local function readUDimComponent(inst: Instance, propName: string, component: string): number
	local value = (inst :: any)[propName]
	if component == "XScale" then
		return value.X.Scale
	elseif component == "XOffset" then
		return value.X.Offset
	elseif component == "YScale" then
		return value.Y.Scale
	elseif component == "YOffset" then
		return value.Y.Offset
	elseif component == "Scale" then
		return value.Scale
	elseif component == "Offset" then
		return value.Offset
	end
	return 0
end

-- Write a UDim component to an instance property
local function writeUDimComponent(
	inst: Instance,
	propName: string,
	propType: "UDim" | "UDim2",
	component: string,
	newValue: number
)
	local current = (inst :: any)[propName]
	if propType == "UDim2" then
		local xs, xo, ys, yo = current.X.Scale, current.X.Offset, current.Y.Scale, current.Y.Offset
		if component == "XScale" then
			xs = newValue
		elseif component == "XOffset" then
			xo = newValue
		elseif component == "YScale" then
			ys = newValue
		elseif component == "YOffset" then
			yo = newValue
		end
		(inst :: any)[propName] = UDim2.new(xs, xo, ys, yo)
	else
		local s, o = current.Scale, current.Offset
		if component == "Scale" then
			s = newValue
		elseif component == "Offset" then
			o = newValue
		end
		(inst :: any)[propName] = UDim.new(s, o)
	end
end

-- A single slider row for one UDim component
local function ComponentRow(props: {
	Label: string,
	Instances: { Instance },
	PropertyName: string,
	PropertyType: "UDim" | "UDim2",
	Component: string,
	IsScale: boolean,
	LayoutOrder: number?,
})
	local instances = props.Instances
	local mRecordingId = React.useRef(nil :: string?)
	local isDragging = React.useRef(false)
	local dragValue, setDragValue = React.useState(0)

	-- Read value from first instance (representative)
	local instanceValue = readUDimComponent(instances[1], props.PropertyName, props.Component)

	-- Use drag value for immediate UI feedback while dragging, instance value otherwise
	local value = if isDragging.current then dragValue else instanceValue

	-- Check for mixed values across multi-selection
	local isMixed = false
	for i = 2, #instances do
		local other = readUDimComponent(instances[i], props.PropertyName, props.Component)
		if math.abs(other - instanceValue) > 0.0001 then
			isMixed = true
			break
		end
	end

	local sliderMin = if props.IsScale then 0 else -500
	local sliderMax = if props.IsScale then 1 else 500

	local function applyValue(newValue: number)
		for _, inst in instances do
			writeUDimComponent(inst, props.PropertyName, props.PropertyType, props.Component, newValue)
		end
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		SliderArea = e(Slider, {
			Label = props.Label,
			Value = value,
			Min = sliderMin,
			Max = sliderMax,
			ValueChanged = function(newValue: number)
				if props.IsScale then
					newValue = math.round(newValue * 1000) / 1000
				else
					newValue = math.round(newValue)
				end
				setDragValue(newValue)
				applyValue(newValue)
			end,
			DragStarted = function()
				isDragging.current = true
				local id = ChangeHistoryService:TryBeginRecording("Adjust " .. props.PropertyName)
				if id then
					mRecordingId.current = id
				end
			end,
			DragEnded = function()
				isDragging.current = false
				if mRecordingId.current then
					ChangeHistoryService:FinishRecording(
						mRecordingId.current,
						Enum.FinishRecordingOperation.Commit
					)
					mRecordingId.current = nil
				end
			end,
			LayoutOrder = 1,
		}),
		Input = e(NumberInput, {
			Value = if isMixed then 0 else (if props.IsScale then math.round(value * 1000) / 1000 else math.round(value)),
			Label = if isMixed then "~" else nil,
			ValueEntered = function(newValue: number)
				local id = ChangeHistoryService:TryBeginRecording("Set " .. props.PropertyName)
				if id then
					applyValue(newValue)
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				end
				return newValue
			end,
			Grow = true,
			LayoutOrder = 2,
		}),
	})
end

-- Panel for a single UDim2 property (4 component rows)
local function UDim2Panel(props: {
	PropertyName: string,
	Instances: { Instance },
	LayoutOrder: number?,
})
	return e(SubPanel, {
		Title = props.PropertyName,
		Padding = UDim.new(0, 2),
		LayoutOrder = props.LayoutOrder,
	}, {
		XScale = e(ComponentRow, {
			Label = "X Scale",
			Instances = props.Instances,
			PropertyName = props.PropertyName,
			PropertyType = "UDim2",
			Component = "XScale",
			IsScale = true,
			LayoutOrder = 1,
		}),
		XOffset = e(ComponentRow, {
			Label = "X Offset",
			Instances = props.Instances,
			PropertyName = props.PropertyName,
			PropertyType = "UDim2",
			Component = "XOffset",
			IsScale = false,
			LayoutOrder = 2,
		}),
		YScale = e(ComponentRow, {
			Label = "Y Scale",
			Instances = props.Instances,
			PropertyName = props.PropertyName,
			PropertyType = "UDim2",
			Component = "YScale",
			IsScale = true,
			LayoutOrder = 3,
		}),
		YOffset = e(ComponentRow, {
			Label = "Y Offset",
			Instances = props.Instances,
			PropertyName = props.PropertyName,
			PropertyType = "UDim2",
			Component = "YOffset",
			IsScale = false,
			LayoutOrder = 4,
		}),
	})
end

-- Panel for a single UDim property (2 component rows)
local function UDimPanel(props: {
	PropertyName: string,
	Instances: { Instance },
	LayoutOrder: number?,
})
	return e(SubPanel, {
		Title = props.PropertyName,
		Padding = UDim.new(0, 2),
		LayoutOrder = props.LayoutOrder,
	}, {
		Scale = e(ComponentRow, {
			Label = "Scale",
			Instances = props.Instances,
			PropertyName = props.PropertyName,
			PropertyType = "UDim",
			Component = "Scale",
			IsScale = true,
			LayoutOrder = 1,
		}),
		Offset = e(ComponentRow, {
			Label = "Offset",
			Instances = props.Instances,
			PropertyName = props.PropertyName,
			PropertyType = "UDim",
			Component = "Offset",
			IsScale = false,
			LayoutOrder = 2,
		}),
	})
end

local function PropertySlidersSettings(props: ToolSettingsProps)
	local selection, setSelection = React.useState(Selection:Get())

	React.useEffect(function()
		local cn = Selection.SelectionChanged:Connect(function()
			setSelection(Selection:Get())
		end)
		return function()
			cn:Disconnect()
		end
	end, {})

	-- Force re-render periodically while panel is visible so slider values stay
	-- in sync when the user changes properties elsewhere (e.g. Properties pane).
	local _, setTick = React.useState(0)
	React.useEffect(function()
		local running = true
		task.spawn(function()
			while running do
				task.wait(0.25)
				if running then
					setTick(function(prev: number)
						return prev + 1
					end)
				end
			end
		end)
		return function()
			running = false
		end
	end, {})

	local properties = getCommonProperties(selection)

	-- Empty state
	if #selection == 0 then
		return e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "Select a GUI object to see its UDim/UDim2 properties.",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			TextWrapped = true,
			LayoutOrder = props.LayoutOrder,
		})
	end

	if #properties == 0 then
		return e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "No UDim/UDim2 properties on the selected object(s).",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			TextWrapped = true,
			LayoutOrder = props.LayoutOrder,
		})
	end

	local children: { [string]: any } = {}
	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	})

	for i, prop in properties do
		if prop.Type == "UDim2" then
			children[prop.Name] = e(UDim2Panel, {
				PropertyName = prop.Name,
				Instances = selection,
				LayoutOrder = i,
			})
		else
			children[prop.Name] = e(UDimPanel, {
				PropertyName = prop.Name,
				Instances = selection,
				LayoutOrder = i,
			})
		end
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local PropertySliders: ToolTypes.ToolDefinition = {
	Id = "propertySliders",
	Name = "Property Sliders",
	Description = "Slider controls for UDim and UDim2 properties",

	RenderSettings = PropertySlidersSettings,
}

return PropertySliders
