--!strict

-- Perform the material flip on a single part, as a single undoable operation.
--  * Brick shapes rotate a quarter turn about the axis of the clicked face,
--    swapping dimensions and surface types so the part occupies the same
--    space with a different material orientation.
--  * Wedge shapes rotate the material 180 degrees by exchanging the slope's
--    two "square" ends.
--  * Round shapes rotate 180 degrees about the axis through the click point.

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local getShape = require("./getShape")

local function cframeFromTopBack(at: Vector3, top: Vector3, back: Vector3): CFrame
	return CFrame.fromMatrix(at, top:Cross(back), top, back)
end

local function flipWedge(part: BasePart)
	local cf = part.CFrame
	local front = -cf.ZVector
	local top = cf.YVector
	part.TopSurface, part.FrontSurface = part.FrontSurface, part.TopSurface
	part.BottomSurface, part.BackSurface = part.BackSurface, part.BottomSurface
	part.RightSurface, part.LeftSurface = part.LeftSurface, part.RightSurface
	pcall(function()
		-- Legacy FormFactor parts can't freely resize without this
		(part :: any).FormFactor = Enum.FormFactor.Custom
	end)
	part.Size = Vector3.new(part.Size.X, part.Size.Z, part.Size.Y)
	part:BreakJoints()
	part.CFrame = cframeFromTopBack(cf.Position, front, -top)
end

local function flipRound(part: BasePart, point: Vector3)
	local cf = part.CFrame
	local pos = cf.Position
	local axis = point - pos
	if axis.Magnitude < 0.0001 then
		return
	end
	local rot = CFrame.fromAxisAngle(axis.Unit, math.pi)
	part.CFrame = (rot * (cf - pos)) + pos
end

local function flipBrick(part: BasePart, normalId: Enum.NormalId)
	local cf = part.CFrame
	local pos = cf.Position
	local axis = cf:VectorToWorldSpace(Vector3.fromNormalId(normalId))
	local rot = CFrame.fromAxisAngle(axis, math.pi / 2)
	local targetCF = (rot * (cf - pos)) + pos
	local size = part.Size
	local targetSize
	if normalId == Enum.NormalId.Front or normalId == Enum.NormalId.Back then
		targetSize = Vector3.new(size.Y, size.X, size.Z)
		if normalId == Enum.NormalId.Front then
			part.RightSurface, part.TopSurface, part.LeftSurface, part.BottomSurface =
				part.BottomSurface, part.RightSurface, part.TopSurface, part.LeftSurface
		else
			part.RightSurface, part.TopSurface, part.LeftSurface, part.BottomSurface =
				part.TopSurface, part.LeftSurface, part.BottomSurface, part.RightSurface
		end
	elseif normalId == Enum.NormalId.Top or normalId == Enum.NormalId.Bottom then
		targetSize = Vector3.new(size.Z, size.Y, size.X)
		if normalId == Enum.NormalId.Top then
			part.FrontSurface, part.RightSurface, part.BackSurface, part.LeftSurface =
				part.LeftSurface, part.FrontSurface, part.RightSurface, part.BackSurface
		else
			part.FrontSurface, part.RightSurface, part.BackSurface, part.LeftSurface =
				part.RightSurface, part.BackSurface, part.LeftSurface, part.FrontSurface
		end
	else
		targetSize = Vector3.new(size.X, size.Z, size.Y)
		if normalId == Enum.NormalId.Right then
			part.TopSurface, part.FrontSurface, part.BottomSurface, part.BackSurface =
				part.BackSurface, part.TopSurface, part.FrontSurface, part.BottomSurface
		else
			part.TopSurface, part.FrontSurface, part.BottomSurface, part.BackSurface =
				part.FrontSurface, part.BottomSurface, part.BackSurface, part.TopSurface
		end
	end
	part.Size = targetSize
	part:BreakJoints() -- Needed to "unstick" hinges.
	part.CFrame = targetCF
end

local function doFlip(part: BasePart, point: Vector3, normalId: Enum.NormalId)
	local recording = ChangeHistoryService:TryBeginRecording("MaterialFlip", "Material Flip")
	part:BreakJoints()
	local shape = getShape(part)
	if shape == "Wedge" then
		flipWedge(part)
	elseif shape == "Round" then
		flipRound(part, point)
	else
		flipBrick(part, normalId)
	end
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:SetWaypoint("MaterialFlip")
	end
end

return doFlip
