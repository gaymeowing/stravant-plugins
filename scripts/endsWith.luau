local function endsWith(s: string, endsWith: string): boolean
	local endingLength = #endsWith
	local length = #s

	if length < endingLength then
		return false
	end
	return string.sub(s, length - endingLength + 1, length) == endsWith
end

return endsWith
