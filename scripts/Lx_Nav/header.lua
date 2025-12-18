--[[
    Lx_Nav - A* Navigation Plugin
    Author: Lexxer

    High-performance pathfinding using optimized .psng navigation graph files.
    Features:
    - A* pathfinding with incremental processing (5ms frame budget)
    - Smooth paths via funnel algorithm
    - Terrain-aware routing
    - Cross-map navigation (ships, zeppelins, portals)
]]

local plugin = {}

plugin["name"]              = "Lx_Nav"
plugin["version"]           = "1.0.0"
plugin["author"]            = "Lexxer"
plugin["load"]              = true

return plugin
