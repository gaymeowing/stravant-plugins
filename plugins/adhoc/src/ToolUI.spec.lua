--!strict
local Packages = script.Parent.Parent.Packages
local React = require(Packages.React)
local ReactRoblox = require(Packages.ReactRoblox)

local TestTypes = require("./TestTypes")
local ToolTypes = require("./ToolTypes")

type ToolDefinition = ToolTypes.ToolDefinition
type ToolSettingsProps = ToolTypes.ToolSettingsProps

local e = React.createElement

return function(t: TestTypes.TestContext)
	-- Discover all tools the same way main.lua does
	local allTools: { ToolDefinition } = {}
	local loadErrors: { string } = {}
	for _, module in script.Parent.Tools:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, tool = pcall(require, module)
			if not ok then
				table.insert(loadErrors, `{module.Name}: {tool}`)
			else
				table.insert(allTools, tool :: ToolDefinition)
			end
		end
	end
	table.sort(allTools, function(a, b)
		return a.Name < b.Name
	end)

	t.test("all tools load without errors", function()
		if #loadErrors > 0 then
			t.fail("Tool load errors:\n" .. table.concat(loadErrors, "\n"))
		end
	end)

	t.test("discovers at least one tool", function()
		t.expect(#allTools > 0).toBe(true)
	end)

	-- Smoke test each tool's RenderSettings
	for _, tool in allTools do
		t.test(tool.Name .. " has required fields", function()
			t.expect(tool.Id ~= nil and tool.Id ~= "").toBe(true)
			t.expect(tool.Name ~= nil and tool.Name ~= "").toBe(true)
			t.expect(tool.Description ~= nil and tool.Description ~= "").toBe(true)
		end)

		if tool.RenderSettings then
			t.test(tool.Name .. " RenderSettings mounts without error", function()
				-- Initialize settings from defaults
				local settings: { [string]: any } = {}
				if tool.DefaultSettings then
					for k, v in tool.DefaultSettings do
						settings[k] = v
					end
				end

				local props: ToolSettingsProps = {
					GetSetting = function(key: string): any
						return settings[key]
					end,
					SetSetting = function(key: string, value: any)
						settings[key] = value
					end,
					LayoutOrder = 1,
				}

				-- Mount into a temporary ScreenGui
				local screenGui = Instance.new("ScreenGui")
				screenGui.Parent = game:GetService("CoreGui")

				local root = ReactRoblox.createRoot(screenGui)
				ReactRoblox.act(function()
					root:render(e(tool.RenderSettings :: any, props))
				end)

				-- Verify something was rendered
				t.expect(#screenGui:GetChildren() > 0).toBe(true)

				-- Cleanup
				ReactRoblox.act(function()
					root:unmount()
				end)
				screenGui:Destroy()
			end)
		end

		if tool.DefaultSettings then
			t.test(tool.Name .. " DefaultSettings are valid", function()
				t.expect(type(tool.DefaultSettings) == "table").toBe(true)
				-- Ensure settings are serializable (no userdata except known types)
				for key, value in tool.DefaultSettings :: { [string]: any } do
					t.expect(type(key) == "string").toBe(true)
					local vtype = type(value)
					local isSerializable = vtype == "string"
						or vtype == "number"
						or vtype == "boolean"
						or vtype == "table"
					t.expect(isSerializable).toBe(true)
				end
			end)
		end
	end

	-- Test that tool IDs are unique
	t.test("all tool IDs are unique", function()
		local seen: { [string]: boolean } = {}
		for _, tool in allTools do
			t.expect(seen[tool.Id] == nil).toBe(true)
			seen[tool.Id] = true
		end
	end)
end
