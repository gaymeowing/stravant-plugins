local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReflectionService = game:GetService("ReflectionService")
local Selection = game:GetService("Selection")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Checkbox = require("../PluginGui/Checkbox")
local ChipForToggle = require("../PluginGui/ChipForToggle")
local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local OperationButton = require("../PluginGui/OperationButton")
local Slider = require("../PluginGui/Slider")
local SubPanel = require("../PluginGui/SubPanel")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type PanelConfig = {
	PropertyName: string,
	TypeName: string,
	Config: { [string]: any },
}

type ReflectedProperty = {
	Name: string,
	Permits: {
		Read: SecurityCapabilities?,
		Write: SecurityCapabilities?,
	},
	Display: {
		DeprecationMessage: string?,
	}?,
}

type PropertyInfo = {
	Name: string,
	TypeName: string,
	EnumType: Enum?,
}

--------------------------------------------------------------------------------
-- Property Discovery
--------------------------------------------------------------------------------

local WRITABLE_PROPERTY_CACHE: { [string]: { string } } = {}

local function getWritableProperties(className: string): { string }
	local cached = WRITABLE_PROPERTY_CACHE[className]
	if cached then
		return cached
	end
	local props: { string } = {}
	for _, prop in ReflectionService:GetPropertiesOfClass(className) :: { ReflectedProperty } do
		local isDeprecated = prop.Display and prop.Display.DeprecationMessage
		if prop.Permits.Read and prop.Permits.Write and prop.Name ~= "Parent" and not isDeprecated then
			table.insert(props, prop.Name)
		end
	end
	WRITABLE_PROPERTY_CACHE[className] = props
	return props
end

local function getCommonPropertyInfos(instances: { Instance }): { PropertyInfo }
	if #instances == 0 then
		return {}
	end

	-- Get writable property names for each class, then intersect
	local firstProps = getWritableProperties(instances[1].ClassName)
	local commonNames: { string } = {}
	for _, name in firstProps do
		local allHave = true
		for i = 2, #instances do
			local found = false
			for _, otherName in getWritableProperties(instances[i].ClassName) do
				if otherName == name then
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
			table.insert(commonNames, name)
		end
	end

	-- Detect types from first instance
	local result: { PropertyInfo } = {}
	for _, name in commonNames do
		local ok, value = pcall(function()
			return (instances[1] :: any)[name]
		end)
		if ok and value ~= nil then
			local typeName = typeof(value)
			local info: PropertyInfo = {
				Name = name,
				TypeName = typeName,
				EnumType = nil,
			}
			if typeName == "EnumItem" then
				info.EnumType = (value :: EnumItem).EnumType
			end
			table.insert(result, info)
		end
	end

	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)
	return result
end

--------------------------------------------------------------------------------
-- Default Config Creation
--------------------------------------------------------------------------------

local function createDefaultConfig(info: PropertyInfo, instances: { Instance }): { [string]: any }
	local typeName = info.TypeName

	if typeName == "number" then
		local minVal = math.huge
		local maxVal = -math.huge
		for _, inst in instances do
			local ok, v = pcall(function()
				return (inst :: any)[info.Name]
			end)
			if ok and typeof(v) == "number" then
				minVal = math.min(minVal, v)
				maxVal = math.max(maxVal, v)
			end
		end
		if minVal == math.huge then
			minVal, maxVal = 0, 1
		end
		return { Min = minVal, Max = maxVal }

	elseif typeName == "boolean" then
		return { Probability = 50 }

	elseif typeName == "Color3" then
		return {
			ColorSpace = "HSV",
			MinH = 0, MaxH = 360, EnableH = true,
			MinS = 0, MaxS = 100, EnableS = true,
			MinV = 0, MaxV = 100, EnableV = true,
			MinR = 0, MaxR = 255, EnableR = true,
			MinG = 0, MaxG = 255, EnableG = true,
			MinB = 0, MaxB = 255, EnableB = true,
		}

	elseif typeName == "Vector3" then
		local minX, maxX = math.huge, -math.huge
		local minY, maxY = math.huge, -math.huge
		local minZ, maxZ = math.huge, -math.huge
		for _, inst in instances do
			local ok, v = pcall(function()
				return (inst :: any)[info.Name]
			end)
			if ok and typeof(v) == "Vector3" then
				minX = math.min(minX, v.X); maxX = math.max(maxX, v.X)
				minY = math.min(minY, v.Y); maxY = math.max(maxY, v.Y)
				minZ = math.min(minZ, v.Z); maxZ = math.max(maxZ, v.Z)
			end
		end
		if minX == math.huge then
			minX, maxX, minY, maxY, minZ, maxZ = -1, 1, -1, 1, -1, 1
		end
		return {
			MinX = minX, MaxX = maxX, EnableX = true,
			MinY = minY, MaxY = maxY, EnableY = true,
			MinZ = minZ, MaxZ = maxZ, EnableZ = true,
		}

	elseif typeName == "Vector2" then
		local minX, maxX = math.huge, -math.huge
		local minY, maxY = math.huge, -math.huge
		for _, inst in instances do
			local ok, v = pcall(function()
				return (inst :: any)[info.Name]
			end)
			if ok and typeof(v) == "Vector2" then
				minX = math.min(minX, v.X); maxX = math.max(maxX, v.X)
				minY = math.min(minY, v.Y); maxY = math.max(maxY, v.Y)
			end
		end
		if minX == math.huge then
			minX, maxX, minY, maxY = -1, 1, -1, 1
		end
		return {
			MinX = minX, MaxX = maxX, EnableX = true,
			MinY = minY, MaxY = maxY, EnableY = true,
		}

	elseif typeName == "UDim" then
		return {
			MinScale = 0, MaxScale = 1, EnableScale = true,
			MinOffset = 0, MaxOffset = 100, EnableOffset = true,
		}

	elseif typeName == "UDim2" then
		return {
			MinXScale = 0, MaxXScale = 1, EnableXScale = true,
			MinXOffset = 0, MaxXOffset = 100, EnableXOffset = true,
			MinYScale = 0, MaxYScale = 1, EnableYScale = true,
			MinYOffset = 0, MaxYOffset = 100, EnableYOffset = true,
		}

	elseif typeName == "CFrame" then
		local minPX, maxPX = math.huge, -math.huge
		local minPY, maxPY = math.huge, -math.huge
		local minPZ, maxPZ = math.huge, -math.huge
		for _, inst in instances do
			local ok, v = pcall(function()
				return (inst :: any)[info.Name]
			end)
			if ok and typeof(v) == "CFrame" then
				local p = v.Position
				minPX = math.min(minPX, p.X); maxPX = math.max(maxPX, p.X)
				minPY = math.min(minPY, p.Y); maxPY = math.max(maxPY, p.Y)
				minPZ = math.min(minPZ, p.Z); maxPZ = math.max(maxPZ, p.Z)
			end
		end
		if minPX == math.huge then
			minPX, maxPX, minPY, maxPY, minPZ, maxPZ = -10, 10, -10, 10, -10, 10
		end
		return {
			MinPX = minPX, MaxPX = maxPX, EnablePX = true,
			MinPY = minPY, MaxPY = maxPY, EnablePY = true,
			MinPZ = minPZ, MaxPZ = maxPZ, EnablePZ = true,
			MinRX = 0, MaxRX = 0, EnableRX = true,
			MinRY = 0, MaxRY = 0, EnableRY = true,
			MinRZ = 0, MaxRZ = 0, EnableRZ = true,
		}

	elseif typeName == "EnumItem" and info.EnumType then
		local enabled: { [string]: boolean } = {}
		for _, item in (info.EnumType :: Enum):GetEnumItems() do
			enabled[item.Name] = true
		end
		return { EnabledValues = enabled }
	end

	return {}
