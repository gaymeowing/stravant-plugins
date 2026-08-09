--!strict

-- Preload the published mesh render content in the background when the tool
-- is activated, so the first flips ideally don't show streaming flicker.
-- Wedges and cylinders preload first: they're much more common in practice
-- and less numerous (13 assets vs 23 corner wedges). PreloadAsync yields
-- until its batch is done, so sequential calls give the priority order.
--
-- This also forces the embedded template blob to deserialize off the
-- activation path, so the first flip doesn't even pay that cost.

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local MeshAssets = require("./MeshAssets")
local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local getMeshRepresentation = require("./getMeshRepresentation")

local mStarted = false

-- PreloadAsync only gets the mesh content into memory; the upload to
-- graphics memory happens when a mesh is actually rendered. So after
-- preloading, briefly parent the (non-Archivable) templates in front of the
-- camera - small and nearly transparent - for a couple of render frames.
local function warmRender(instances: {Instance})
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local warmFolder = Instance.new("Folder")
	warmFolder.Name = "MaterialFlipPreloadWarm"
	warmFolder.Archivable = false
	for _, instance in instances do
		if instance:IsA("BasePart") then
			instance.Archivable = false
			instance.Anchored = true
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false
			instance.CastShadow = false
			instance.Transparency = 0.9
			instance.Size = Vector3.new(0.5, 0.5, 0.5)
			instance.CFrame = camera.CFrame * CFrame.new(0, 0, -15)
			instance.Parent = warmFolder
		end
	end
	warmFolder.Parent = camera
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	warmFolder:Destroy()
end

local function collectTemplates(shapes: {ShapeData.ShapeName}): {Instance}
	local instances: {Instance} = {}
	for _, shape in shapes do
		for m = 1, Orientation.Count do
			if MeshAssets.hasMesh(shape, m) then
				table.insert(instances, getMeshRepresentation(shape, m))
			end
		end
	end
	return instances
end

local function preloadMeshRepresentations()
	if mStarted then
		return
	end
	mStarted = true
	task.spawn(function()
		local ok, err = pcall(function()
			local batches = {
				collectTemplates({"Wedge", "Cylinder"}),
				collectTemplates({"CornerWedge"}),
			}
			for _, batch in batches do
				ContentProvider:PreloadAsync(batch)
				warmRender(batch)
				for _, instance in batch do
					instance:Destroy()
				end
			end
		end)
		if not ok then
			warn("MaterialFlip: Mesh preload failed: " .. tostring(err))
		end
	end)
end

return preloadMeshRepresentations
