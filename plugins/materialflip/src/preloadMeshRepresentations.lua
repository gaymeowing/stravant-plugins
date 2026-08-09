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

local MeshAssets = require("./MeshAssets")
local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local getMeshRepresentation = require("./getMeshRepresentation")

local mStarted = false

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
		local startTime = os.clock()
		local ok, err = pcall(function()
			local batches = {
				{name = "Wedge/Cylinder", instances = collectTemplates({"Wedge", "Cylinder"})},
				{name = "CornerWedge", instances = collectTemplates({"CornerWedge"})},
			}
			for _, batch in batches do
				local batchStart = os.clock()
				ContentProvider:PreloadAsync(batch.instances)
				print(string.format("MaterialFlip: Preloaded %d %s meshes in %.2fs",
					#batch.instances, batch.name, os.clock() - batchStart))
				for _, instance in batch.instances do
					instance:Destroy()
				end
			end
		end)
		if not ok then
			warn("MaterialFlip: Mesh preload failed: " .. tostring(err))
		else
			print(string.format("MaterialFlip: Mesh preload finished in %.2fs total", os.clock() - startTime))
		end
	end)
end

return preloadMeshRepresentations