end

--------------------------------------------------------------------------------
-- Randomization Logic
--------------------------------------------------------------------------------

local mRandom = Random.new()

local function generateRandomValue(config: { [string]: any }, typeName: string, enumType: Enum?, currentValue: any?): any
	if typeName == "number" then
		return mRandom:NextNumber(config.Min, config.Max)

	elseif typeName == "boolean" then
		return mRandom:NextNumber(0, 100) < config.Probability

	elseif typeName == "Color3" then
		if config.ColorSpace == "HSV" then
			local curH, curS, curV = 0, 0, 0
			if currentValue and typeof(currentValue) == "Color3" then
				curH, curS, curV = currentValue:ToHSV()
				curH = curH * 360
				curS = curS * 100
				curV = curV * 100
			end
			local h = (if config.EnableH ~= false then mRandom:NextNumber(config.MinH, config.MaxH) else curH) / 360
			local s = (if config.EnableS ~= false then mRandom:NextNumber(config.MinS, config.MaxS) else curS) / 100
			local v = (if config.EnableV ~= false then mRandom:NextNumber(config.MinV, config.MaxV) else curV) / 100
			return Color3.fromHSV(h, s, v)
		else
			local curR, curG, curB = 0, 0, 0
			if currentValue and typeof(currentValue) == "Color3" then
				curR = currentValue.R * 255
				curG = currentValue.G * 255
				curB = currentValue.B * 255
			end
			local r = (if config.EnableR ~= false then mRandom:NextNumber(config.MinR, config.MaxR) else curR) / 255
			local g = (if config.EnableG ~= false then mRandom:NextNumber(config.MinG, config.MaxG) else curG) / 255
			local b = (if config.EnableB ~= false then mRandom:NextNumber(config.MinB, config.MaxB) else curB) / 255
			return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
		end

	elseif typeName == "Vector3" then
		local cur = if currentValue and typeof(currentValue) == "Vector3" then currentValue else Vector3.zero
		return Vector3.new(
			if config.EnableX ~= false then mRandom:NextNumber(config.MinX, config.MaxX) else cur.X,
			if config.EnableY ~= false then mRandom:NextNumber(config.MinY, config.MaxY) else cur.Y,
			if config.EnableZ ~= false then mRandom:NextNumber(config.MinZ, config.MaxZ) else cur.Z
		)

	elseif typeName == "Vector2" then
		local cur = if currentValue and typeof(currentValue) == "Vector2" then currentValue else Vector2.zero
		return Vector2.new(
			if config.EnableX ~= false then mRandom:NextNumber(config.MinX, config.MaxX) else cur.X,
			if config.EnableY ~= false then mRandom:NextNumber(config.MinY, config.MaxY) else cur.Y
		)

	elseif typeName == "UDim" then
		local cur = if currentValue and typeof(currentValue) == "UDim" then currentValue else UDim.new(0, 0)
		return UDim.new(
			if config.EnableScale ~= false then mRandom:NextNumber(config.MinScale, config.MaxScale) else cur.Scale,
			if config.EnableOffset ~= false then mRandom:NextNumber(config.MinOffset, config.MaxOffset) else cur.Offset
		)

	elseif typeName == "UDim2" then
		local cur = if currentValue and typeof(currentValue) == "UDim2" then currentValue else UDim2.new()
		return UDim2.new(
			if config.EnableXScale ~= false then mRandom:NextNumber(config.MinXScale, config.MaxXScale) else cur.X.Scale,
			if config.EnableXOffset ~= false then mRandom:NextNumber(config.MinXOffset, config.MaxXOffset) else cur.X.Offset,
			if config.EnableYScale ~= false then mRandom:NextNumber(config.MinYScale, config.MaxYScale) else cur.Y.Scale,
			if config.EnableYOffset ~= false then mRandom:NextNumber(config.MinYOffset, config.MaxYOffset) else cur.Y.Offset
		)

	elseif typeName == "CFrame" then
		local curPos = Vector3.zero
		local curRX, curRY, curRZ = 0, 0, 0
		if currentValue and typeof(currentValue) == "CFrame" then
			curPos = currentValue.Position
			curRX, curRY, curRZ = currentValue:ToEulerAnglesXYZ()
		end
		local pos = Vector3.new(
			if config.EnablePX ~= false then mRandom:NextNumber(config.MinPX, config.MaxPX) else curPos.X,
			if config.EnablePY ~= false then mRandom:NextNumber(config.MinPY, config.MaxPY) else curPos.Y,
			if config.EnablePZ ~= false then mRandom:NextNumber(config.MinPZ, config.MaxPZ) else curPos.Z
		)
		local rx = if config.EnableRX ~= false then math.rad(mRandom:NextNumber(config.MinRX, config.MaxRX)) else curRX
		local ry = if config.EnableRY ~= false then math.rad(mRandom:NextNumber(config.MinRY, config.MaxRY)) else curRY
		local rz = if config.EnableRZ ~= false then math.rad(mRandom:NextNumber(config.MinRZ, config.MaxRZ)) else curRZ
		return CFrame.new(pos) * CFrame.Angles(rx, ry, rz)

	elseif typeName == "EnumItem" and enumType then
		local enabled = config.EnabledValues :: { [string]: boolean }
		local candidates: { EnumItem } = {}
		for _, item in enumType:GetEnumItems() do
			if enabled[item.Name] then
				table.insert(candidates, item)
			end
		end
		if #candidates > 0 then
			return candidates[mRandom:NextInteger(1, #candidates)]
		end
		return nil
	end

	return nil
end

local function applyRandomization(instances: { Instance }, panels: { PanelConfig })
	local id = ChangeHistoryService:TryBeginRecording("Randomize Properties")
	if not id then
		return
	end
	for _, inst in instances do
		for _, panel in panels do
			local ok, currentVal = pcall(function()
				return (inst :: any)[panel.PropertyName]
			end)
			local value = generateRandomValue(panel.Config, panel.TypeName, nil, if ok then currentVal else nil)
			-- Resolve EnumType from the actual instance value for EnumItem panels
			if panel.TypeName == "EnumItem" then
				if ok and typeof(currentVal) == "EnumItem" then
					value = generateRandomValue(panel.Config, panel.TypeName, currentVal.EnumType, currentVal)
				end
			end
			if value ~= nil then
				pcall(function()
					(inst :: any)[panel.PropertyName] = value
				end)
			end
		end
	end
	ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
end

--------------------------------------------------------------------------------
-- Reusable UI: MinMaxRow + MinMaxHeader
--------------------------------------------------------------------------------

local kLabelWidth = 24
local kDashWidth = 14

local function MinMaxHeader(props: {
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Spacer = e("Frame", {
			Size = UDim2.fromOffset(kLabelWidth, 16),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}),
		MinLabel = e("TextLabel", {
			Size = UDim2.new(0, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = "Min",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 13,
			LayoutOrder = 2,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
		DashSpacer = e("Frame", {
			Size = UDim2.fromOffset(kDashWidth, 16),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}),
		MaxLabel = e("TextLabel", {
			Size = UDim2.new(0, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = "Max",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 13,
			LayoutOrder = 4,
		}, {
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
	})
end

local kCheckboxSize = 16

local function MinMaxRow(props: {
	Label: string,
	Min: number,
	Max: number,
	Enabled: boolean?,
	OnMinChanged: (number) -> number?,
	OnMaxChanged: (number) -> number?,
	OnEqualClicked: () -> (),
	OnEnabledChanged: ((boolean) -> ())?,
	LayoutOrder: number?,
})
	local enabled = props.Enabled ~= false
	local dimmed = not enabled

	local children: { [string]: any } = {}
	children.ListLayout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	if props.OnEnabledChanged then
		children.EnableCheck = e("TextButton", {
			Size = UDim2.fromOffset(kCheckboxSize, kCheckboxSize),
			BackgroundColor3 = if enabled then Colors.ACTION_BLUE else Colors.GREY,
			AutoButtonColor = true,
			Text = if enabled then "\u{2713}" else "",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 12,
			BorderSizePixel = 0,
			LayoutOrder = 0,
			[React.Event.MouseButton1Click] = function()
				(props.OnEnabledChanged :: any)(not enabled)
			end,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
		})
	end

	children.Label = e("TextLabel", {
		Size = UDim2.fromOffset(kLabelWidth, 24),
		BackgroundTransparency = 1,
		Text = props.Label,
		TextColor3 = if dimmed then Colors.GREY else Colors.OFFWHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	children.MinInput = e(NumberInput, {
		Value = props.Min,
		ValueEntered = props.OnMinChanged,
		Grow = true,
		LayoutOrder = 2,
	})
	children.EqualButton = e("TextButton", {
		Size = UDim2.fromOffset(kDashWidth, 24),
		BackgroundTransparency = 1,
		Text = "=",
		TextColor3 = if dimmed then Colors.GREY else Colors.OFFWHITE,
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		LayoutOrder = 3,
		[React.Event.MouseButton1Click] = props.OnEqualClicked,
	})
	children.MaxInput = e(NumberInput, {
		Value = props.Max,
		ValueEntered = props.OnMaxChanged,
		Grow = true,
		LayoutOrder = 4,
	})

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

--------------------------------------------------------------------------------
-- Type-specific Editors
--------------------------------------------------------------------------------

local function collapseRange(
	config: { [string]: any },
	minKey: string,
	maxKey: string,
	onBatchChanged: ({ [string]: any }) -> ()
)
	local avg = (config[minKey] + config[maxKey]) / 2
	onBatchChanged({ [minKey] = avg, [maxKey] = avg })
end

local function NumberEditor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		MinLabel = e("TextLabel", {
			Size = UDim2.fromOffset(26, 24),
			BackgroundTransparency = 1,
			Text = "Min",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = 1,
		}),
		MinInput = e(NumberInput, {
			Value = props.Config.Min,
			ValueEntered = function(v: number)
				props.OnConfigChanged("Min", v)
				return v
			end,
			Grow = true,
			LayoutOrder = 2,
		}),
		EqualButton = e("TextButton", {
			Size = UDim2.fromOffset(kDashWidth, 24),
			BackgroundTransparency = 1,
			Text = "=",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 16,
			LayoutOrder = 3,
			[React.Event.MouseButton1Click] = function()
				collapseRange(props.Config, "Min", "Max", props.OnBatchChanged)
			end,
		}),
		MaxLabel = e("TextLabel", {
			Size = UDim2.fromOffset(26, 24),
			BackgroundTransparency = 1,
			Text = "Max",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = 4,
		}),
		MaxInput = e(NumberInput, {
			Value = props.Config.Max,
			ValueEntered = function(v: number)
				props.OnConfigChanged("Max", v)
				return v
			end,
			Grow = true,
			LayoutOrder = 5,
		}),
	})
end

local function BooleanEditor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	LayoutOrder: number?,
})
	return e(Slider, {
		Label = "True %",
		Value = props.Config.Probability,
		Min = 0,
		Max = 100,
		ValueChanged = function(v: number)
			props.OnConfigChanged("Probability", math.round(v))
		end,
		LayoutOrder = props.LayoutOrder,
	})
end

local function Color3Editor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	LayoutOrder: number?,
})
	local config = props.Config
	local isHSV = config.ColorSpace == "HSV"

	local children: { [string]: any } = {}
	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	children.ModeToggle = e("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, {
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		RGB = e(ChipForToggle, {
			Text = "RGB",
			IsCurrent = not isHSV,
			OnClick = function()
				props.OnConfigChanged("ColorSpace", "RGB")
			end,
			LayoutOrder = 1,
		}),
		HSV = e(ChipForToggle, {
			Text = "HSV",
			IsCurrent = isHSV,
			OnClick = function()
				props.OnConfigChanged("ColorSpace", "HSV")
			end,
			LayoutOrder = 2,
		}),
	})

	children.Header = e(MinMaxHeader, { LayoutOrder = 2 })

	if isHSV then
		children.H = e(MinMaxRow, {
			Label = "H", Min = config.MinH, Max = config.MaxH,
			Enabled = config.EnableH ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinH", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxH", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinH", "MaxH", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableH", v) end,
			LayoutOrder = 3,
		})
		children.S = e(MinMaxRow, {
			Label = "S", Min = config.MinS, Max = config.MaxS,
			Enabled = config.EnableS ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinS", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxS", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinS", "MaxS", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableS", v) end,
			LayoutOrder = 4,
		})
		children.V = e(MinMaxRow, {
			Label = "V", Min = config.MinV, Max = config.MaxV,
			Enabled = config.EnableV ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinV", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxV", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinV", "MaxV", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableV", v) end,
			LayoutOrder = 5,
		})
	else
		children.R = e(MinMaxRow, {
			Label = "R", Min = config.MinR, Max = config.MaxR,
			Enabled = config.EnableR ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinR", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxR", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinR", "MaxR", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableR", v) end,
			LayoutOrder = 3,
		})
		children.G = e(MinMaxRow, {
			Label = "G", Min = config.MinG, Max = config.MaxG,
			Enabled = config.EnableG ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinG", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxG", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinG", "MaxG", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableG", v) end,
			LayoutOrder = 4,
		})
		children.B = e(MinMaxRow, {
			Label = "B", Min = config.MinB, Max = config.MaxB,
			Enabled = config.EnableB ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinB", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxB", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinB", "MaxB", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableB", v) end,
			LayoutOrder = 5,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local function Vector3Editor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	LayoutOrder: number?,
})
	local config = props.Config
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Header = e(MinMaxHeader, { LayoutOrder = 1 }),
		X = e(MinMaxRow, {
			Label = "X", Min = config.MinX, Max = config.MaxX,
			Enabled = config.EnableX ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinX", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxX", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinX", "MaxX", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableX", v) end,
			LayoutOrder = 2,
		}),
		Y = e(MinMaxRow, {
			Label = "Y", Min = config.MinY, Max = config.MaxY,
			Enabled = config.EnableY ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinY", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxY", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinY", "MaxY", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableY", v) end,
			LayoutOrder = 3,
		}),
		Z = e(MinMaxRow, {
			Label = "Z", Min = config.MinZ, Max = config.MaxZ,
			Enabled = config.EnableZ ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinZ", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxZ", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinZ", "MaxZ", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableZ", v) end,
			LayoutOrder = 4,
		}),
	})
