-- baseGlobIgnorePaths
-- adds the shared Rojo globIgnorePaths used by build/test projects

local rojo = require("./rojo")

local function addBaseGlobIgnorePaths(project: rojo.Project, ignoreSpecs: boolean?, packagesPrefix: string?)
	local ignores = project.globIgnorePaths
	packagesPrefix = packagesPrefix or ""

	table.insert(ignores, `{packagesPrefix}Packages/_Index/**/examples`)
	table.insert(ignores, `{packagesPrefix}Packages/_Index/**/benchmarks`)
	table.insert(ignores, `{packagesPrefix}Packages/_Index/**/bin`)
	table.insert(ignores, "**/benchmarks.project.json")
	table.insert(ignores, "**/place.project.json")

	if ignoreSpecs then
		table.insert(ignores, "**/*.spec.luau")
	end
end

return addBaseGlobIgnorePaths
