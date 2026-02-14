--!strict
local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

type SwatchData = {
	Color: { number }, -- {R, G, B} floats 0-1
	Locked: boolean,
}

--------------------------------------------------------------------------------
-- Color math helpers
--------------------------------------------------------------------------------

local function colorToHex(r: number, g: number, b: number): string
	return string.format("#%02X%02X%02X", math.round(r * 255), math.round(g * 255), math.round(b * 255))
end

local function hexToColor(hex: string): (number, number, number)?
	hex = hex:gsub("^#", "")
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end
	if #hex ~= 6 then
		return nil
	end
	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if not r or not g or not b then
		return nil
	end
	return r / 255, g / 255, b / 255
end

-- sRGB relative luminance (simplified gamma)
local function luminance(r: number, g: number, b: number): number
	local function linearize(c: number): number
		if c <= 0.03928 then
			return c / 12.92
		end
		return ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
end

-- WCAG contrast ratio between two colors
local function contrastRatio(r1: number, g1: number, b1: number, r2: number, g2: number, b2: number): number
	local l1 = luminance(r1, g1, b1)
	local l2 = luminance(r2, g2, b2)
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
end

-- Wrap hue to [0, 1)
local function wrapHue(h: number): number
	return h % 1
end

-- Vary saturation and value slightly around a base, keeping them in [0.2, 1]
local function varyHSV(s: number, v: number): (number, number)
	local ns = math.clamp(s + (math.random() - 0.5) * 0.15, 0.2, 1)
	local nv = math.clamp(v + (math.random() - 0.5) * 0.15, 0.2, 1)
	return ns, nv
end

--------------------------------------------------------------------------------
-- Swatch generation
--------------------------------------------------------------------------------

local function generateComplementary(baseR: number, baseG: number, baseB: number, count: number): { { number } }
	local h, s, v = Color3.new(baseR, baseG, baseB):ToHSV()
	local offsets: { number }
	if count == 1 then
		offsets = { 0.5 }
	elseif count == 2 then
		offsets = { 150 / 360, 210 / 360 }
	elseif count == 3 then
		offsets = { 150 / 360, 0.5, 210 / 360 }
	else
		offsets = { 0.25, 0.5, 0.75, 1 / 6 }
	end

	local results: { { number } } = {}
	for i = 1, math.min(count, #offsets) do
		local ns, nv = varyHSV(s, v)
		local c = Color3.fromHSV(wrapHue(h + offsets[i]), ns, nv)
		table.insert(results, { c.R, c.G, c.B })
	end
	return results
end

local function generateContrasting(baseR: number, baseG: number, baseB: number, count: number): { { number } }
	local baseLum = luminance(baseR, baseG, baseB)
	local isDark = baseLum < 0.5
	local results: { { number } } = {}
	local usedHues: { number } = {}

	for _ = 1, count do
		local bestColor: { number }? = nil
		local bestContrast = 0

		for _ = 1, 200 do
			local hue = math.random()

			-- Check hue distance from existing swatches
			local tooClose = false
			for _, usedH in usedHues do
				local dist = math.abs(hue - usedH)
				dist = math.min(dist, 1 - dist)
				if dist < 30 / 360 then
					tooClose = true
					break
				end
			end
			if tooClose then
				continue
			end

			-- Generate with appropriate lightness
			local sat = 0.4 + math.random() * 0.5
			local val: number
			if isDark then
				val = 0.7 + math.random() * 0.3
			else
				val = 0.15 + math.random() * 0.35
			end

			local c = Color3.fromHSV(hue, sat, val)
			local cr = contrastRatio(baseR, baseG, baseB, c.R, c.G, c.B)
			if cr >= 4.5 and cr > bestContrast then
				bestContrast = cr
				bestColor = { c.R, c.G, c.B }
			end
		end

		if bestColor then
			local bh = Color3.new(bestColor[1], bestColor[2], bestColor[3]):ToHSV()
			table.insert(usedHues, bh)
			table.insert(results, bestColor)
		else
			-- Fallback: black or white
			if isDark then
				table.insert(results, { 1, 1, 1 })
			else
				table.insert(results, { 0, 0, 0 })
			end
		end
	end
	return results
end

local function generateSwatches(
	baseColor: { number },
	mode: string,
	count: number,
	existingSwatches: { SwatchData }
): { SwatchData }
	-- Generate new colors for unlocked slots
	local newColors: { { number } }
	if mode == "Complementary" then
		newColors = generateComplementary(baseColor[1], baseColor[2], baseColor[3], count)
	else
		newColors = generateContrasting(baseColor[1], baseColor[2], baseColor[3], count)
	end

	local result: { SwatchData } = {}
	local newIdx = 1
	for i = 1, count do
		if i <= #existingSwatches and existingSwatches[i].Locked then
			-- Keep locked swatch as-is
			table.insert(result, {
				Color = existingSwatches[i].Color,
				Locked = true,
			})
		else
			-- Use next generated color
			local color = if newIdx <= #newColors then newColors[newIdx] else { 0.5, 0.5, 0.5 }
			newIdx += 1
			table.insert(result, {
				Color = color,
				Locked = false,
			})
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- UI Components
--------------------------------------------------------------------------------

-- Toggle button row (reused for mode and swatch count)
local function ToggleRow(props: {
	Options: { string },
	Value: string,
	OnChanged: (value: string) -> (),
	LayoutOrder: number?,
})
	local buttons: { [string]: any } = {}

	buttons.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})

	for i, option in props.Options do
		local isSelected = option == props.Value
		buttons[option] = e("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = if isSelected then Colors.ACTION_BLUE else Colors.GREY,
			AutoButtonColor = not isSelected,
			Text = option,
			TextColor3 = if isSelected then Colors.WHITE else Colors.OFFWHITE,
			Font = if isSelected then Enum.Font.SourceSansBold else Enum.Font.SourceSans,
			TextSize = 13,
			BorderSizePixel = 0,
			LayoutOrder = i,
			[React.Event.MouseButton1Click] = function()
				props.OnChanged(option)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, buttons)