end

local function Vector2Editor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	LayoutOrder: number?,
})
	local config = props.Config
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Header = e(MinMaxHeader, { LayoutOrder = 1 }),
		X = e(MinMaxRow, {
			Label = "X", Min = config.MinX, Max = config.MaxX,
			Enabled = config.EnableX ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinX", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxX", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinX", "MaxX", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableX", v) end,
			LayoutOrder = 2,
		}),
		Y = e(MinMaxRow, {
			Label = "Y", Min = config.MinY, Max = config.MaxY,
			Enabled = config.EnableY ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinY", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxY", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinY", "MaxY", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableY", v) end,
			LayoutOrder = 3,
		}),
	})
end

local function UDimEditor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	LayoutOrder: number?,
})
	local config = props.Config
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Header = e(MinMaxHeader, { LayoutOrder = 1 }),
		Scale = e(MinMaxRow, {
			Label = "Scl", Min = config.MinScale, Max = config.MaxScale,
			Enabled = config.EnableScale ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinScale", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxScale", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinScale", "MaxScale", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableScale", v) end,
			LayoutOrder = 2,
		}),
		Offset = e(MinMaxRow, {
			Label = "Off", Min = config.MinOffset, Max = config.MaxOffset,
			Enabled = config.EnableOffset ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinOffset", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxOffset", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinOffset", "MaxOffset", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableOffset", v) end,
			LayoutOrder = 3,
		}),
	})
