-- Briefly render the given parts in front of the camera so their meshes get
-- uploaded to graphics memory - showing a mesh for the first time otherwise
-- renders wrong (or not at all) for a frame while it uploads.
--
-- The parts are mutated (size, transparency, CFrame...) and left unparented,
-- so callers should pass throwaway instances (clones share their mesh
-- resource with the original, so warming a clone warms the original's mesh).

local RunService = game:GetService("RunService")

local function warmRenderParts(parts: {BasePart})
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local warmFolder = Instance.new("Folder")
	warmFolder.Name = "MaterialFlipRenderWarm"
	warmFolder.Archivable = false
	for _, part in parts do
		part.Archivable = false
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 0.9
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.CFrame = camera.CFrame * CFrame.new(0, 0, -15)
		part.Parent = warmFolder
	end
	warmFolder.Parent = camera
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	for _, part in parts do
		part.Parent = nil
	end
	warmFolder:Destroy()
end

return warmRenderParts
