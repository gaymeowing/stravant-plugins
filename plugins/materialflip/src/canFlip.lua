--!strict

local identifyPart = require("./identifyPart")

-- Whether a given part can have its material orientation flipped.
local function canFlip(part: BasePart?): boolean
	if not part then
		return false
	end
	assert(part)
	if part.Locked then
		return false
	end
	return identifyPart(part) ~= nil
end

return canFlip
