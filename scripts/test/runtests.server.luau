_G.__ROACT_17_MOCK_SCHEDULER__ = true

local CaptureService = game:GetService("CaptureService")
local HttpService = game:GetService("HttpService")

local TestRunner = require("./TestRunner")

local WEBSOCKET_URL = "ws://localhost:38741"

type RunMessage = {
	type: string?,
	filter: string?,
}

local websocket = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
	Url = WEBSOCKET_URL,
})

local function sendJson(data: { [string]: any })
	websocket:Send(HttpService:JSONEncode(data))
end

local function takeScreenshot(name: string?)
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
		sendJson({ type = "screenshot", success = false, name = name })
		return
	end

	local waited = 0
	while not done and waited < 5 do
		task.wait(0.1)
		waited += 0.1
	end
	sendJson({ type = "screenshot", success = success, name = name })
end

local function runTests(filter: string)
	local src = (script.Parent :: any):FindFirstChild("Src") :: Instance

	local summary = TestRunner.run(src, plugin, filter, {
		screenshot = takeScreenshot,
		onOutput = function(message: string)
			sendJson({ type = "output", message = message })
		end,
		onResult = function(result: {
			name: string,
			status: "pass" | "fail",
			error: string?,
			duration: number,
		})
			sendJson({
				type = "result",
				name = result.name,
				status = result.status,
				error = result.error,
				duration = result.duration,
			})
		end,
	})
	sendJson({
		type = "done",
		passed = summary.passed,
		failed = summary.failed,
		total = summary.total,
	})
end

websocket.Opened:Connect(function()
	sendJson({ type = "ready" })
end)

websocket.MessageReceived:Connect(function(message: string)
	local data = HttpService:JSONDecode(message) :: RunMessage

	if data.type == "run" then
		local filter = data.filter or "all"
		sendJson({ type = "output", message = "Running tests with filter: " .. filter })

		-- pcall of a void function is typed as returning only boolean; return a value so we get the error too.
		local runOk, runErr = pcall(function()
			runTests(filter)
			return true
		end)
		if not runOk then
			sendJson({
				type = "output",
				message = "Fatal error running tests: " .. tostring(runErr),
			})
			sendJson({
				type = "done",
				passed = 0,
				failed = 1,
				total = 1,
			})
		end
	end
end)