end

local function UDim2Editor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	LayoutOrder: number?,
})
	local config = props.Config
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		XLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = "X",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		XHeader = e(MinMaxHeader, { LayoutOrder = 2 }),
		XScale = e(MinMaxRow, {
			Label = "Scl", Min = config.MinXScale, Max = config.MaxXScale,
			Enabled = config.EnableXScale ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinXScale", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxXScale", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinXScale", "MaxXScale", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableXScale", v) end,
			LayoutOrder = 3,
		}),
		XOffset = e(MinMaxRow, {
			Label = "Off", Min = config.MinXOffset, Max = config.MaxXOffset,
			Enabled = config.EnableXOffset ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinXOffset", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxXOffset", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinXOffset", "MaxXOffset", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableXOffset", v) end,
			LayoutOrder = 4,
		}),
		YLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = "Y",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 5,
		}),
		YHeader = e(MinMaxHeader, { LayoutOrder = 6 }),
		YScale = e(MinMaxRow, {
			Label = "Scl", Min = config.MinYScale, Max = config.MaxYScale,
			Enabled = config.EnableYScale ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinYScale", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxYScale", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinYScale", "MaxYScale", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableYScale", v) end,
			LayoutOrder = 7,
		}),
		YOffset = e(MinMaxRow, {
			Label = "Off", Min = config.MinYOffset, Max = config.MaxYOffset,
			Enabled = config.EnableYOffset ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinYOffset", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxYOffset", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinYOffset", "MaxYOffset", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableYOffset", v) end,
			LayoutOrder = 8,
		}),
	})
