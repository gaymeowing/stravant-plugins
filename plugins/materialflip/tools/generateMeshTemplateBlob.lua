-- Regenerates the mesh template blob for src/meshTemplateBlob.lua.
--
-- Run this in the Studio command bar (or via MCP execute_luau). It creates
-- one MeshPart per published mesh asset (see src/MeshAssets.lua - keep the
-- table below in sync with it), serializes them all as a single blob,
-- base64 encodes it, verifies the round trip, and returns the base64 text.
-- Paste the resulting text into src/meshTemplateBlob.lua (chunked; see the
-- existing file's format).
--
-- The single combined blob matters: the rbxm format shares string/property
-- tables, so 36 templates in one blob are ~9.6 KB of base64 vs ~163 KB as
-- individual blobs.

local AssetService = game:GetService("AssetService")
local SerializationService = game:GetService("SerializationService")
local EncodingService = game:GetService("EncodingService")

-- Must match src/MeshAssets.lua
local assets = {
	Wedge = {
		[1] = 80346279955780, [3] = 108277817889361, [4] = 72987583208759,
		[5] = 108172817689253, [6] = 117404827720381, [7] = 96015881632298,
		[8] = 100171084822956, [9] = 71523663272461, [10] = 135765929600848,
		[11] = 97528077625215, [12] = 76068028421080,
	},
	CornerWedge = {
		[1] = 75528959771956, [2] = 78842690592062, [3] = 115020858005120,
		[4] = 120685846190851, [5] = 106849852042953, [6] = 128387218095618,
		[7] = 93882669713785, [8] = 119080314411119, [9] = 138088505696632,
		[10] = 76615216883811, [11] = 109693704973297, [12] = 85870691147024,
		[13] = 77641322527000, [14] = 105951808965714, [15] = 136971294238220,
		[16] = 112701690316311, [17] = 123837802337051, [18] = 126325842789801,
		[19] = 101063652683184, [20] = 116794817622010, [21] = 82820511817607,
		[22] = 132917309482157, [23] = 86807296168743,
	},
	Cylinder = {
		[5] = 129558248019147, [6] = 77126782442054,
	},
}

-- Deterministic order for reproducible blobs
local parts = {}
for _, shapeName in {"Wedge", "CornerWedge", "Cylinder"} do
	local classIds = {}
	for classId in assets[shapeName] do
		table.insert(classIds, classId)
	end
	table.sort(classIds)
	for _, classId in classIds do
		local part = AssetService:CreateMeshPartAsync(
			Content.fromUri("rbxassetid://" .. assets[shapeName][classId]), {
				CollisionFidelity = Enum.CollisionFidelity.Hull,
			})
		part.Name = shapeName .. "_" .. classId
		table.insert(parts, part)
	end
end

local blob = SerializationService:SerializeInstancesAsync(parts)
local encodedString = buffer.tostring(EncodingService:Base64Encode(blob))

-- Round trip verification
local restored = SerializationService:DeserializeInstancesAsync(
	EncodingService:Base64Decode(buffer.fromstring(encodedString)))
local byName = {}
for _, instance in restored do
	byName[instance.Name] = instance
end
for _, shapeName in {"Wedge", "CornerWedge", "Cylinder"} do
	for classId, assetId in assets[shapeName] do
		local instance = byName[shapeName .. "_" .. classId]
		assert(instance and instance:IsA("MeshPart"), "missing template " .. shapeName .. "_" .. classId)
		assert(instance.MeshId == "rbxassetid://" .. assetId, "MeshId mismatch for " .. instance.Name)
	end
end

for _, part in parts do part:Destroy() end
for _, instance in restored do instance:Destroy() end

return "VERIFIED " .. #encodedString .. " chars\nBLOB:" .. encodedString
