--!strict

local identifyPart = require("./identifyPart")

-- Whether a given part can have its material orientation flipped.
-- Locked parts are skipped unless allowLocked (the Target Locked setting).
local function canFlip(part: BasePart?, allowLocked: boolean?): boolean
	if not part then
		return false
	end
	assert(part)
	if part.Locked and not allowLocked then
		return false
	end
	return identifyPart(part) ~= nil
end

return canFlip
