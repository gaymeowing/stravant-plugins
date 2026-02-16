--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local StudioService = game:GetService("StudioService")

local Plugin = script.Parent.Parent.Parent
local Packages = Plugin.Packages
local React = require(Packages.React)

local Checkbox = require("../PluginGui/Checkbox")
local Colors = require("../PluginGui/Colors")
local ToolTypes = require("../ToolTypes")

type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

local kMaxHistory = 20
local kColumnBg = Color3.fromRGB(28, 28, 28)

-- Common services to prepopulate the targets list with
local kDefaultTargetNames = {
	"Workspace",
	"ReplicatedStorage",
	"ServerStorage",
	"ServerScriptService",
	"Lighting",
	"StarterGui",
	"StarterPlayer",
	"StarterPack",
	"SoundService",
	"ReplicatedFirst",
}

local function getDefaultTargets(): { { Instance } }
	local targets: { { Instance } } = {}
	for _, name in kDefaultTargetNames do
		local ok, service = pcall(function()
			return game:GetService(name)
		end)
		if ok and service then
			table.insert(targets, { service })
		end
	end
	return targets
end

local function getAlive(instances: { Instance }): { Instance }
	local alive = {}
	for _, inst in instances do
		if inst.Parent ~= nil or inst == game then
			table.insert(alive, inst)
		end
	end
	return alive
end

local function selectionsEqual(a: { Instance }, b: { Instance }): boolean
	if #a ~= #b then
		return false
	end
	local set: { [Instance]: boolean } = {}
	for _, inst in a do
		set[inst] = true
	end
	for _, inst in b do
		if not set[inst] then
			return false
		end
	end
	return true
end

