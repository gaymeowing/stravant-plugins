--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local NumberInput = require("../PluginGui/NumberInput")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local function isBlockPart(part: BasePart?): boolean
	if not part then
		return false
	end
	if part:IsA("Part") then
		return part.Shape == Enum.PartType.Block
	end
	return false
end

-- Copy visual/physical properties from source part to a new part
local function applyProperties(target: BasePart, source: BasePart)
	target.Color = source.Color
	target.Material = source.Material
	target.MaterialVariant = source.MaterialVariant
	target.Transparency = source.Transparency
	target.Reflectance = source.Reflectance
	target.Anchored = source.Anchored
	target.CanCollide = source.CanCollide
	target.CastShadow = source.CastShadow
	target.TopSurface = Enum.SurfaceType.Smooth
	target.BottomSurface = Enum.SurfaceType.Smooth
	target.FrontSurface = Enum.SurfaceType.Smooth
	target.BackSurface = Enum.SurfaceType.Smooth
	target.LeftSurface = Enum.SurfaceType.Smooth
	target.RightSurface = Enum.SurfaceType.Smooth
end

-- Create a slab (block) part
local function createSlab(
	model: Model,
	source: BasePart,
	cf: CFrame,
	size: Vector3
)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Size = size
	part.CFrame = cf
	applyProperties(part, source)
	part.Parent = model
end

-- Create a cylinder part (axis along local X)
local function createCylinder(
	model: Model,
	source: BasePart,
	cf: CFrame,
	length: number,
	radius: number
)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	-- Cylinder Size: X = length along axis, Y = diameter, Z = diameter
	part.Size = Vector3.new(length, radius * 2, radius * 2)
	part.CFrame = cf
	applyProperties(part, source)
	part.Parent = model
end

-- Create a sphere (ball) part
local function createSphere(
	model: Model,
	source: BasePart,
	cf: CFrame,
	radius: number
)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = cf
	applyProperties(part, source)
	part.Parent = model
end

local function doBevel(part: BasePart, radius: number)
	local W = part.Size.X
	local H = part.Size.Y
	local D = part.Size.Z

	-- Clamp radius to half the smallest dimension
	local maxR = math.min(W, H, D) / 2
	local R = math.clamp(radius, 0.01, maxR)

	local cf = part.CFrame
	local model = Instance.new("Model")
	model.Name = part.Name

	-- 3 Slabs (overlapping cross, centered at part position)
	-- Reuse the original part as the first slab so its children stay on it
	applyProperties(part, part)
	part.Size = Vector3.new(W, H - 2 * R, D - 2 * R)
	-- Full height, inset width and depth
	createSlab(model, part, cf, Vector3.new(W - 2 * R, H, D - 2 * R))
	-- Full depth, inset width and height
	createSlab(model, part, cf, Vector3.new(W - 2 * R, H - 2 * R, D))

	-- 12 Cylinders (edges)
	-- Cylinder axis is local X by default

	-- 4 along X-axis at corners of YZ cross-section
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local offset = Vector3.new(0, sy * (H / 2 - R), sz * (D / 2 - R))
			createCylinder(model, part, cf * CFrame.new(offset), W - 2 * R, R)
		end
	end

	-- 4 along Y-axis at corners of XZ cross-section
	-- Rotate cylinder so its X-axis aligns with Y: rotate Z by 90 degrees
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local offset = Vector3.new(sx * (W / 2 - R), 0, sz * (D / 2 - R))
			createCylinder(
				model, part,
				cf * CFrame.new(offset) * CFrame.Angles(0, 0, math.pi / 2),
				H - 2 * R, R
			)
		end
	end

	-- 4 along Z-axis at corners of XY cross-section
	-- Rotate cylinder so its X-axis aligns with Z: rotate Y by 90 degrees
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local offset = Vector3.new(sx * (W / 2 - R), sy * (H / 2 - R), 0)
			createCylinder(
				model, part,
				cf * CFrame.new(offset) * CFrame.Angles(0, math.pi / 2, 0),
				D - 2 * R, R
			)
		end
	end

	-- 8 Spheres (corners)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local offset = Vector3.new(
					sx * (W / 2 - R),
					sy * (H / 2 - R),
					sz * (D / 2 - R)
				)
				createSphere(model, part, cf * CFrame.new(offset), R)
			end
		end
	end

	-- Place model where the original part was, with the original part inside it
	model.Parent = part.Parent
	model.PrimaryPart = part
	part.Parent = model

	return model
end

-- Settings UI
local function BevelSettings(props: ToolSettingsProps)
	local radius = props.GetSetting("Radius") :: number

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		ListLayout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		RadiusInput = e(NumberInput, {
			Label = "Radius",
			Value = radius,
			ValueEntered = function(newValue: number)
				newValue = math.max(0.01, newValue)
				props.SetSetting("Radius", newValue)
				return newValue
			end,
			LayoutOrder = 1,
		}),
	})
end

local Bevel: ToolTypes.ToolDefinition = {
	Id = "bevel",
	Name = "Bevel",
	Description = "Replace a block part with a rounded-edge model",

	DefaultSettings = {
		Radius = 0.5,
	},

	OnDeactivated = function(ctx: ToolContext)
		ctx.SetHighlight(nil)
	end,

	OnViewChanged = function(ctx: ToolContext)
		if isBlockPart(ctx.Target) then
			ctx.SetHighlight(ctx.Target)
		else
			ctx.SetHighlight(nil)
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if not ctx.Target then
			return
		end
		if not isBlockPart(ctx.Target) then
			return
		end

		local radius = ctx.GetSetting("Radius") :: number
		local id = ctx.BeginRecording("Bevel")

		doBevel(ctx.Target, radius)

		if id then
			ctx.FinishRecording(id)
		end

		ctx.SetHighlight(nil)
	end,

	RenderSettings = BevelSettings,
}

return Bevel
