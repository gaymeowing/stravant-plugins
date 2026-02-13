--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local MATERIALS = {
	"Plastic",
	"SmoothPlastic",
	"Wood",
	"WoodPlanks",
	"Marble",
	"Slate",
	"Concrete",
	"Granite",
	"Brick",
	"Cobblestone",
	"Metal",
	"CorrodedMetal",
	"DiamondPlate",
	"Foil",
	"Glass",
	"Neon",
	"Sand",
	"Fabric",
	"Ice",
	"Grass",
	"Ground",
	"Pebble",
	"Limestone",
	"Sandstone",
	"Rock",
	"CeramicTiles",
	"Plaster",
	"Asphalt",
	"LeafyGrass",
	"Salt",
	"Mud",
	"Snow",
	"Basalt",
	"CrackedLava",
	"Glacier",
	"Pavement",
	"Cardboard",
	"Carpet",
	"Leather",
	"RoofShingles",
	"Rubber",
}

local function MaterialRow(props: {
	Name: string,
	IsSelected: boolean,
	OnClick: () -> (),
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)

	local bgColor = if props.IsSelected
		then Colors.ACTION_BLUE
		elseif isHovered then Colors.GREY
		else Colors.BLACK

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = bgColor,
		Text = props.Name,
		TextColor3 = Colors.WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = if props.IsSelected then Enum.Font.SourceSansBold else Enum.Font.SourceSans,
		TextSize = 16,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = props.OnClick,
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
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
		}),
	})
end

local function PaintMaterialSettings(props: ToolSettingsProps)
	local currentMaterial = props.GetSetting("Material") :: string

	local children: { [string]: any } = {}

	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	for i, materialName in MATERIALS do
		children[materialName] = e(MaterialRow, {
			Name = materialName,
			IsSelected = currentMaterial == materialName,
			OnClick = function()
				props.SetSetting("Material", materialName)
			end,
			LayoutOrder = i,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local mRecordingId: string? = nil
local mPaintedParts: { [BasePart]: boolean } = {}

local function applyMaterial(ctx: ToolContext)
	local materialName = ctx.GetSetting("Material") :: string
	local material = (Enum.Material :: any)[materialName] :: Enum.Material?
	if material and ctx.Target then
		ctx.Target.Material = material
		mPaintedParts[ctx.Target] = true
	end
end

local PaintMaterial: ToolTypes.ToolDefinition = {
	Id = "paintMaterial",
	Name = "Paint Material",
	Description = "Paint material onto parts",

	DefaultSettings = {
		Material = "Plastic",
	},

	OnActivated = function(ctx: ToolContext)
		mPaintedParts = {}
	end,

	OnDeactivated = function(ctx: ToolContext)
		mPaintedParts = {}
		ctx.SetHighlight(nil)
	end,

	OnViewChanged = function(ctx: ToolContext)
		ctx.SetHighlight(ctx.Target)
		if ctx.IsMouseDown and ctx.Target and not mPaintedParts[ctx.Target] then
			applyMaterial(ctx)
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if ctx.Target then
			local id = ctx.BeginRecording("Paint Material")
			if id then
				mRecordingId = id
			end
			mPaintedParts = { [ctx.Target] = true }
			applyMaterial(ctx)
		end
	end,

	OnReleased = function(ctx: ToolContext)
		if mRecordingId then
			ctx.FinishRecording(mRecordingId)
			mRecordingId = nil
		end
		mPaintedParts = {}
	end,

	RenderSettings = PaintMaterialSettings,
}

return PaintMaterial
