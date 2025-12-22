-- LX_Nav2 Wireframe Visualization Module
-- Renders navmesh polygons in 3D using actual polygon data structures
-- Uses core.graphics.line_2d after w2s conversion for 2D screen-space rendering
-- Uses core.graphics.line_3d for 3D world-space rendering (when available)

local Debug = require("modules/debug")
local DrawPolygon = require("modules/draw_polygon")

local color = require("common/color")
local vec3 = require("common/geometry/vector_3")
local vec2 = require("common/geometry/vector_2")

local Wireframe = {}

-- ===========================================
-- CONFIGURATION
-- ===========================================

local CONFIG = {
    enabled = false,
    draw_range = 50,           -- Only draw polygons within this range (yards)
    draw_filled = true,        -- Draw filled polygons (transparent)
    draw_edges = false,        -- Draw polygon edges (disabled by default)
    draw_walls_only = false,   -- Only draw wall edges (no neighbor)
    draw_centers = false,      -- Draw center points
    draw_penalty_zones = false, -- Draw wall proximity penalty zones
    
    -- Colors
    fill_color = color.new(0, 200, 100, 60),           -- Semi-transparent green fill
    internal_edge_color = color.new(0, 255, 100, 200), -- Green for internal edges
    wall_edge_color = color.new(255, 100, 0, 220),     -- Orange for wall/boundary edges
    external_edge_color = color.new(255, 200, 0, 200), -- Yellow for cross-tile edges
    center_color = color.new(255, 255, 0, 180),        -- Yellow centers
    
    -- Edge thickness
    edge_thickness = 1.5,
    wall_edge_thickness = 2.0,
    
    -- Center radius
    center_radius = 0.3,
    
    -- Height offset to prevent z-fighting
    height_offset = 0.1,
    
    -- Use 2D rendering (w2s + line_2d) vs 3D (line_3d)
    use_2d_rendering = false,
}

-- Edge type constants (mirrors DrawPolygon.EDGE_TYPE)
local EDGE_TYPE = {
    WALL = 0,           -- No neighbor (boundary/wall)
    INTERNAL = 1,       -- Internal neighbor (same tile)
    EXTERNAL = 2,       -- External neighbor (cross-tile, neis >= 0x8000)
}

local DT_EXT_LINK = 0x8000  -- External link flag

-- Tile size constants
local TILE_SIZE = 533.33333
local HALF_WORLD = 32 * TILE_SIZE  -- = 17066.66656

-- ===========================================
-- STATE
-- ===========================================

local current_map_id = nil
local cached_tiles = {}          -- map_id -> {tile_key -> tile_data}
local wireframe_cache = {}       -- tile_key -> wireframe_data
local tiles_dirty = {}           -- tile_key -> true if needs rebuild
local last_tile_count = {}       -- map_id -> count (for change detection)

-- Pre-allocated vec3 objects for rendering (avoid per-frame allocations)
local temp_vec3_1 = nil
local temp_vec3_2 = nil

-- ===========================================
-- UTILITY FUNCTIONS
-- ===========================================

--- Convert world position to tile coordinates
local function world_to_tile(x, y)
    local tile_x = math.floor((HALF_WORLD - x) / TILE_SIZE)
    local tile_y = math.floor((HALF_WORLD - y) / TILE_SIZE)
    -- Clamp to valid range (0-63)
    tile_x = math.max(0, math.min(63, tile_x))
    tile_y = math.max(0, math.min(63, tile_y))
    return tile_x, tile_y
end

--- Classify an edge based on neighbor data
-- @param nei Neighbor value from poly.neis[i]
-- @return EDGE_TYPE constant
local function classify_edge(nei)
    if not nei or nei == 0 then
        return EDGE_TYPE.WALL
    elseif nei >= DT_EXT_LINK then
        return EDGE_TYPE.EXTERNAL
    else
        return EDGE_TYPE.INTERNAL
    end
end

--- Get edge color based on edge type
local function get_edge_color(edge_type)
    if edge_type == EDGE_TYPE.WALL then
        return CONFIG.wall_edge_color
    elseif edge_type == EDGE_TYPE.EXTERNAL then
        return CONFIG.external_edge_color
    else
        return CONFIG.internal_edge_color
    end
end

