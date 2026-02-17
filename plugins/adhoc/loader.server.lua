-- Use the toolbar combiner?
local COMBINE_TOOLBAR = false

local createSharedToolbar = require(script.Parent.Packages.createSharedToolbar)
local Signal = require(script.Parent.Packages.Signal)

local RIBBON_ICON = "rbxassetid://111115477526194"
local TOOLTIP = "Open Adhoc Tools panel — a collection of small community-requested tools."

local setButtonActive: (active: boolean) -> () = nil
local buttonClicked = Signal.new()

if COMBINE_TOOLBAR then
	local toolbarSettings: createSharedToolbar.SharedToolbarSettings = {
		ButtonName = "Adhoc Tools",
		ButtonTooltip = TOOLTIP,
		ButtonIcon = RIBBON_ICON,
		ToolbarName = "GeomTools",
		CombinerName = "GeomToolsToolbar",
		ClickedFn = function()
			buttonClicked:Fire()
		end,
	}
	createSharedToolbar(plugin, toolbarSettings)
	function setButtonActive(active: boolean)
		assert(toolbarSettings.Button):SetActive(active)
	end
else
	local toolbar = plugin:CreateToolbar("Adhoc Tools")
	local button = toolbar:CreateButton("openAdhocTools", TOOLTIP, RIBBON_ICON, "AdHoc")
	local clickCn = button.Click:Connect(function()
		buttonClicked:Fire()
	end)
	function setButtonActive(active: boolean)
		button:SetActive(active)
	end
	plugin.Unloading:Connect(function()
		clickCn:Disconnect()
	end)
end

-- Create the dockable panel
local params = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false, -- Is it initially enabled
	false, -- Override the previous state
	240, -- Default width
	400, -- Default height
	240, -- Minimum width
	200  -- Minimum height
)
local panel = plugin:CreateDockWidgetPluginGuiAsync("AdhocToolsPanel", params)

-- Register panel for cross-plugin access (used by screenshot tool)
local panels: { [string]: DockWidgetPluginGui } = _G.__PluginPanels or {}
_G.__PluginPanels = panels
panels["AdhocTools"] = panel

local loaded = false
local function doInitialLoad()
	loaded = true
	require(script.Parent.Src.main)(plugin, panel, buttonClicked, setButtonActive)
end

-- Lazy load the main plugin on first click
local clickedCn = buttonClicked:Connect(function()
	if not loaded then
		doInitialLoad()
		-- Refire event now that the plugin is listening
		buttonClicked:Fire()
	end
end)

panel.Title = "Adhoc Tools"
panel.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if panel.Enabled then
	doInitialLoad()
end

plugin.Deactivation:Connect(function()
	clickedCn:Disconnect()
end)
