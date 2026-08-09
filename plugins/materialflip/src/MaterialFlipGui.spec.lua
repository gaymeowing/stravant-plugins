--!strict

local CoreGui = game:GetService("CoreGui")

local TestTypes = require("./TestTypes")

local Packages = script.Parent.Parent.Packages
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

local MaterialFlipGui = require("./MaterialFlipGui")
local TestHelpers = require("./TestHelpers")

local e = React.createElement

local function mountAndUnmount(guiState: "inactive" | "active", panelized: boolean)
	local screen = Instance.new("ScreenGui")
	screen.Name = "MaterialFlipGuiTest"
	screen.Parent = CoreGui

	local root = ReactRoblox.createRoot(screen)
	ReactRoblox.act(function()
		root:render(e(MaterialFlipGui, {
			GuiState = guiState,
			CurrentSettings = TestHelpers.makeTestSettings(),
			UpdatedSettings = function() end,
			HandleAction = function() end,
			Panelized = panelized,
			StatusText = "Hover over a part and click to rotate its material.",
			StatusIsWarning = false,
		}))
	end)

	ReactRoblox.act(function()
		root:unmount()
	end)
	screen:Destroy()
end

return function(t: TestTypes.TestContext)
	t.test("Active floating window smoke", function()
		mountAndUnmount("active", false)
	end)
	t.test("Warning status smoke", function()
		local screen = Instance.new("ScreenGui")
		screen.Name = "MaterialFlipGuiWarningTest"
		screen.Parent = CoreGui
		local root = ReactRoblox.createRoot(screen)
		ReactRoblox.act(function()
			root:render(e(MaterialFlipGui, {
				GuiState = "active",
				CurrentSettings = TestHelpers.makeTestSettings(),
				UpdatedSettings = function() end,
				HandleAction = function() end,
				Panelized = false,
				StatusText = "This part is not a primitive shape. It will be rotated as if it were a box.",
				StatusIsWarning = true,
			}))
		end)
		ReactRoblox.act(function()
			root:unmount()
		end)
		screen:Destroy()
	end)
	t.test("Active panelized smoke", function()
		mountAndUnmount("active", true)
	end)
	t.test("Inactive panelized smoke", function()
		mountAndUnmount("inactive", true)
	end)
end