--- Get edge thickness based on edge type
local function get_edge_thickness(edge_type)
    if edge_type == EDGE_TYPE.WALL then
        return CONFIG.wall_edge_thickness
    else
        return CONFIG.edge_thickness
    end
end

--- Check if a point is within draw range
local function in_range(px, py, pz, player_pos)
    local dx = px - player_pos.x
    local dy = py - player_pos.y
    local dz = pz - player_pos.z
    local dist_sq = dx*dx + dy*dy + dz*dz
    return dist_sq <= (CONFIG.draw_range * CONFIG.draw_range)
end

-- ===========================================
-- WIREFRAME DATA STRUCTURE
-- ===========================================

--- Wireframe edge representation
-- Each edge contains:
--   v1, v2: world-space vertex positions {x, y, z}
--   edge_type: EDGE_TYPE constant
--   poly_idx: source polygon index

--- Build wireframe edge list from a single polygon (OPTIMIZED: pre-compute midpoints)
-- @param poly Polygon object with worldVerts, neis, vertCount
-- @param poly_idx Polygon index in tile
-- @return array of wireframe edges
local function build_wireframe_from_polygon(poly, poly_idx)
    local edges = {}
    
    if not poly or not poly.worldVerts or not poly.vertCount then
        return edges
    end
    
    local vc = poly.vertCount
    local verts = poly.worldVerts
    local neis = poly.neis or {}
    
    for i = 1, vc do
        local v1 = verts[i]
        local v2 = verts[(i % vc) + 1]
        
        if v1 and v2 then
            local nei = neis[i] or 0
            local edge_type = classify_edge(nei)
            
            -- Pre-compute midpoint for faster range checks
            local mx = (v1.x + v2.x) * 0.5
            local my = (v1.y + v2.y) * 0.5
            local mz = (v1.z + v2.z) * 0.5
            
            edges[#edges + 1] = {
                v1 = {x = v1.x, y = v1.y, z = v1.z},
                v2 = {x = v2.x, y = v2.y, z = v2.z},
                mx = mx, my = my, mz = mz,  -- Pre-computed midpoint
                edge_type = edge_type,
                poly_idx = poly_idx,
                nei_value = nei,
            }
        end
    end
    
    return edges
end

--- Build wireframe from all polygons in a tile
-- Iterates through each polygon, extracts worldVerts, and constructs edges
-- @param tile Tile data with polygons array
-- @return wireframe data {edges = {...}, poly_count = N, edge_count = M}
function Wireframe.BuildWireframeFromPolygons(tile)
    if not tile or not tile.polygons then
        return {edges = {}, poly_count = 0, edge_count = 0}
    end
    
    local all_edges = {}
    local poly_count = 0
    local wall_count = 0
    local internal_count = 0
    local external_count = 0
    
    for poly_idx, poly in ipairs(tile.polygons) do
        local poly_edges = build_wireframe_from_polygon(poly, poly_idx)
        
        for _, edge in ipairs(poly_edges) do
            table.insert(all_edges, edge)
            
            -- Count edge types
            if edge.edge_type == EDGE_TYPE.WALL then
                wall_count = wall_count + 1
            elseif edge.edge_type == EDGE_TYPE.INTERNAL then
                internal_count = internal_count + 1
            elseif edge.edge_type == EDGE_TYPE.EXTERNAL then
                external_count = external_count + 1
            end
        end
        
        poly_count = poly_count + 1
    end
    
    return {
        edges = all_edges,
        poly_count = poly_count,
        edge_count = #all_edges,
        wall_count = wall_count,
        internal_count = internal_count,
        external_count = external_count,
        tile_x = tile.tileX,
        tile_y = tile.tileY,
    }
end

-- ===========================================
-- RENDERING FUNCTIONS
-- ===========================================

-- Initialize temp vectors on first use
local function ensure_temp_vectors()
    if not temp_vec3_1 then
        temp_vec3_1 = vec3.new(0, 0, 0)
        temp_vec3_2 = vec3.new(0, 0, 0)
    end
end

