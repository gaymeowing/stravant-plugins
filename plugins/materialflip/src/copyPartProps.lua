--!strict

-- Copy the visual/physical properties that should survive swapping a part's
-- representation (primitive <-> MeshPart) during a material flip.

local kProps = {
	"Name",
	"Color",
	"Material",
	"MaterialVariant",
	"Transparency",
	"Reflectance",
	"Anchored",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"CollisionGroup",
	"Massless",
	"RootPriority",
	"PivotOffset",
}

local function copyPartProps(from: BasePart, to: BasePart)
	for _, prop in kProps do
		(to :: any)[prop] = (from :: any)[prop]
	end
	-- Attributes and tags are part of the part's contents too
	for name, value in from:GetAttributes() do
		to:SetAttribute(name, value)
	end
	for _, tag in from:GetTags() do
		to:AddTag(tag)
	end
end

return copyPartProps
