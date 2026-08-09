--!strict

-- Create a MeshPart for a (shape, orientation class) from the published
-- mesh assets. The mesh geometry is the unit-size shape with the class
-- rotation baked in; the caller sets Size (axis-permuted) and CFrame.
--
-- Creating a MeshPart from an asset yields while the mesh downloads, so
-- templates are cached and cloned on subsequent uses.

local AssetService = game:GetService("AssetService")

local MeshAssets = require("./MeshAssets")
local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")

local kTemplateCache: {[string]: MeshPart} = {}

local function getMeshRepresentation(shape: ShapeData.ShapeName, classId: Orientation.OrientationId): MeshPart
	local meshId = MeshAssets.getMeshId(shape, classId)
	local template = kTemplateCache[meshId]
	if not template then
		-- All our shapes are convex, so Hull collision is exact and cheap
		template = AssetService:CreateMeshPartAsync(Content.fromUri(meshId), {
			CollisionFidelity = Enum.CollisionFidelity.Hull,
		})
		kTemplateCache[meshId] = template
	end
	return template:Clone()
end

return getMeshRepresentation
