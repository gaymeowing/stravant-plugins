local Selection = game:GetService("Selection")

local Packages = script.Parent.Parent.Packages
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

local TestTypes = require("./TestTypes")
local ToolTypes = require("./ToolTypes")

local RandomizeProperties = require("./Tools/RandomizeProperties") :: ToolTypes.ToolDefinition

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local function mountSettings(
	screenGui: ScreenGui,
	settings: { [string]: any }
): ReactRoblox.RootType
	local props: ToolSettingsProps = {
		GetSetting = function(key: string): any
			return settings[key]
		end,
		SetSetting = function(key: string, value: any)
			settings[key] = value
		end,
		LayoutOrder = 1,
	}

	local root = ReactRoblox.createRoot(screenGui)
	ReactRoblox.act(function()
		root:render(e("Frame", {
			Size = UDim2.fromOffset(240, 500),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
			}),
			Settings = e(RandomizeProperties.RenderSettings :: any, props),
		}))
	end)

	return root
end

local function createTestParts(): { BasePart }
	local parts: { BasePart } = {}
	for i = 1, 5 do
		local p = Instance.new("Part")
		p.Name = "TestPart" .. i
		p.Size = Vector3.new(4, 1, 2)
		p.Position = Vector3.new(i * 5, 2, 0)
		p.Color = Color3.fromHSV(i / 5, 0.8, 0.9)
		p.Transparency = i * 0.15
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = workspace
		table.insert(parts, p)
	end
	return parts
end

local function cleanupParts(parts: { BasePart })
	for _, p in parts do
		p:Destroy()
	end
end

return function(t: TestTypes.TestContext)
	t.test("empty state - no selection", function()
		Selection:Set({})
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = { Panels = {} }
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
	end)

	t.test("with selection - no panels", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = { Panels = {} }
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("number panel - Transparency", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Transparency",
					TypeName = "number",
					Config = { Min = 0, Max = 1 },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("Color3 panel - HSV mode", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Color",
					TypeName = "Color3",
					Config = {
						ColorSpace = "HSV",
						MinH = 0, MaxH = 360,
						MinS = 0, MaxS = 100,
						MinV = 0, MaxV = 100,
						MinR = 0, MaxR = 255,
						MinG = 0, MaxG = 255,
						MinB = 0, MaxB = 255,
					},
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("Color3 panel - RGB mode", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Color",
					TypeName = "Color3",
					Config = {
						ColorSpace = "RGB",
						MinH = 0, MaxH = 360,
						MinS = 0, MaxS = 100,
						MinV = 0, MaxV = 100,
						MinR = 0, MaxR = 255,
						MinG = 0, MaxG = 255,
						MinB = 0, MaxB = 255,
					},
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("enum panel - Material", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local enabled: { [string]: boolean } = {}
		for _, item in Enum.Material:GetEnumItems() do
			enabled[item.Name] = true
		end

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Material",
					TypeName = "EnumItem",
					Config = { EnabledValues = enabled },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("boolean panel", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Anchored",
					TypeName = "boolean",
					Config = { Probability = 50 },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("multiple panels", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Transparency",
					TypeName = "number",
					Config = { Min = 0, Max = 1 },
				},
				{
					PropertyName = "Color",
					TypeName = "Color3",
					Config = {
						ColorSpace = "HSV",
						MinH = 0, MaxH = 360,
						MinS = 50, MaxS = 100,
						MinV = 50, MaxV = 100,
						MinR = 0, MaxR = 255,
						MinG = 0, MaxG = 255,
						MinB = 0, MaxB = 255,
					},
				},
				{
					PropertyName = "Anchored",
					TypeName = "boolean",
					Config = { Probability = 75 },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("Vector3 panel - Size", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Size",
					TypeName = "Vector3",
					Config = { MinX = 1, MaxX = 10, MinY = 1, MaxY = 5, MinZ = 1, MaxZ = 8 },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("CFrame panel", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "CFrame",
					TypeName = "CFrame",
					Config = {
						MinPX = -10, MaxPX = 10, MinPY = 0, MaxPY = 20, MinPZ = -10, MaxPZ = 10,
						MinRX = 0, MaxRX = 360, MinRY = 0, MaxRY = 360, MinRZ = 0, MaxRZ = 0,
					},
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("UDim panel", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "SomeUDim",
					TypeName = "UDim",
					Config = { MinScale = 0, MaxScale = 1, MinOffset = 0, MaxOffset = 100 },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("UDim2 panel", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "SomeUDim2",
					TypeName = "UDim2",
					Config = {
						MinXScale = 0, MaxXScale = 1, MinXOffset = 0, MaxXOffset = 100,
						MinYScale = 0, MaxYScale = 1, MinYOffset = 0, MaxYOffset = 100,
					},
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("Vector2 panel", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "SomeVector2",
					TypeName = "Vector2",
					Config = { MinX = -5, MaxX = 5, MinY = -3, MaxY = 3 },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("unsupported type", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "SomeProp",
					TypeName = "Instance",
					Config = {},
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("enum panel - small enum (Shape)", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local enabled: { [string]: boolean } = {}
		for _, item in Enum.PartType:GetEnumItems() do
			enabled[item.Name] = true
		end

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Shape",
					TypeName = "EnumItem",
					Config = { EnabledValues = enabled },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)

	t.test("no selection with existing panels", function()
		Selection:Set({})
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Transparency",
					TypeName = "number",
					Config = { Min = 0, Max = 1 },
				},
				{
					PropertyName = "Color",
					TypeName = "Color3",
					Config = {
						ColorSpace = "HSV",
						MinH = 0, MaxH = 360,
						MinS = 0, MaxS = 100,
						MinV = 0, MaxV = 100,
						MinR = 0, MaxR = 255,
						MinG = 0, MaxG = 255,
						MinB = 0, MaxB = 255,
					},
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
	end)

	t.test("kitchen sink - all panel types", function()
		local parts = createTestParts()
		Selection:Set(parts)
		task.wait()

		local screenGui = Instance.new("ScreenGui")
		screenGui.Parent = game:GetService("CoreGui")

		local shapeEnabled: { [string]: boolean } = {}
		for _, item in Enum.PartType:GetEnumItems() do
			shapeEnabled[item.Name] = true
		end

		local settings: { [string]: any } = {
			Panels = {
				{
					PropertyName = "Transparency",
					TypeName = "number",
					Config = { Min = 0, Max = 1 },
				},
				{
					PropertyName = "Color",
					TypeName = "Color3",
					Config = {
						ColorSpace = "HSV",
						MinH = 0, MaxH = 360,
						MinS = 50, MaxS = 100,
						MinV = 50, MaxV = 100,
						MinR = 0, MaxR = 255,
						MinG = 0, MaxG = 255,
						MinB = 0, MaxB = 255,
					},
				},
				{
					PropertyName = "Size",
					TypeName = "Vector3",
					Config = { MinX = 1, MaxX = 10, MinY = 1, MaxY = 5, MinZ = 1, MaxZ = 8 },
				},
				{
					PropertyName = "Anchored",
					TypeName = "boolean",
					Config = { Probability = 75 },
				},
				{
					PropertyName = "Shape",
					TypeName = "EnumItem",
					Config = { EnabledValues = shapeEnabled },
				},
			},
		}
		local root = mountSettings(screenGui, settings)

		root:unmount()
		screenGui:Destroy()
		Selection:Set({})
		cleanupParts(parts)
	end)
end