end

local function CFrameEditor(props: {
	Config: { [string]: any },
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	OnResetToSelection: () -> (),
	LayoutOrder: number?,
})
	local config = props.Config
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		ResetButton = e("TextButton", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = Colors.GREY,
			AutoButtonColor = true,
			Text = "Set from Selection",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			BorderSizePixel = 0,
			LayoutOrder = 0,
			[React.Event.MouseButton1Click] = props.OnResetToSelection,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
		}),
		PosLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = "Position",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		PosHeader = e(MinMaxHeader, { LayoutOrder = 2 }),
		PX = e(MinMaxRow, {
			Label = "X", Min = config.MinPX, Max = config.MaxPX,
			Enabled = config.EnablePX ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinPX", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxPX", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinPX", "MaxPX", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnablePX", v) end,
			LayoutOrder = 3,
		}),
		PY = e(MinMaxRow, {
			Label = "Y", Min = config.MinPY, Max = config.MaxPY,
			Enabled = config.EnablePY ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinPY", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxPY", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinPY", "MaxPY", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnablePY", v) end,
			LayoutOrder = 4,
		}),
		PZ = e(MinMaxRow, {
			Label = "Z", Min = config.MinPZ, Max = config.MaxPZ,
			Enabled = config.EnablePZ ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinPZ", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxPZ", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinPZ", "MaxPZ", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnablePZ", v) end,
			LayoutOrder = 5,
		}),
		RotLabel = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Text = "Rotation (degrees)",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 6,
		}),
		RotHeader = e(MinMaxHeader, { LayoutOrder = 7 }),
		RX = e(MinMaxRow, {
			Label = "X", Min = config.MinRX, Max = config.MaxRX,
			Enabled = config.EnableRX ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinRX", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxRX", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinRX", "MaxRX", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableRX", v) end,
			LayoutOrder = 8,
		}),
		RY = e(MinMaxRow, {
			Label = "Y", Min = config.MinRY, Max = config.MaxRY,
			Enabled = config.EnableRY ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinRY", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxRY", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinRY", "MaxRY", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableRY", v) end,
			LayoutOrder = 9,
		}),
		RZ = e(MinMaxRow, {
			Label = "Z", Min = config.MinRZ, Max = config.MaxRZ,
			Enabled = config.EnableRZ ~= false,
			OnMinChanged = function(v: number) props.OnConfigChanged("MinRZ", v); return v end,
			OnMaxChanged = function(v: number) props.OnConfigChanged("MaxRZ", v); return v end,
			OnEqualClicked = function() collapseRange(config, "MinRZ", "MaxRZ", props.OnBatchChanged) end,
			OnEnabledChanged = function(v: boolean) props.OnConfigChanged("EnableRZ", v) end,
			LayoutOrder = 10,
		}),
	})