--- Render a single wireframe edge using 2D screen-space rendering
-- @param edge Wireframe edge {v1, v2, edge_type}
-- @param ho Height offset
-- @return true if edge was drawn
local function render_edge_2d(edge, ho)
    ensure_temp_vectors()
    -- Reuse temp vectors instead of allocating new ones
    temp_vec3_1.x = edge.v1.x
    temp_vec3_1.y = edge.v1.y
    temp_vec3_1.z = edge.v1.z + ho
    temp_vec3_2.x = edge.v2.x
    temp_vec3_2.y = edge.v2.y
    temp_vec3_2.z = edge.v2.z + ho
    
    -- Convert to screen space
    local s1 = core.graphics.w2s(temp_vec3_1)
    local s2 = core.graphics.w2s(temp_vec3_2)
    
    if s1 and s2 then
        local edge_color = get_edge_color(edge.edge_type)
        local thickness = get_edge_thickness(edge.edge_type)
        core.graphics.line_2d(s1, s2, edge_color, thickness)
        return true
    end
    
    return false
end

--- Render a single wireframe edge using 3D world-space rendering (OPTIMIZED)
-- @param edge Wireframe edge {v1, v2, edge_type}
-- @param ho Height offset
-- @return true if edge was drawn
local function render_edge_3d(edge, ho)
    ensure_temp_vectors()
    -- Reuse temp vectors instead of allocating new ones
    temp_vec3_1.x = edge.v1.x
    temp_vec3_1.y = edge.v1.y
    temp_vec3_1.z = edge.v1.z + ho
    temp_vec3_2.x = edge.v2.x
    temp_vec3_2.y = edge.v2.y
    temp_vec3_2.z = edge.v2.z + ho
    
    local edge_color = get_edge_color(edge.edge_type)
    local thickness = get_edge_thickness(edge.edge_type)
    
    core.graphics.line_3d(temp_vec3_1, temp_vec3_2, edge_color, thickness)
    return true
end

--- Render wireframe edges for a tile (OPTIMIZED: pre-computed midpoints, reduced allocations)
-- @param wireframe Wireframe data from BuildWireframeFromPolygons
-- @param player_pos Player position for range checking
-- @return stats {edges_drawn, edges_culled}
local function render_wireframe_edges(wireframe, player_pos)
    if not wireframe or not wireframe.edges then
        return {edges_drawn = 0, edges_culled = 0}
    end
    
    local ho = CONFIG.height_offset
    local drawn = 0
    local culled = 0
    local range_sq = CONFIG.draw_range * CONFIG.draw_range
    local px, py, pz = player_pos.x, player_pos.y, player_pos.z
    local walls_only = CONFIG.draw_walls_only
    local use_2d = CONFIG.use_2d_rendering
    local edges = wireframe.edges
    local edge_count = #edges
    
    for i = 1, edge_count do
        local edge = edges[i]
        
        -- Skip internal edges if walls_only mode
        if walls_only and edge.edge_type ~= EDGE_TYPE.WALL then
            goto continue
        end
        
        -- Range check using pre-computed midpoint if available, or calculate inline
        local mx, my, mz
        if edge.mx then
            mx, my, mz = edge.mx, edge.my, edge.mz
        else
            mx = (edge.v1.x + edge.v2.x) * 0.5
            my = (edge.v1.y + edge.v2.y) * 0.5
            mz = (edge.v1.z + edge.v2.z) * 0.5
        end
        
        -- Inline distance check (avoid function call overhead)
        local dx = mx - px
        local dy = my - py
        local dz = mz - pz
        local dist_sq = dx*dx + dy*dy + dz*dz
        
        if dist_sq <= range_sq then
            local success
            if use_2d then
                success = render_edge_2d(edge, ho)
            else
                success = render_edge_3d(edge, ho)
            end
            
            if success then
                drawn = drawn + 1
            else
                culled = culled + 1
            end
        else
            culled = culled + 1
        end
        
        ::continue::
    end
    
    return {edges_drawn = drawn, edges_culled = culled}
end

--- Render filled polygons for a tile
-- @param tile Tile data with polygons
-- @param player_pos Player position for range checking
-- @return number of polygons drawn
local function render_filled_polygons(tile, player_pos)
    if not tile or not tile.polygons or not CONFIG.draw_filled then
        return 0
    end
    
    local drawn = 0
    
    for _, poly in ipairs(tile.polygons) do
        if poly.center and in_range(poly.center.x, poly.center.y, poly.center.z, player_pos) then
            local result = DrawPolygon.draw_polygon(poly, {
                draw_filled = true,
                draw_outline = false,  -- We handle edges separately
                fill_color = CONFIG.fill_color,
            })
            if result.triangles > 0 then
                drawn = drawn + 1
            end
        end
    end
    
    return drawn
