--[[
    Lx_Nav Configuration
    Author: Lexxer

    Constants, magic numbers, and settings for navigation.
]]

local Config = {}

-- PSNG file format constants
Config.PSNG_MAGIC = 0x474E5350  -- 'PSNG'
Config.PSNG_VERSION = 1

-- Header offsets (64 bytes total)
Config.HEADER_SIZE = 64
Config.TILE_INDEX_SIZE = 64 * 64 * 8  -- 32KB

-- Structure sizes
Config.NODE_SIZE = 16
Config.EDGE_SIZE = 20
Config.OFFMESH_SIZE = 28
Config.MAP_EXIT_SIZE = 32

-- Fixed-point scaling
Config.XY_SCALE = 100       -- Multiply by 100 for fixed-point
Config.Z_SCALE = 10         -- Multiply by 10 for Z
Config.COST_SCALE = 100     -- Multiply by 100 for costs
Config.PORTAL_SCALE = 10    -- Portal vertices scaled by 10

-- Area types (from TrinityCore NavArea)
Config.NAV_AREA_EMPTY = 0
Config.NAV_AREA_MAGMA_SLIME = 8
Config.NAV_AREA_WATER = 9
Config.NAV_AREA_GROUND_STEEP = 10
Config.NAV_AREA_GROUND = 11

-- Terrain cost multipliers (already pre-baked in .psng, but useful for display)
Config.TERRAIN_COSTS = {
    [0]  = 10.0,  -- EMPTY (avoid)
    [8]  = 50.0,  -- MAGMA/SLIME (dangerous)
    [9]  = 1.5,   -- WATER (slower)
    [10] = 2.0,   -- STEEP (harder)
    [11] = 1.0,   -- GROUND (normal)
}

-- Map exit types
Config.EXIT_TYPE_PORTAL = 0
Config.EXIT_TYPE_SHIP = 1
Config.EXIT_TYPE_ZEPPELIN = 2
Config.EXIT_TYPE_INSTANCE = 3

-- Faction
Config.FACTION_NEUTRAL = 0
Config.FACTION_ALLIANCE = 1
Config.FACTION_HORDE = 2

-- Edge flags
Config.EDGE_FLAG_CROSS_TILE = 1
Config.EDGE_FLAG_STEEP = 2

-- Off-mesh flags
Config.OFFMESH_FLAG_BIDIRECTIONAL = 1
Config.OFFMESH_FLAG_JUMP = 2
Config.OFFMESH_FLAG_LADDER = 4

-- A* settings
Config.FRAME_BUDGET_MS = 5      -- Max ms per frame for A*
Config.GOAL_TOLERANCE = 5       -- Yards within goal to consider "arrived"

-- Data paths
Config.PSNG_PATH = "scripts_data/psng"

-- Visualization colors (RGBA)
Config.COLOR_START = {r = 0, g = 255, b = 0, a = 200}       -- Green
Config.COLOR_END = {r = 255, g = 0, b = 0, a = 200}         -- Red
Config.COLOR_PATH = {r = 0, g = 255, b = 255, a = 200}      -- Cyan
Config.COLOR_WAYPOINT = {r = 255, g = 255, b = 0, a = 200}  -- Yellow

-- Visualization settings
Config.WAYPOINT_RADIUS = 0.5
Config.PATH_THICKNESS = 2

return Config