end

local kCheckboxHeight = 22
local kCheckboxPadding = 1
local kMaxVisibleEnumItems = 8

local function EnumItemEditor(props: {
	Config: { [string]: any },
	EnumType: Enum,
	OnConfigChanged: (key: string, value: any) -> (),
	LayoutOrder: number?,
})
	local enabled = props.Config.EnabledValues :: { [string]: boolean }
	local items = props.EnumType:GetEnumItems()

	local function setAll(value: boolean)
		local newEnabled: { [string]: boolean } = {}
		for _, item in items do
			newEnabled[item.Name] = value
		end
		props.OnConfigChanged("EnabledValues", newEnabled)
	end

	local checkboxChildren: { [string]: any } = {}
	checkboxChildren.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, kCheckboxPadding),
	})

	for i, item in items do
		checkboxChildren[item.Name] = e(Checkbox, {
			Label = item.Name,
			Checked = if enabled[item.Name] == nil then false else enabled[item.Name],
			Changed = function(checked: boolean)
				local newEnabled = table.clone(enabled)
				newEnabled[item.Name] = checked
				props.OnConfigChanged("EnabledValues", newEnabled)
			end,
			LayoutOrder = i,
		})
	end

	local totalHeight = #items * (kCheckboxHeight + kCheckboxPadding) - kCheckboxPadding
	local needsScroll = #items > kMaxVisibleEnumItems
	local visibleHeight = if needsScroll
		then kMaxVisibleEnumItems * (kCheckboxHeight + kCheckboxPadding) - kCheckboxPadding
		else totalHeight

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Buttons = e("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			AllButton = e("TextButton", {
				Size = UDim2.fromOffset(36, 22),
				BackgroundColor3 = Colors.GREY,
				AutoButtonColor = true,
				Text = "All",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSans,
				TextSize = 14,
				BorderSizePixel = 0,
				LayoutOrder = 1,
				[React.Event.MouseButton1Click] = function()
					setAll(true)
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
			}),
			NoneButton = e("TextButton", {
				Size = UDim2.fromOffset(42, 22),
				BackgroundColor3 = Colors.GREY,
				AutoButtonColor = true,
				Text = "None",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSans,
				TextSize = 14,
				BorderSizePixel = 0,
				LayoutOrder = 2,
				[React.Event.MouseButton1Click] = function()
					setAll(false)
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
			}),
		}),
		Items = if needsScroll
			then e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 0, visibleHeight),
				CanvasSize = UDim2.fromScale(1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = Colors.OFFWHITE,
				LayoutOrder = 2,
			}, checkboxChildren)
			else e("Frame", {
				Size = UDim2.new(1, 0, 0, visibleHeight),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, checkboxChildren),
	})
end

--------------------------------------------------------------------------------
-- Editor Dispatcher
--------------------------------------------------------------------------------

local function renderEditor(
	config: { [string]: any },
	typeName: string,
	enumType: Enum?,
	onConfigChanged: (key: string, value: any) -> (),
	onBatchChanged: ({ [string]: any }) -> (),
	onResetToSelection: () -> (),
	layoutOrder: number?
): any
	if typeName == "number" then
		return e(NumberEditor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, LayoutOrder = layoutOrder })
	elseif typeName == "boolean" then
		return e(BooleanEditor, { Config = config, OnConfigChanged = onConfigChanged, LayoutOrder = layoutOrder })
	elseif typeName == "Color3" then
		return e(Color3Editor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, LayoutOrder = layoutOrder })
	elseif typeName == "Vector3" then
		return e(Vector3Editor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, LayoutOrder = layoutOrder })
	elseif typeName == "Vector2" then
		return e(Vector2Editor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, LayoutOrder = layoutOrder })
	elseif typeName == "UDim" then
		return e(UDimEditor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, LayoutOrder = layoutOrder })
	elseif typeName == "UDim2" then
		return e(UDim2Editor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, LayoutOrder = layoutOrder })
	elseif typeName == "CFrame" then
		return e(CFrameEditor, { Config = config, OnConfigChanged = onConfigChanged, OnBatchChanged = onBatchChanged, OnResetToSelection = onResetToSelection, LayoutOrder = layoutOrder })
	elseif typeName == "EnumItem" and enumType then
		return e(EnumItemEditor, { Config = config, EnumType = enumType, OnConfigChanged = onConfigChanged, LayoutOrder = layoutOrder })
	else
		return e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "Unsupported type: " .. typeName,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			LayoutOrder = layoutOrder,
		})
	end
