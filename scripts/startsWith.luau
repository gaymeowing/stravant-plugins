local function startsWith(s: string, startsWith: string): boolean
	return string.sub(s, 1, #startsWith) == startsWith
end

return startsWith
