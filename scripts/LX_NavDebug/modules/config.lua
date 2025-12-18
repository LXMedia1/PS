local Config = {}

-- Enable/disable toggle
Config.enabled = false

-- Render settings
Config.render_distance = 100  -- yards
Config.cone_angle = 90        -- degrees (front cone)
Config.edge_thickness = 2     -- line thickness

-- Data path (relative to scripts_data/)
Config.data_path = "navvis"

-- Tile grid size to load around player
Config.tile_grid_size = 3  -- 3x3 grid

-- NavArea types (from TrinityCore)
Config.NAV_AREA_EMPTY = 0
Config.NAV_AREA_MAGMA_SLIME = 8
Config.NAV_AREA_WATER = 9
Config.NAV_AREA_GROUND_STEEP = 10
Config.NAV_AREA_GROUND = 11

-- Edge types
Config.EDGE_INTERNAL = 0
Config.EDGE_BORDER = 1
Config.EDGE_PORTAL = 2

-- Colors per area type (RGBA)
Config.colors = {
    [Config.NAV_AREA_EMPTY] = {r = 128, g = 128, b = 128, a = 100},       -- Gray
    [Config.NAV_AREA_MAGMA_SLIME] = {r = 255, g = 50, b = 0, a = 200},    -- Red
    [Config.NAV_AREA_WATER] = {r = 0, g = 150, b = 255, a = 200},         -- Blue
    [Config.NAV_AREA_GROUND_STEEP] = {r = 255, g = 150, b = 0, a = 200},  -- Orange
    [Config.NAV_AREA_GROUND] = {r = 0, g = 255, b = 0, a = 200},          -- Green
}

-- Border edge color (brighter white)
Config.border_color = {r = 255, g = 255, b = 255, a = 255}

-- Portal edge color
Config.portal_color = {r = 255, g = 255, b = 0, a = 255}  -- Yellow

-- Internal edge dimming factor
Config.internal_dim_factor = 0.6

-- World constants for tile calculation
-- WoW uses a 64x64 tile grid, with each tile being 533.33333 yards
Config.TILE_SIZE = 533.33333
Config.MAP_SIZE = 64
Config.MAP_OFFSET = 32  -- Center of map

return Config