end

--------------------------------------------------------------------------------
-- PropertySearchRow
--------------------------------------------------------------------------------

local function PropertySearchRow(props: {
	Info: PropertyInfo,
	OnClick: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = if isHovered then Colors.GREY else Colors.BLACK,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = props.OnClick,
		[React.Event.MouseEnter] = function()
			setIsHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setIsHovered(false)
		end,
	}, {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		}),
		ListLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		NameLabel = e("TextLabel", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = props.Info.Name,
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
		TypeLabel = e("TextLabel", {
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = props.Info.TypeName,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 13,
			LayoutOrder = 2,
		}),
	})
end

--------------------------------------------------------------------------------
-- PropertyPanel (SubPanel + X button + editor)
--------------------------------------------------------------------------------

local function PropertyPanel(props: {
	Panel: PanelConfig,
	EnumType: Enum?,
	Applicable: boolean,
	OnRemove: () -> (),
	OnRandomize: () -> (),
	OnConfigChanged: (key: string, value: any) -> (),
	OnBatchChanged: ({ [string]: any }) -> (),
	OnResetToSelection: () -> (),
	LayoutOrder: number?,
})
	if not props.Applicable then
		return nil
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Panel = e(SubPanel, {
			Title = props.Panel.PropertyName,
			Padding = UDim.new(0, 2),
		}, {
			Editor = renderEditor(
				props.Panel.Config,
				props.Panel.TypeName,
				props.EnumType,
				props.OnConfigChanged,
				props.OnBatchChanged,
				props.OnResetToSelection,
				1
			),
			RandomizeSpacer = e("Frame", {
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundTransparency = 1,
				LayoutOrder = 99,
			}),
			RandomizeButton = e("TextButton", {
				Size = UDim2.new(0, 0, 0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Colors.ACTION_BLUE,
				AutoButtonColor = true,
				Text = "  Randomize " .. props.Panel.PropertyName .. "  ",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 14,
				BorderSizePixel = 0,
				LayoutOrder = 100,
				[React.Event.MouseButton1Click] = props.OnRandomize,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
		}),
		RemoveButton = e("TextButton", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(1, -8, 0, -2),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Colors.DARK_RED,
			AutoButtonColor = true,
			Text = "X",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			ZIndex = 3,
			[React.Event.MouseButton1Click] = props.OnRemove,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

--------------------------------------------------------------------------------
-- PropertySearchPanel
--------------------------------------------------------------------------------

local function PropertySearchPanel(props: {
	AvailableProperties: { PropertyInfo },
	OnAddProperty: (info: PropertyInfo) -> (),
	OnClose: () -> (),
	LayoutOrder: number?,
})
	local searchText, setSearchText = React.useState("")
	local searchLower = searchText:lower()

	local filtered: { PropertyInfo } = {}
	for _, info in props.AvailableProperties do
		if searchText == "" or info.Name:lower():find(searchLower, 1, true) then
			table.insert(filtered, info)
		end
	end

	local listChildren: { [string]: any } = {}
	listChildren.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 1),
	})
	for i, info in filtered do
		listChildren[info.Name] = e(PropertySearchRow, {
			Info = info,
			OnClick = function()
				props.OnAddProperty(info)
			end,
			LayoutOrder = i,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		SearchHeader = e("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			ListLayout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			TextBox = e("TextBox", {
				Size = UDim2.new(0, 0, 0, 26),
				BackgroundColor3 = Colors.GREY,
				TextColor3 = Colors.WHITE,
				PlaceholderText = "Search properties...",
				PlaceholderColor3 = Colors.OFFWHITE,
				Text = searchText,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
				LayoutOrder = 1,
				[React.Change.Text] = function(rbx: TextBox)
					setSearchText(rbx.Text)
				end,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}),
				Flex = e("UIFlexItem", {
					FlexMode = Enum.UIFlexMode.Grow,
				}),
			}),
			CancelButton = e("TextButton", {
				Size = UDim2.fromOffset(52, 26),
				BackgroundColor3 = Colors.DARK_RED,
				AutoButtonColor = true,
				Text = "Cancel",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 14,
				LayoutOrder = 2,
				[React.Event.MouseButton1Click] = props.OnClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			}),
		}),
		ResultsList = e("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, math.min(#filtered * 25, 200)),
			CanvasSize = UDim2.fromScale(1, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Colors.BLACK,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Colors.OFFWHITE,
			LayoutOrder = 2,
		}, listChildren),
	})
end

--------------------------------------------------------------------------------
-- Main Settings Component
--------------------------------------------------------------------------------

local SUPPORTED_TYPES: { [string]: boolean } = {
	number = true,
	boolean = true,
	Color3 = true,
	Vector3 = true,
	Vector2 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	EnumItem = true,
}

