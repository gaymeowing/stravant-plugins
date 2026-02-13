--!strict
local UserInputService = game:GetService("UserInputService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local NumberInput = require("../PluginGui/NumberInput")
local ToolTypes = require("../ToolTypes")

type ToolContext = ToolTypes.ToolContext
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local HUE_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
	ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
	ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
	ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
	ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
	ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
})

local WHITE_TO_TRANSPARENT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 1),
})

local TRANSPARENT_TO_BLACK = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0),
})

-- Saturation-Value picker square
-- Left→right = saturation 0→1, top→bottom = value 1→0
local function SVPicker(props: {
	Hue: number,
	Saturation: number,
	Value: number,
	OnSVChanged: (s: number, v: number) -> (),
	LayoutOrder: number?,
})
	local frameRef = React.useRef(nil :: GuiObject?)

	local function updateFromMouse()
		local frame = frameRef.current
		if not frame then
			return
		end
		local mousePos = UserInputService:GetMouseLocation()
		local relX = (mousePos.X - frame.AbsolutePosition.X) / frame.AbsoluteSize.X
		local relY = (mousePos.Y - frame.AbsolutePosition.Y) / frame.AbsoluteSize.Y
		props.OnSVChanged(
			math.clamp(relX, 0, 1),
			1 - math.clamp(relY, 0, 1)
		)
	end

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.fromHSV(props.Hue, 1, 1),
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder,
		ref = frameRef,
		[React.Event.MouseButton1Down] = function()
			updateFromMouse()
			task.spawn(function()
				while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					updateFromMouse()
					task.wait()
				end
			end)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		-- White overlay: left = opaque white, right = transparent
		WhiteOverlay = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colors.WHITE,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Gradient = e("UIGradient", {
				Transparency = WHITE_TO_TRANSPARENT,
			}),
		}),
		-- Black overlay: top = transparent, bottom = opaque black
		BlackOverlay = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colors.BLACK,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Gradient = e("UIGradient", {
				Transparency = TRANSPARENT_TO_BLACK,
				Rotation = 90,
			}),
		}),
		-- Marker at current SV position
		Marker = e("Frame", {
			Size = UDim2.fromOffset(12, 12),
			Position = UDim2.fromScale(props.Saturation, 1 - props.Value),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, {
			UICorner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = Colors.WHITE,
				Thickness = 2,
			}),
		}),
	})
end

-- Horizontal hue bar with rainbow gradient
local function HueBar(props: {
	Hue: number,
	OnHueChanged: (number) -> (),
	LayoutOrder: number?,
})
	local frameRef = React.useRef(nil :: GuiObject?)

	local function updateFromMouse()
		local frame = frameRef.current
		if not frame then
			return
		end
		local mousePos = UserInputService:GetMouseLocation()
		local relX = (mousePos.X - frame.AbsolutePosition.X) / frame.AbsoluteSize.X
		props.OnHueChanged(math.clamp(relX, 0, 1))
	end

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = Colors.WHITE,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder,
		ref = frameRef,
		[React.Event.MouseButton1Down] = function()
			updateFromMouse()
			task.spawn(function()
				while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					updateFromMouse()
					task.wait()
				end
			end)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		Gradient = e("UIGradient", {
			Color = HUE_GRADIENT,
		}),
		-- Marker at current hue
		Marker = e("Frame", {
			Size = UDim2.new(0, 4, 1, 0),
			Position = UDim2.fromScale(props.Hue, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Colors.WHITE,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Stroke = e("UIStroke", {
				Color = Colors.BLACK,
				Thickness = 1,
			}),
		}),
	})
end

local function PaintColorSettings(props: ToolSettingsProps)
	local colorArray = props.GetSetting("Color") :: { number }
	local color = Color3.new(colorArray[1], colorArray[2], colorArray[3])
	local h, s, v = color:ToHSV()

	-- Preserve hue in a ref so it doesn't jump to 0 when S or V reaches 0
	-- (where hue becomes mathematically undefined)
	local hueRef = React.useRef(h)
	if s > 0.01 and v > 0.01 then
		hueRef.current = h
	end
	local displayHue = hueRef.current

	local function setColorFromHSV(newH: number, newS: number, newV: number)
		local c = Color3.fromHSV(newH, newS, newV)
		props.SetSetting("Color", { c.R, c.G, c.B })
	end

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
		SVPicker = e(SVPicker, {
			Hue = displayHue,
			Saturation = s,
			Value = v,
			OnSVChanged = function(newS: number, newV: number)
				setColorFromHSV(displayHue, newS, newV)
			end,
			LayoutOrder = 1,
		}),
		HueBar = e(HueBar, {
			Hue = displayHue,
			OnHueChanged = function(newH: number)
				hueRef.current = newH
				setColorFromHSV(newH, s, v)
			end,
			LayoutOrder = 2,
		}),
		Preview = e("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			LayoutOrder = 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
		RInput = e(NumberInput, {
			Label = "R",
			Value = math.round(color.R * 255),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 255)
				props.SetSetting("Color", { newValue / 255, color.G, color.B })
				return newValue
			end,
			LayoutOrder = 4,
		}),
		GInput = e(NumberInput, {
			Label = "G",
			Value = math.round(color.G * 255),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 255)
				props.SetSetting("Color", { color.R, newValue / 255, color.B })
				return newValue
			end,
			LayoutOrder = 5,
		}),
		BInput = e(NumberInput, {
			Label = "B",
			Value = math.round(color.B * 255),
			ValueEntered = function(newValue: number)
				newValue = math.clamp(math.round(newValue), 0, 255)
				props.SetSetting("Color", { color.R, color.G, newValue / 255 })
				return newValue
			end,
			LayoutOrder = 6,
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
