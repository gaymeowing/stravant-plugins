--!strict

-- Pick which bounding box face a click on a part acts on.
--
-- The hit normal, not the closest box face to the hit point, drives the
-- choice: on sloped surfaces (wedge/corner wedge slopes) the closest box
-- face changes as you move toward the thin end - clicking a wedge slope
-- near the bottom lip used to rotate the back face. The surface normal is
-- constant across a sloped face, so alignment with it gives one consistent
-- answer for the whole surface. The camera direction breaks near ties
-- (e.g. a 45 degree slope is equally aligned with two box faces: prefer
-- the one facing the viewer).

local identifyPart = require("./identifyPart")

local kNormalIds = {
	Enum.NormalId.Right, Enum.NormalId.Left,
	Enum.NormalId.Top, Enum.NormalId.Bottom,
	Enum.NormalId.Back, Enum.NormalId.Front,
}

-- The camera direction can only override up to this much alignment deficit
local kCameraBias = 0.05

local function pickRotationFace(state: identifyPart.PartState, worldPoint: Vector3, worldNormal: Vector3): Enum.NormalId
	local localNormal = state.ShapeCFrame:VectorToObjectSpace(worldNormal)

	local localToCamera = Vector3.zero
	local camera = workspace.CurrentCamera
	if camera then
		local toCamera = camera.CFrame.Position - worldPoint
		if toCamera.Magnitude > 0.001 then
			localToCamera = state.ShapeCFrame:VectorToObjectSpace(toCamera.Unit)
		end
	end

	local bestScore = -math.huge
	local bestFace = Enum.NormalId.Top
	for _, face in kNormalIds do
		local faceNormal = Vector3.fromNormalId(face)
		local score = faceNormal:Dot(localNormal) + kCameraBias * faceNormal:Dot(localToCamera)
		if score > bestScore then
			bestScore = score
			bestFace = face
		end
	end
	return bestFace
end

return pickRotationFace
