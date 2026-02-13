--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local function ColorPreview(props: {
	Color: Color3,
	LayoutOrder: number?,
})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = props.Color,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
	})
end

local function PaintColorSettings(props: ToolSettingsProps)
	local colorArray = props.GetSetting("Color") :: { number }
	local color = Color3.new(colorArray[1], colorArray[2], colorArray[3])

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
		Preview = e(ColorPreview, {
			Color = color,
			LayoutOrder = 1,
		}),
		RInput = e(NumberInput, {
			Label = "R",
			Value = math.round(color.R * 255),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 255)
				props.SetSetting("Color", { newValue / 255, color.G, color.B })
				return newValue
			end,
			LayoutOrder = 2,
		}),
		GInput = e(NumberInput, {
			Label = "G",
			Value = math.round(color.G * 255),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 255)
				props.SetSetting("Color", { color.R, newValue / 255, color.B })
				return newValue
			end,
			LayoutOrder = 3,
		}),
		BInput = e(NumberInput, {
			Label = "B",
			Value = math.round(color.B * 255),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 255)
				props.SetSetting("Color", { color.R, color.G, newValue / 255 })
				return newValue
			end,
			LayoutOrder = 4,
		}),
	})
end

local mRecordingId: string? = nil
local mPaintedParts: { [BasePart]: boolean } = {}

local PaintColor: ToolTypes.ToolDefinition = {
	Id = "paintColor",
	Name = "Paint Color",
	Description = "Paint parts with a selected color",

	DefaultSettings = {
		Color = { 1, 0, 0 },
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
			local colorArray = ctx.GetSetting("Color") :: { number }
			local color = Color3.new(colorArray[1], colorArray[2], colorArray[3])
			ctx.Target.Color = color
			mPaintedParts[ctx.Target] = true
		end
	end,

	OnClicked = function(ctx: ToolContext)
		if ctx.Target then
			local id = ctx.BeginRecording("Paint Color")
			if id then
				mRecordingId = id
			end
			local colorArray = ctx.GetSetting("Color") :: { number }
			local color = Color3.new(colorArray[1], colorArray[2], colorArray[3])
			ctx.Target.Color = color
			mPaintedParts = { [ctx.Target] = true }
		end
	end,

	OnReleased = function(ctx: ToolContext)
		if mRecordingId then
			ctx.FinishRecording(mRecordingId)
			mRecordingId = nil
		end
		mPaintedParts = {}
	end,

	RenderSettings = PaintColorSettings,
}

return PaintColor
