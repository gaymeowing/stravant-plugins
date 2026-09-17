local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

-- Build color lists by year of release
local function buildList(ids: { number }): { BrickColor }
	local list: { BrickColor } = {}
	for _, id in ids do
		table.insert(list, BrickColor.new(id))
	end
	return list
end

-- 2006: Original LEGO-based palette (32 colors)
local COLORS_2006 = buildList({
	1, 5, 9, 11, 18, 21, 23, 24, 26, 28, 29, 37, 38, 45,
	101, 102, 104, 105, 106, 107, 119, 125, 135, 141, 151, 153,
	192, 194, 199, 208, 217, 226,
})

-- 2009: Roblox-original colors (31 colors)
local COLORS_2009 = buildList({
	1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010,
	1011, 1012, 1013, 1014, 1015, 1016, 1018, 1019, 1020, 1021,
	1022, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032,
})

-- 2015: Extended palette (65 colors)
local COLORS_2015 = buildList({
	133, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310,
	311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322,
	323, 324, 325, 327, 328, 329, 330, 331, 332, 333, 334, 335,
	336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347,
	348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359,
	360, 361, 362, 363, 364, 365,
})

-- All named BrickColors (iterate known range)
local ALL_COLORS: { BrickColor } = {}
do
	local seen: { [number]: boolean } = {}
	for i = 0, 1032 do
		local ok, bc = pcall(BrickColor.new, i)
		if ok and bc and not seen[bc.Number] then
			seen[bc.Number] = true
			table.insert(ALL_COLORS, bc)
		end
	end
	table.sort(ALL_COLORS, function(a, b)
		return a.Name < b.Name
	end)
end

local FILTER_OPTIONS = { "2006", "2009", "2015", "All" }

local function ColorSwatch(props: {
	BrickColor: BrickColor,
	LayoutOrder: number?,
})
	local isHovered, setIsHovered = React.useState(false)
	local bc = props.BrickColor

	-- Pick text/stroke colors based on brightness (opposite for readability)
	local isLight = bc.Color.R * 0.299 + bc.Color.G * 0.587 + bc.Color.B * 0.114 > 0.5
	local textColor = if isLight then Colors.BLACK else Colors.WHITE
	local textStrokeColor = if isLight then Colors.WHITE else Colors.BLACK

	return e("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = bc.Color,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = bc.Name,
		TextColor3 = textColor,
		TextStrokeColor3 = if isHovered then textStrokeColor else textColor,
		TextStrokeTransparency = if isHovered then 0.5 else 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSansBold,
		TextSize = 16,
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = function()
			local parts = Selection:Get()
			if #parts == 0 then
				return
			end
			local id = ChangeHistoryService:TryBeginRecording("Set BrickColor")
			if not id then
				return
			end
			for _, inst in parts do
				if inst:IsA("BasePart") then
					inst.BrickColor = bc
				end
			end
			ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
		end,
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
			PaddingRight = UDim.new(0, 8),
		}),
		Stroke = isHovered and e("UIStroke", {
			Color = textStrokeColor,
			Thickness = 2,
		}),
	})
end

local function FilterChip(props: {
	Label: string,
	IsSelected: boolean,
	OnClick: () -> (),
	LayoutOrder: number?,
})
	return e("TextButton", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = if props.IsSelected then Colors.ACTION_BLUE else Colors.GREY,
		AutoButtonColor = true,
		Text = props.Label,
		TextColor3 = Colors.WHITE,
		Font = if props.IsSelected then Enum.Font.SourceSansBold else Enum.Font.SourceSans,
		TextSize = 14,
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = props.OnClick,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})
end

local function BrickColorBrowserSettings(props: ToolSettingsProps)
	local filter = props.GetSetting("Filter") :: string
	local searchText = props.GetSetting("Search") :: string

	-- Get the source list based on filter
	local sourceList: { BrickColor }
	if filter == "2006" then
		sourceList = COLORS_2006
	elseif filter == "2009" then
		sourceList = COLORS_2009
	elseif filter == "2015" then
		sourceList = COLORS_2015
	else
		sourceList = ALL_COLORS
	end

	-- Apply name search
	local searchLower = searchText:lower()
	local filtered: { BrickColor } = {}
	for _, bc in sourceList do
		if searchText == "" or bc.Name:lower():find(searchLower, 1, true) then
			table.insert(filtered, bc)
		end
	end

	-- Build children
	local children: { [string]: any } = {}

	children.ListLayout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	-- Filter chips row
	local chipChildren: { [string]: any } = {}
	chipChildren.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})
	for i, option in FILTER_OPTIONS do
		chipChildren[option] = e(FilterChip, {
			Label = option,
			IsSelected = filter == option,
			OnClick = function()
				props.SetSetting("Filter", option)
			end,
			LayoutOrder = i,
		})
	end
	children.Filters = e("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, chipChildren)

	-- Search box
	children.Search = e("TextBox", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Colors.GREY,
		TextColor3 = Colors.WHITE,
		PlaceholderText = "Filter by name...",
		PlaceholderColor3 = Colors.OFFWHITE,
		Text = searchText,
		Font = Enum.Font.SourceSans,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		LayoutOrder = 2,
		[React.Change.Text] = function(rbx: TextBox)
			props.SetSetting("Search", rbx.Text)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 4),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})

	-- Count label
	children.Count = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = #filtered .. " colors — click to apply to selection",
		TextColor3 = Colors.OFFWHITE,
		Font = Enum.Font.SourceSans,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
	})

	-- Color swatches in a two-column grid
	local gridChildren: { [string]: any } = {}
	gridChildren.GridLayout = e("UIGridLayout", {
		CellSize = UDim2.new(0.5, -2, 0, 26),
		CellPadding = UDim2.new(0, 4, 0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for i, bc in filtered do
		gridChildren["Color" .. bc.Number] = e(ColorSwatch, {
			BrickColor = bc,
			LayoutOrder = i,
		})
	end
	children.Grid = e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
	}, gridChildren)

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local BrickColorBrowser: ToolTypes.ToolDefinition = {
	Id = "brickColorBrowser",
	Name = "BrickColor Browser",
	Description = "Browse and filter all BrickColors. Click a color to apply it to selected parts.",

	DefaultSettings = {
		Filter = "2006",
		Search = "",
	},

	RenderSettings = BrickColorBrowserSettings,
}

return BrickColorBrowser