end

--- Render penalty zones for a tile's wall edges
-- @param tile Tile data with polygons
-- @param player_pos Player position for range checking
-- @return table {zone1_total, zone2_total}
local function render_penalty_zones(tile, player_pos)
    if not tile or not tile.polygons or not CONFIG.draw_penalty_zones then
        return {zone1_total = 0, zone2_total = 0}
    end
    
    local zone1_total = 0
    local zone2_total = 0
    
    for _, poly in ipairs(tile.polygons) do
        if poly.center and in_range(poly.center.x, poly.center.y, poly.center.z, player_pos) then
            local result = DrawPolygon.draw_penalty_zones(poly)
            zone1_total = zone1_total + result.zone1_drawn
            zone2_total = zone2_total + result.zone2_drawn
        end
    end
    
    return {zone1_total = zone1_total, zone2_total = zone2_total}
end

--- Render polygon center points
-- @param tile Tile data with polygons
-- @param player_pos Player position for range checking
-- @return number of centers drawn
local function render_polygon_centers(tile, player_pos)
    if not tile or not tile.polygons or not CONFIG.draw_centers then
        return 0
    end
    
    local drawn = 0
    local ho = CONFIG.height_offset
    
    for _, poly in ipairs(tile.polygons) do
        if poly.center and in_range(poly.center.x, poly.center.y, poly.center.z, player_pos) then
            local center = vec3.new(poly.center.x, poly.center.y, poly.center.z + ho)
            core.graphics.circle_3d_filled(center, CONFIG.center_radius, CONFIG.center_color)
            drawn = drawn + 1
        end
    end
    
    return drawn
end

-- ===========================================
-- TILE MANAGEMENT
-- ===========================================

--- Set tiles for rendering (OPTIMIZED: only rebuilds changed tiles)
-- @param map_id Map ID
-- @param tiles Table of tile_key -> tile_data
function Wireframe.set_tiles(map_id, tiles)
    if not tiles then
        cached_tiles[map_id] = nil
        return
    end
    
    -- Count tiles to detect changes
    local new_count = 0
    for _ in pairs(tiles) do
        new_count = new_count + 1
    end
    
    local old_count = last_tile_count[map_id] or 0
    
    -- Only process if tile count changed (new tiles loaded)
    if new_count == old_count and cached_tiles[map_id] then
        -- Check if any tiles are actually different
        local changed = false
        for key, tile in pairs(tiles) do
            if not cached_tiles[map_id][key] then
                changed = true
                break
            end
        end
        if not changed then
            return  -- No changes, skip rebuild
        end
    end
    
    last_tile_count[map_id] = new_count
    cached_tiles[map_id] = tiles
    
    -- Only rebuild wireframe for NEW tiles (not already in cache)
    for key, tile in pairs(tiles) do
        if not wireframe_cache[key] then
            wireframe_cache[key] = Wireframe.BuildWireframeFromPolygons(tile)
        end
    end
end

--- Add a single tile (OPTIMIZED: only builds wireframe once)
-- @param map_id Map ID
-- @param tile_key Tile key string
-- @param tile Tile data
function Wireframe.add_tile(map_id, tile_key, tile)
    if not cached_tiles[map_id] then
        cached_tiles[map_id] = {}
    end
    
    -- Only rebuild if tile is new or marked dirty
    if not cached_tiles[map_id][tile_key] or tiles_dirty[tile_key] then
        cached_tiles[map_id][tile_key] = tile
        wireframe_cache[tile_key] = Wireframe.BuildWireframeFromPolygons(tile)
        tiles_dirty[tile_key] = nil
        last_tile_count[map_id] = (last_tile_count[map_id] or 0) + 1
    end
end

--- Mark a tile as dirty (needs wireframe rebuild)
-- @param tile_key Tile key string
function Wireframe.mark_dirty(tile_key)
    tiles_dirty[tile_key] = true
end

--- Get cached wireframe for a tile
-- @param tile_key Tile key string
-- @return wireframe data or nil
function Wireframe.get_wireframe(tile_key)
    return wireframe_cache[tile_key]