local function describeInstances(instances: { Instance }): string
	local alive = getAlive(instances)
	if #alive == 0 then
		return "(deleted)"
	elseif #alive == 1 then
		return alive[1].Name
	elseif #alive <= 2 then
		local names = {}
		for _, inst in alive do
			table.insert(names, inst.Name)
		end
		return table.concat(names, ", ")
	else
		return alive[1].Name .. " +" .. (#alive - 1)
	end
end

-- Filter out instances that can't be reparented (services, Terrain)
local function filterReparentable(instances: { Instance }): { Instance }
	local result = {}
	for _, inst in instances do
		if inst.Parent == game or inst:IsA("Terrain") then
			continue
		end
		table.insert(result, inst)
	end
	return result
end

-- Check if every instance in `sub` is also in `super`
local function isSubsetOf(sub: { Instance }, super: { Instance }): boolean
	local set: { [Instance]: boolean } = {}
	for _, inst in super do
		set[inst] = true
	end
	for _, inst in sub do
		if not set[inst] then
			return false
		end
	end
	return true
end

-- Add to front of history, removing any older duplicate or subset entries.
-- If the new selection is a strict superset of an existing entry (e.g. from
-- Shift+Click extending), the old entry is replaced by the new one.
local function addToHistory(
	historyRef: { current: { { Instance } } },
	sel: { Instance }
)
	local history = historyRef.current
	-- Build new list: new entry first, skip duplicates and strict subsets
	local newHistory = { sel }
	for _, existing in history do
		if selectionsEqual(existing, sel) then
			continue -- exact duplicate
		end
		if isSubsetOf(existing, sel) then
			continue -- old entry is a subset of the new one (Shift+Select)
		end
		table.insert(newHistory, existing)
	end
	if #newHistory > kMaxHistory then
		while #newHistory > kMaxHistory do
			table.remove(newHistory)
		end
	end
	historyRef.current = newHistory
	return true
end

-- Perform the reparent operation with undo support, then restore selection
local function doReparent(
	alive: { Instance },
	target: Instance,
	suppressRef: { current: boolean },
	selectAfter: boolean,
	restoreSelection: { Instance }
)
	suppressRef.current = true
	local id = ChangeHistoryService:TryBeginRecording("Reparent")
	for _, inst in alive do
		inst.Parent = target
	end
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:SetWaypoint("Reparent")
	end
	if selectAfter then
		Selection:Set(alive)
	else
		Selection:Set(restoreSelection)
	end
	suppressRef.current = false
end

-- Get class icon info for a given class name
local function getClassIcon(className: string): { Image: string, ImageRectOffset: Vector2, ImageRectSize: Vector2 }?
	local ok, info = pcall(function()
		return StudioService:GetClassIcon(className)
	end)
	if ok and info then
		return info
	end
	return nil
end

-- A single clickable entry row
local function EntryRow(props: {
	Text: string,
	Count: number,
	ClassName: string?,
	IsActive: boolean,
	OnClick: () -> (),
	LayoutOrder: number,
})
	local isHovered, setIsHovered = React.useState(false)
	local bg = if props.IsActive
		then Colors.ACTION_BLUE
		elseif isHovered then Colors.GREY
		else kColumnBg

	local icon = if props.ClassName then getClassIcon(props.ClassName) else nil
	local kIconSize = 16
	local hasIcon = icon ~= nil
	local textOffset = if hasIcon then kIconSize + 4 else 0
	local countOffset = if props.Count > 1 then 18 else 0

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = bg,
		BackgroundTransparency = if props.IsActive then 0.15 else 0,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = props.LayoutOrder,
		[React.Event.MouseButton1Click] = props.OnClick,
		[React.Event.MouseEnter] = function()
			setIsHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setIsHovered(false)
		end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
		}),
		Icon = hasIcon and e("ImageLabel", {
			Size = UDim2.fromOffset(kIconSize, kIconSize),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Image = icon.Image,
			ImageRectOffset = icon.ImageRectOffset,
			ImageRectSize = icon.ImageRectSize,
			ScaleType = Enum.ScaleType.Crop,
		}),
		Label = e("TextLabel", {
			Size = UDim2.new(1, -(textOffset + countOffset), 1, 0),
			Position = UDim2.new(0, textOffset, 0, 0),
			BackgroundTransparency = 1,
			Text = props.Text,
			TextColor3 = Colors.WHITE,
			Font = Enum.Font.SourceSans,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Count = if props.Count > 1
			then e("TextLabel", {
				Size = UDim2.new(0, 16, 1, 0),
				Position = UDim2.new(1, -16, 0, 0),
				BackgroundTransparency = 1,
				Text = tostring(props.Count),
				TextColor3 = Colors.OFFWHITE,
				Font = Enum.Font.SourceSans,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			else nil,
	})
end

-- React settings component — all logic lives here via useEffect so the tool
-- doesn't need OnActivated / OnClicked and won't steal input from Studio tools.
local function ReparentSettings(props: ToolSettingsProps)
	local _, setRenderCount = React.useState(0)
	local selectionsRef = React.useRef(nil :: { { Instance } }?)
	local targetsRef = React.useRef(nil :: { { Instance } }?)
	local pickIndexRef = React.useRef(nil :: number?)
	local suppressRef = React.useRef(false)
	local prevSelectionRef = React.useRef({} :: { Instance })

	local function forceUpdate()
		setRenderCount(function(n: number)
			return n + 1
		end)
	end

	-- One-time initialization on first render
	if not targetsRef.current then
		targetsRef.current = getDefaultTargets()
	end
	if not selectionsRef.current then
		local sel = filterReparentable(Selection:Get())
		selectionsRef.current = if #sel > 0 then { sel } else {}
	end

	-- Connect to SelectionChanged on mount, disconnect on unmount
	React.useEffect(function()
		local connection = Selection.SelectionChanged:Connect(function()
			if suppressRef.current then
				return
			end
			local newSel = Selection:Get()
			local previousSelection = prevSelectionRef.current
			prevSelectionRef.current = newSel

			if #newSel == 0 then
				return
			end

			local pi = pickIndexRef.current
			if pi then
				-- Pick mode: reparent staged items under the new selection
				local entry = (selectionsRef.current :: any)[pi]
				if entry then
					local alive = getAlive(entry)
					if #alive > 0 then
						local target = newSel[1]
						addToHistory(targetsRef :: any, { target })
						doReparent(alive, target, suppressRef, props.GetSetting("SelectAfterReparent") == true, previousSelection)
					end
				end
				pickIndexRef.current = nil
				forceUpdate()
			else
				-- Normal mode: track the selection (filter out non-reparentable)
				local reparentable = filterReparentable(newSel)
				if #reparentable > 0 then
					addToHistory(selectionsRef :: any, reparentable)
					forceUpdate()
				end
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	local selections = selectionsRef.current
	local targets = targetsRef.current or {}
	local pickIndex = pickIndexRef.current

	-- Build selections column children
	local selChildren: { [string]: any } = {}
	selChildren["Corner"] = e("UICorner", { CornerRadius = UDim.new(0, 4) })
	selChildren["Layout"] = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	selChildren["Pad"] = e("UIPadding", {
		PaddingLeft = UDim.new(0, 3),
		PaddingRight = UDim.new(0, 3),
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 3),
	})
	local selCount = 0
	for i, selection in selections do
		local alive = getAlive(selection)
		if #alive > 0 then
			selCount += 1
			selChildren["E" .. i] = e(EntryRow, {
				Text = describeInstances(selection),
				Count = #alive,
				ClassName = alive[1].ClassName,
				IsActive = pickIndex == i,
				OnClick = function()
					if pickIndexRef.current == i then
						pickIndexRef.current = nil
					else
						pickIndexRef.current = i
					end
					forceUpdate()
				end,
				LayoutOrder = i,
			})
		end
	end
	if selCount == 0 then
		selChildren["Empty"] = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = "None yet",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansItalic,
			TextSize = 12,
			LayoutOrder = 1,
		})
	end

	-- Build targets column children
	local tgtChildren: { [string]: any } = {}
	tgtChildren["Corner"] = e("UICorner", { CornerRadius = UDim.new(0, 4) })
	tgtChildren["Layout"] = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	tgtChildren["Pad"] = e("UIPadding", {
		PaddingLeft = UDim.new(0, 3),
		PaddingRight = UDim.new(0, 3),
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 3),
	})
	local tgtCount = 0
	for i, targetEntry in targets do
		local alive = getAlive(targetEntry)
		if #alive > 0 then
			tgtCount += 1
			tgtChildren["E" .. i] = e(EntryRow, {
				Text = describeInstances(targetEntry),
				Count = #alive,
				ClassName = alive[1].ClassName,
				IsActive = false,
				OnClick = function()
					local pi = pickIndexRef.current
					if not pi then
						return
					end
					local entry = selectionsRef.current[pi]
					if not entry then
						return
					end
					local selAlive = getAlive(entry)
					if #selAlive == 0 then
						return
					end
					local tgtAlive = getAlive(targetEntry)
					if #tgtAlive == 0 then
						return
					end
					addToHistory(targetsRef :: any, targetEntry)
					doReparent(selAlive, tgtAlive[1], suppressRef, props.GetSetting("SelectAfterReparent") == true, Selection:Get())
					pickIndexRef.current = nil
					forceUpdate()
				end,
				LayoutOrder = i,
			})
		end
	end

	-- Top-level children
	local children: { [string]: any } = {}

	children["Layout"] = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})

	-- Options
	local selectAfter = props.GetSetting("SelectAfterReparent") == true
	children["SelectAfterCheckbox"] = e(Checkbox, {
		Label = "Select after reparent",
		Checked = selectAfter,
		Changed = function(checked: boolean)
			props.SetSetting("SelectAfterReparent", checked)
		end,
		LayoutOrder = -1,
	})

	-- Current selection preview / pick mode banner
	if not pickIndex then
		-- Show the current selection with a quick-stage button
		local curSel = filterReparentable(Selection:Get())
		local curAlive = if #curSel > 0 then getAlive(curSel) else {}
		local hasCurrent = #curAlive > 0
		local curDesc = if hasCurrent then describeInstances(curAlive) else "Nothing selected"
		local curClassName = if hasCurrent then curAlive[1].ClassName else nil
		local curIcon = if curClassName then getClassIcon(curClassName) else nil

		children["CurrentSel"] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = kColumnBg,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 6),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			Header = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 12),
				BackgroundTransparency = 1,
				Text = "Current Selection",
				TextColor3 = Colors.OFFWHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),
			SelRow = e("Frame", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, {
				Icon = curIcon and e("ImageLabel", {
					Size = UDim2.fromOffset(16, 16),
					Position = UDim2.new(0, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundTransparency = 1,
					Image = curIcon.Image,
					ImageRectOffset = curIcon.ImageRectOffset,
					ImageRectSize = curIcon.ImageRectSize,
					ScaleType = Enum.ScaleType.Crop,
				}),
				Label = e("TextLabel", {
					Size = UDim2.new(1, if curIcon then -20 else 0, 1, 0),
					Position = UDim2.new(0, if curIcon then 20 else 0, 0, 0),
					BackgroundTransparency = 1,
					Text = curDesc,
					TextColor3 = if hasCurrent then Colors.WHITE else Colors.OFFWHITE,
					Font = if hasCurrent then Enum.Font.SourceSans else Enum.Font.SourceSansItalic,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}),
			}),
			StageBtn = hasCurrent and e("TextButton", {
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundColor3 = Colors.ACTION_BLUE,
				AutoButtonColor = true,
				BorderSizePixel = 0,
				Text = "Reparent This",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				LayoutOrder = 3,
				[React.Event.MouseButton1Click] = function()
					-- Ensure this selection is at the front of history, then stage it
					addToHistory(selectionsRef :: any, curAlive)
					pickIndexRef.current = 1
					forceUpdate()
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
		})
	end
	if pickIndex then
		local entry = selections[pickIndex]
		local desc = if entry then describeInstances(entry) else "(none)"

		children["PickBanner"] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = kColumnBg,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 6),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			Label = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 14),
				BackgroundTransparency = 1,
				Text = "Reparenting: " .. desc,
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),
			Hint = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 12),
				BackgroundTransparency = 1,
				Text = "Pick a target below or select one in Explorer",
				TextColor3 = Color3.new(1, 1, 1),
				TextTransparency = 0.3,
				Font = Enum.Font.SourceSans,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
			}),
			CancelBtn = e("TextButton", {
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundColor3 = Colors.DARK_RED,
				AutoButtonColor = true,
				BorderSizePixel = 0,
				Text = "Cancel",
				TextColor3 = Colors.WHITE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 14,
				LayoutOrder = 3,
				[React.Event.MouseButton1Click] = function()
					pickIndexRef.current = nil
					forceUpdate()
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
		})
	end

	-- Column headers row
	children["Headers"] = e("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, {
		SelHeader = e("TextLabel", {
			Size = UDim2.new(0.5, -2, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
			Text = "Selections",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		TgtHeader = e("TextLabel", {
			Size = UDim2.new(0.5, -2, 1, 0),
			Position = UDim2.new(0.5, 2, 0, 0),
			BackgroundTransparency = 1,
			Text = "Targets",
			TextColor3 = Colors.OFFWHITE,
			Font = Enum.Font.SourceSansBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})

	-- Two side-by-side columns
	children["Columns"] = e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, {
		SelColumn = e("Frame", {
			Size = UDim2.new(0.5, -2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = kColumnBg,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, selChildren),
		TgtColumn = e("Frame", {
			Size = UDim2.new(0.5, -2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0.5, 2, 0, 0),
			BackgroundColor3 = kColumnBg,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, tgtChildren),
	})

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	}, children)
end

local Reparent: ToolTypes.ToolDefinition = {
	Id = "reparent",
	Name = "Quick Reparenting",
	Description = "Track recent selections. Click one of them to choose a new parent for it in the list or the Explorer.",

	DefaultSettings = {
		SelectAfterReparent = false,
	},

	RenderSettings = ReparentSettings,
}

return Reparent
