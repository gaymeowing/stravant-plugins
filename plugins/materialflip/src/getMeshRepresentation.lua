--!strict

-- Create a MeshPart for a (shape, orientation class). The templates for all
-- 36 classes are embedded in the plugin as a single serialized+base64 blob
-- (meshTemplateBlob.lua), deserialized once on first use and cloned per
-- request - no asset download yield. The templates' MeshIds still reference
-- the published assets (MeshAssets.lua), which is what identifyPart keys
-- off; the render meshes stream in lazily in the background.

local AssetService = game:GetService("AssetService")
local SerializationService = game:GetService("SerializationService")
local EncodingService = game:GetService("EncodingService")

local MeshAssets = require("./MeshAssets")
local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")
local meshTemplateBlob = require("./meshTemplateBlob")

local mTemplates: {[string]: MeshPart}? = nil

local function templateKey(shape: ShapeData.ShapeName, classId: Orientation.OrientationId): string
	return shape .. "_" .. classId
end

local function loadTemplates(): {[string]: MeshPart}
	if mTemplates then
		return mTemplates
	end
	local templates: {[string]: MeshPart} = {}
	local ok, err = pcall(function()
		local decoded = EncodingService:Base64Decode(buffer.fromstring(meshTemplateBlob))
		for _, instance in SerializationService:DeserializeInstancesAsync(decoded) do
			if instance:IsA("MeshPart") then
				templates[instance.Name] = instance
			end
		end
	end)
	if not ok then
		warn("MaterialFlip: Failed to load embedded mesh templates: " .. tostring(err))
	end
	mTemplates = templates
	return templates
end

local function getMeshRepresentation(shape: ShapeData.ShapeName, classId: Orientation.OrientationId): MeshPart
	local template = loadTemplates()[templateKey(shape, classId)]
	if template then
		return template:Clone()
	end
	-- Fallback: create from the published asset directly (yields to download)
	warn("MaterialFlip: Missing embedded template for " .. templateKey(shape, classId))
	return AssetService:CreateMeshPartAsync(Content.fromUri(MeshAssets.getMeshId(shape, classId)), {
		-- All our shapes are convex, so Hull collision is exact and cheap
		CollisionFidelity = Enum.CollisionFidelity.Hull,
	})
end

return getMeshRepresentation
