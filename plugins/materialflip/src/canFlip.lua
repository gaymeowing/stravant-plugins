--!strict

local getShape = require("./getShape")

-- Whether a given part can have its material orientation flipped.
local function canFlip(part: BasePart?): boolean
	if not part then
		return false
	end
	assert(part)
	if part.Locked then
		return false
	end
	local shape = getShape(part)
	return shape == "Brick" or shape == "Wedge" or shape == "Round"
end

return canFlip
