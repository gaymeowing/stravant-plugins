--!strict

-- Create the tiny negative frame-donor part used for CSG material rotations.
-- As the first input of UnionAsync, its CFrame becomes the result's local
-- frame (and therefore the material frame), while - being negative geometry
-- disjoint from the part - it contributes nothing to the result's shape.
--
-- NegateOperations can't be created with usable CSG data via Instance.new,
-- so an embedded serialized template (made with plugin:Negate) is
-- deserialized once and cloned per use. Returns nil if the template fails
-- to load.

local SerializationService = game:GetService("SerializationService")
local EncodingService = game:GetService("EncodingService")

local negateTemplateBlob = require("./negateTemplateBlob")

local mTemplate: BasePart? = nil

local function getNegateHelper(): BasePart?
	if not mTemplate then
		local ok, err = pcall(function()
			local decoded = EncodingService:Base64Decode(buffer.fromstring(negateTemplateBlob))
			for _, instance in SerializationService:DeserializeInstancesAsync(decoded) do
				if instance:IsA("BasePart") then
					mTemplate = instance
				end
			end
		end)
		if not ok then
			warn("MaterialFlip: Failed to load the negate helper template: " .. tostring(err))
		end
	end
	local template = mTemplate
	return if template then template:Clone() else nil
end

return getNegateHelper
