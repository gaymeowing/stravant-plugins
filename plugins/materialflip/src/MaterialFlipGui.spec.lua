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
	t.test("Active panelized smoke", function()
		mountAndUnmount("active", true)
	end)
	t.test("Inactive panelized smoke", function()
		mountAndUnmount("inactive", true)
	end)
end
