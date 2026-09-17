local TestTypes = require("./TestTypes")
local preloadMeshRepresentations = require("./preloadMeshRepresentations")

return function(t: TestTypes.TestContext)
	t.test("is safe to call repeatedly", function()
		-- The preload itself runs in the background; this covers that kicking
		-- it off is non-yielding, doesn't error, and is idempotent
		preloadMeshRepresentations()
		preloadMeshRepresentations()
	end)
end
