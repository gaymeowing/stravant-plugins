-- Use the toolbar combiner?
local COMBINE_TOOLBAR = false

local createSharedToolbar = require(script.Parent.Packages.createSharedToolbar)
local Signal = require(script.Parent.Packages.Signal)
local define = require(script.Parent.Src.define)

local setButtonActive: (active: boolean) -> () = nil
local buttonClicked = Signal.new()

if COMBINE_TOOLBAR then
	local toolbarSettings: createSharedToolbar.SharedToolbarSettings = {
		ButtonName = define.PluginName,
		ButtonTooltip = define.ButtonTooltip,
		ButtonIcon = define.ButtonIcon,
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
	local toolbar = plugin:CreateToolbar(define.PluginName)
	local button = toolbar:CreateButton(`open{define.PluginName}`, define.ButtonTooltip, define.ButtonIcon, define.PluginName)
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

-- Lazy load the main plugin on first click
local loaded = false
local clickedCn
clickedCn = buttonClicked:Connect(function()
	if not loaded then
		loaded = true
		clickedCn:Disconnect()
		require(script.Parent.Src.main)(plugin, buttonClicked, setButtonActive)
		-- Refire event now that the plugin is listening
		buttonClicked:Fire()
	end
end)
