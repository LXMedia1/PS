local NavConstants = {}

-- Polygon Flags (verify against core generation settings)
NavConstants.Flags = {
    WALK       = 0x01, -- Standard ground
    SWIM       = 0x02, -- Water/Slime
    UNWALKABLE = 0x04, -- Blocked/Steep
    JUMP       = 0x08, -- Jumpable edge
    DOOR       = 0x10, -- Door trigger
}

-- Area Types (Cost modifiers)
NavConstants.Area = {
    GROUND = 0, -- Cost: 1.0
    WATER  = 1, -- Cost: ? (usually higher)
    ROAD   = 2, -- Cost: 0.9 (preferred)
    DANGER = 3, -- Cost: 20.0 (avoid)
}

return NavConstants