end

-- Single swatch display
local function SwatchRow(props: {
	Color: { number },
	Locked: boolean,
	OnToggleLock: () -> (),
	LayoutOrder: number?,
})
	local color = Color3.new(props.Color[1], props.Color[2], props.Color[3])
	local hex = colorToHex(props.Color[1], props.Color[2], props.Color[3])

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		ColorPreview = e("Frame", {
			Size = UDim2.new(0, 0, 0, 28),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
		HexLabel = e("TextLabel", {
			Size = UDim2.fromOffset(62, 28),
			BackgroundTransparency = 1,
			Text = hex,
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.Code,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 2,
		}),
		LockButton = e("TextButton", {
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = if props.Locked then Colors.ACTION_BLUE else Colors.GREY,
			AutoButtonColor = true,
			Text = if props.Locked then "L" else "U",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			BorderSizePixel = 0,
			LayoutOrder = 3,
			[React.Event.MouseButton1Click] = props.OnToggleLock,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

--------------------------------------------------------------------------------
-- Main settings component
--------------------------------------------------------------------------------

local function ColorCompanionSettings(props: ToolSettingsProps)
	local baseColor = props.GetSetting("BaseColor") :: { number }
	local mode = props.GetSetting("Mode") :: string
	local swatchCount = props.GetSetting("SwatchCount") :: number
	local swatches = props.GetSetting("Swatches") :: { SwatchData }

	local hexInputRef = React.useRef(nil :: TextBox?)

	local function regenerate(newBase: { number }?, newMode: string?, newCount: number?, newSwatches: { SwatchData }?)
		local b = newBase or baseColor
		local m = newMode or mode
		local c = newCount or swatchCount
		local s = newSwatches or swatches
		local generated = generateSwatches(b, m, c, s)
		props.SetSetting("Swatches", generated)
	end

	local children: { [string]: any } = {}

	children.Layout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	})

	-- Base color: preview + hex input
	children.BaseColorSection = e("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		Label = e("TextLabel", {
			Size = UDim2.fromOffset(36, 28),
			BackgroundTransparency = 1,
			Text = "Base",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		Preview = e("Frame", {
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Color3.new(baseColor[1], baseColor[2], baseColor[3]),
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
		HexInput = e("TextBox", {
			ref = hexInputRef,
			Size = UDim2.new(0, 0, 0, 28),
			BackgroundColor3 = Colors.GREY,
			Text = colorToHex(baseColor[1], baseColor[2], baseColor[3]),
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.Code,
			TextSize = 14,
			ClearTextOnFocus = false,
			BorderSizePixel = 0,
			LayoutOrder = 3,
			[React.Event.FocusLost] = function(rbx: TextBox)
				local r, g, b = hexToColor(rbx.Text)
				if r and g and b then
					local newBase = { r, g, b }
					props.SetSetting("BaseColor", newBase)
					regenerate(newBase)
				else
					-- Reset to current
					rbx.Text = colorToHex(baseColor[1], baseColor[2], baseColor[3])
				end
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
	})

	-- Mode picker
	children.ModeLabel = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "Mode",
		TextColor3 = Colors.OFFWHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSansBold,
		TextSize = 14,
		LayoutOrder = 2,
	})

	children.ModePicker = e(ToggleRow, {
		Options = { "Complementary", "Contrasting" },
		Value = mode,
		OnChanged = function(newMode: string)
			props.SetSetting("Mode", newMode)
			regenerate(nil, newMode)
		end,
		LayoutOrder = 3,
	})

	-- Swatch count
	children.CountLabel = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "Swatches",
		TextColor3 = Colors.OFFWHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSansBold,
		TextSize = 14,
		LayoutOrder = 4,
	})

	children.CountPicker = e(ToggleRow, {
		Options = { "1", "2", "3", "4" },
		Value = tostring(swatchCount),
		OnChanged = function(val: string)
			local newCount = tonumber(val) :: number
			props.SetSetting("SwatchCount", newCount)
			regenerate(nil, nil, newCount)
		end,
		LayoutOrder = 5,
	})

	-- Action buttons
	children.Actions = e("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		Randomize = e("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = Colors.ACTION_BLUE,
			AutoButtonColor = true,
			Text = "Randomize",
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 14,
			BorderSizePixel = 0,
			LayoutOrder = 1,
			[React.Event.MouseButton1Click] = function()
				regenerate()
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
		ClearLocks = e("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = Colors.GREY,
			AutoButtonColor = true,
			Text = "Clear Locks",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			[React.Event.MouseButton1Click] = function()
				local unlocked: { SwatchData } = {}
				for _, sw in swatches do
					table.insert(unlocked, { Color = sw.Color, Locked = false })
				end
				props.SetSetting("Swatches", unlocked)
				regenerate(nil, nil, nil, unlocked)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Flex = e("UIFlexItem", {
				FlexMode = Enum.UIFlexMode.Grow,
			}),
		}),
	})

	-- Swatches
	for i, swatch in swatches do
		children["Swatch" .. i] = e(SwatchRow, {
			Color = swatch.Color,
			Locked = swatch.Locked,
			OnToggleLock = function()
				local newSwatches = table.clone(swatches)
				newSwatches[i] = {
					Color = swatch.Color,
					Locked = not swatch.Locked,
				}
				props.SetSetting("Swatches", newSwatches)
			end,
			LayoutOrder = 10 + i,
		})
	end

	-- Empty state: auto-generate if no swatches
	if #swatches == 0 then
		children.Empty = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = "Click Randomize to generate swatches.",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 14,
			LayoutOrder = 10,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local ColorCompanion: ToolTypes.ToolDefinition = {
	Id = "colorCompanion",
	Name = "Color Companion",
	Description = "Generate complementary or contrasting color swatches",

	DefaultSettings = {
		BaseColor = { 1, 0, 0 },
		Mode = "Complementary",
		SwatchCount = 3,
		Swatches = {},
	},

	RenderSettings = ColorCompanionSettings,
}

return ColorCompanion
