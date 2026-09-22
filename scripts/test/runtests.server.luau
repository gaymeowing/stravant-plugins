_G.__ROACT_17_MOCK_SCHEDULER__ = true

local CaptureService = game:GetService("CaptureService")
local HttpService = game:GetService("HttpService")

local TestRunner = require(script.Parent.TestRunner)

local WS_URL = "ws://localhost:38741"

local function sendJson(ws: WebSocketClient, data: { [string]: any })
	ws:Send(HttpService:JSONEncode(data))
end

local function takeScreenshot(ws: WebSocketClient, name: string?)
	local done = false
	local success = false
	local captureOk, captureErr = pcall(function()
		CaptureService:TakeScreenshotCaptureAsync(function(result, _screenshotCapture)
			success = result == Enum.ScreenshotCaptureResult.Success
			done = true
		end, { UICaptureMode = Enum.UICaptureMode.All })
	end)
	if not captureOk then
		warn("[RunTests] Screenshot failed: " .. tostring(captureErr))
		sendJson(ws, { type = "screenshot", success = false, name = name })
		return
	end

	local waited = 0
	while not done and waited < 5 do
		task.wait(0.1)
		waited += 0.1
	end
	sendJson(ws, { type = "screenshot", success = success, name = name })
end

local function runTests(ws: WebSocketClient, filter: string)
	local src = script.Parent.Src
	local summary = TestRunner.run(src, plugin, filter, {
		screenshot = function(name: string?)
			takeScreenshot(ws, name)
		end,
		onOutput = function(message: string)
			sendJson(ws, { type = "output", message = message })
		end,
		onResult = function(result)
			sendJson(ws, {
				type = "result",
				name = result.name,
				status = result.status,
				error = result.error,
				duration = result.duration,
			})
		end,
	})
	sendJson(ws, {
		type = "done",
		passed = summary.passed,
		failed = summary.failed,
		total = summary.total,
	})
end

local ws: WebSocketClient = HttpService:CreateWebStreamClient(
	Enum.WebStreamClientType.WebSocket,
	{ Url = WS_URL }
)

ws.Opened:Connect(function()
	sendJson(ws, { type = "ready" })
end)

ws.MessageReceived:Connect(function(message: string)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, message)
	if not ok then
		warn("[RunTests] Failed to decode message: " .. message)
		return
	end

	if data.type == "run" then
		local filter = data.filter or "all"
		sendJson(ws, { type = "output", message = "Running tests with filter: " .. filter })

		local runOk, runErr = pcall(runTests, ws, filter)
		if not runOk then
			sendJson(ws, {
				type = "output",
				message = "Fatal error running tests: " .. tostring(runErr),
			})
			sendJson(ws, {
				type = "done",
				passed = 0,
				failed = 1,
				total = 1,
			})
		end
	end
end)

ws.Closed:Connect(function() end)
