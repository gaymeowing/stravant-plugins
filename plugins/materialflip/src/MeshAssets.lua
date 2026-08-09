--!strict

-- Published mesh assets for each (shape, orientation class), generated from
-- the geometry in buildShapeMesh.lua at unit size and uploaded once via
-- AssetService:CreateAssetAsync (owned by stravant). The identity class of
-- each shape is represented by the primitive itself and has no mesh.
--
-- MeshPart representations are identified by these MeshIds - this is the
-- reverse lookup that tells us what shape/orientation a clicked MeshPart is.
-- Orientation ids are stable because Orientation.lua's enumeration is
-- deterministic; these tables pin them permanently.

local Orientation = require("./Orientation")
local ShapeData = require("./ShapeData")

local kAssets: {[string]: {[number]: number}} = {
	Wedge = {
		-- Identity class is 2 (the primitive covers it)
		[1] = 80346279955780,
		[3] = 108277817889361,
		[4] = 72987583208759,
		[5] = 108172817689253,
		[6] = 117404827720381,
		[7] = 96015881632298,
		[8] = 100171084822956,
		[9] = 71523663272461,
		[10] = 135765929600848,
		[11] = 97528077625215,
		[12] = 76068028421080,
	},
	CornerWedge = {
		-- Identity class is 24 (the primitive covers it)
		[1] = 75528959771956,
		[2] = 78842690592062,
		[3] = 115020858005120,
		[4] = 120685846190851,
		[5] = 106849852042953,
		[6] = 128387218095618,
		[7] = 93882669713785,
		[8] = 119080314411119,
		[9] = 138088505696632,
		[10] = 76615216883811,
		[11] = 109693704973297,
		[12] = 85870691147024,
		[13] = 77641322527000,
		[14] = 105951808965714,
		[15] = 136971294238220,
		[16] = 112701690316311,
		[17] = 123837802337051,
		[18] = 126325842789801,
		[19] = 101063652683184,
		[20] = 116794817622010,
		[21] = 82820511817607,
		[22] = 132917309482157,
		[23] = 86807296168743,
	},
	Cylinder = {
		-- Identity class is 1 (the primitive covers it)
		[5] = 129558248019147,
		[6] = 77126782442054,
	},
}

export type MeshInfo = {
	Shape: ShapeData.ShapeName,
	Orientation: Orientation.OrientationId,
}

local kByMeshId: {[string]: MeshInfo} = {}
for shape, list in kAssets do
	for classId, assetId in list do
		kByMeshId["rbxassetid://" .. assetId] = {
			Shape = shape :: ShapeData.ShapeName,
			Orientation = classId,
		}
	end
end

local MeshAssets = {}

function MeshAssets.getMeshId(shape: ShapeData.ShapeName, classId: Orientation.OrientationId): string
	local shapeAssets = kAssets[shape]
	local assetId = shapeAssets and shapeAssets[classId]
	assert(assetId, "No mesh asset for " .. tostring(shape) .. " class " .. tostring(classId))
	return "rbxassetid://" .. assetId
end

function MeshAssets.hasMesh(shape: ShapeData.ShapeName, classId: Orientation.OrientationId): boolean
	local shapeAssets = kAssets[shape]
	return (shapeAssets and shapeAssets[classId]) ~= nil
end

function MeshAssets.fromMeshId(meshId: string): MeshInfo?
	return kByMeshId[meshId]
end

return MeshAssets