local function RandomizePropertiesSettings(props: ToolSettingsProps)
	local selection, setSelection = React.useState(Selection:Get())
	local searchOpen, setSearchOpen = React.useState(false)

	React.useEffect(function()
		local cn = Selection.SelectionChanged:Connect(function()
			setSelection(Selection:Get())
		end)
		return function()
			cn:Disconnect()
		end
	end, {})

	local panels = props.GetSetting("Panels") :: { PanelConfig }
	if not panels then
		panels = {}
	end

	-- Discover properties common to current selection
	local allPropertyInfos = React.useMemo(function()
		return getCommonPropertyInfos(selection)
	end, { selection } :: { any })

	-- Build a lookup of property infos by name for the current selection
	local propertyInfoByName: { [string]: PropertyInfo } = {}
	for _, info in allPropertyInfos do
		propertyInfoByName[info.Name] = info
	end

	-- Filter available properties: must be supported type and not already added
	local addedNames: { [string]: boolean } = {}
	for _, panel in panels do
		addedNames[panel.PropertyName] = true
	end

	local availableProperties: { PropertyInfo } = {}
	for _, info in allPropertyInfos do
		if SUPPORTED_TYPES[info.TypeName] and not addedNames[info.Name] then
			table.insert(availableProperties, info)
		end
	end

	local function updatePanels(newPanels: { PanelConfig })
		props.SetSetting("Panels", newPanels)
	end

	local function addProperty(info: PropertyInfo)
		local config = createDefaultConfig(info, selection)
		local newPanel: PanelConfig = {
			PropertyName = info.Name,
			TypeName = info.TypeName,
			Config = config,
		}
		local newPanels = table.clone(panels)
		table.insert(newPanels, newPanel)
		updatePanels(newPanels)
	end

	local function removePanel(index: number)
		local newPanels = table.clone(panels)
		table.remove(newPanels, index)
		updatePanels(newPanels)
	end

	local function updatePanelConfigBatch(index: number, changes: { [string]: any })
		local newPanels = table.clone(panels)
		local newConfig = table.clone(newPanels[index].Config)
		for key, value in changes do
			newConfig[key] = value
		end
		newPanels[index] = {
			PropertyName = newPanels[index].PropertyName,
			TypeName = newPanels[index].TypeName,
			Config = newConfig,
		}
		updatePanels(newPanels)
	end

	local function updatePanelConfig(index: number, key: string, value: any)
		updatePanelConfigBatch(index, { [key] = value })
	end

	-- Build children
	local children: { [string]: any } = {}
	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	})

	-- Empty state
	if #selection == 0 then
		children.EmptyState = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "Select instances to randomize their properties.",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 16,
			TextWrapped = true,
			LayoutOrder = 1,
		})
	else
		if searchOpen then
			-- Search panel replaces the Add button
			children.SearchPanel = e(PropertySearchPanel, {
				AvailableProperties = availableProperties,
				OnAddProperty = function(info: PropertyInfo)
					addProperty(info)
					setSearchOpen(false)
				end,
				OnClose = function()
					setSearchOpen(false)
				end,
				LayoutOrder = 1,
			})
		else
			-- Add Property button
			children.AddButton = e("TextButton", {
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = Colors.ACTION_BLUE,
				AutoButtonColor = true,
				Text = "+ Add Property",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 16,
				BorderSizePixel = 0,
				LayoutOrder = 1,
				[React.Event.MouseButton1Click] = function()
					setSearchOpen(true)
				end,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			})
		end
	end

	-- Property panels
	for i, panel in panels do
		-- Resolve EnumType from the current selection if possible
		local enumType: Enum? = nil
		if panel.TypeName == "EnumItem" then
			local info = propertyInfoByName[panel.PropertyName]
			if info then
				enumType = info.EnumType
			end
		end

		local applicable = propertyInfoByName[panel.PropertyName] ~= nil or #selection == 0

		children["Panel_" .. panel.PropertyName] = e(PropertyPanel, {
			Panel = panel,
			EnumType = enumType,
			Applicable = applicable,
			OnRemove = function()
				removePanel(i)
			end,
			OnRandomize = function()
				applyRandomization(selection, { panel })
			end,
			OnConfigChanged = function(key: string, value: any)
				updatePanelConfig(i, key, value)
			end,
			OnBatchChanged = function(changes: { [string]: any })
				updatePanelConfigBatch(i, changes)
			end,
			OnResetToSelection = function()
				local info = propertyInfoByName[panel.PropertyName]
				if info then
					updatePanelConfigBatch(i, createDefaultConfig(info, selection))
				end
			end,
			LayoutOrder = 10 + i,
		})
	end

	-- Randomize button (only when there are panels)
	if #panels > 0 then
		children.RandomizeButton = e(OperationButton, {
			Text = "Randomize All",
			Height = 30,
			Disabled = #selection == 0,
			Color = Colors.ACTION_BLUE,
			OnClick = function()
				applyRandomization(selection, panels)
			end,
			LayoutOrder = 1000,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

--------------------------------------------------------------------------------
-- Tool Definition
--------------------------------------------------------------------------------

local RandomizeProperties: ToolTypes.ToolDefinition = {
	Id = "randomizeProperties",
	Name = "Randomize Properties",
	Description = "Randomize properties of selected instances within configurable bounds",

	DefaultSettings = {
		Panels = {},
	},

	RenderSettings = RandomizePropertiesSettings,
}

return RandomizeProperties