end

-- ===========================================
-- MAIN RENDER FUNCTION
-- ===========================================

--- Main render function (call from on_render callback)
function Wireframe.render()
    if not CONFIG.enabled then
        return
    end
    
    local player = core.object_manager.get_local_player()
    if not player then
        return
    end
    
    local player_pos = player:get_position()
    if not player_pos then
        return
    end
    
    local map_id = core.get_instance_id()
    if not map_id then
        return
    end
    
    local tiles = cached_tiles[map_id]
    if not tiles then
        return
    end
    
    local total_edges_drawn = 0
    local total_polys_filled = 0
    local total_centers_drawn = 0
    local total_penalty_zones = 0
    
    for key, tile in pairs(tiles) do
        -- Render filled polygons first (so edges draw on top)
        if CONFIG.draw_filled then
            total_polys_filled = total_polys_filled + render_filled_polygons(tile, player_pos)
        end
        
        -- Render penalty zones (after fill, before edges)
        if CONFIG.draw_penalty_zones then
            local zone_stats = render_penalty_zones(tile, player_pos)
            total_penalty_zones = total_penalty_zones + zone_stats.zone1_total + zone_stats.zone2_total
        end
        
        -- Render wireframe edges
        if CONFIG.draw_edges then
            local wireframe = wireframe_cache[key]
            if wireframe then
                local stats = render_wireframe_edges(wireframe, player_pos)
                total_edges_drawn = total_edges_drawn + stats.edges_drawn
            end
        end
        
        -- Render center points
        if CONFIG.draw_centers then
            total_centers_drawn = total_centers_drawn + render_polygon_centers(tile, player_pos)
        end
    end
end

-- ===========================================
-- CONFIGURATION API
-- ===========================================

--- Enable/disable wireframe rendering
function Wireframe.set_enabled(enabled)
    if CONFIG.enabled ~= enabled then
        CONFIG.enabled = enabled
        if enabled then
            Debug.log("[Wireframe] Enabled")
        else
            Debug.log("[Wireframe] Disabled")
        end
    end
end

function Wireframe.is_enabled()
    return CONFIG.enabled
end

--- Set draw range
function Wireframe.set_range(range)
    CONFIG.draw_range = range
end

function Wireframe.get_range()
    return CONFIG.draw_range
end

--- Set draw options
function Wireframe.set_draw_filled(enabled)
    CONFIG.draw_filled = enabled
end

function Wireframe.set_draw_edges(enabled)
    CONFIG.draw_edges = enabled
end

function Wireframe.set_draw_walls_only(enabled)
    CONFIG.draw_walls_only = enabled
end

function Wireframe.set_draw_centers(enabled)
    CONFIG.draw_centers = enabled
end

function Wireframe.set_draw_penalty_zones(enabled)
    CONFIG.draw_penalty_zones = enabled
    -- Also update DrawPolygon module
    DrawPolygon.set_penalty_zones_enabled(enabled)
end

function Wireframe.get_draw_penalty_zones()
    return CONFIG.draw_penalty_zones
end

--- Set colors
function Wireframe.set_fill_color(r, g, b, a)
    CONFIG.fill_color = color.new(r, g, b, a)
end

function Wireframe.set_wall_color(r, g, b, a)
    CONFIG.wall_edge_color = color.new(r, g, b, a)
end

function Wireframe.set_internal_color(r, g, b, a)
    CONFIG.internal_edge_color = color.new(r, g, b, a)
end

function Wireframe.set_external_color(r, g, b, a)
    CONFIG.external_edge_color = color.new(r, g, b, a)
end

--- Set rendering mode
function Wireframe.set_2d_rendering(enabled)
    CONFIG.use_2d_rendering = enabled
end

--- Get current configuration
function Wireframe.get_config()
    return CONFIG
end

--- Clear all cached data
function Wireframe.clear_cache()
    cached_tiles = {}
    wireframe_cache = {}
    tiles_dirty = {}
    last_tile_count = {}
    Debug.log("[Wireframe] Cache cleared")
end

-- ===========================================
-- EDGE TYPE CONSTANTS (exported)
-- ===========================================
Wireframe.EDGE_TYPE = EDGE_TYPE

return Wireframe