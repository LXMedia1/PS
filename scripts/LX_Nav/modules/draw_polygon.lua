-- LX_Nav DrawPolygon Module
-- Renders arbitrary convex and concave polygons using core.graphics primitives
-- Supports filled rendering (triangle fan decomposition) and outline rendering
-- Handles edge classification using neighbor data (walls vs internal edges)
-- Includes wall proximity penalty zone visualization

local color = require("common/color")
local vec3 = require("common/geometry/vector_3")

local DrawPolygon = {}

-- ===========================================
-- CONFIGURATION
-- ===========================================

local CONFIG = {
    -- Fill colors
    fill_color = color.new(0, 200, 100, 60),           -- Semi-transparent green fill

    -- Edge colors
    internal_edge_color = color.new(0, 255, 100, 200), -- Green for internal edges
    wall_edge_color = color.new(255, 100, 0, 220),     -- Orange for wall/boundary edges
    external_edge_color = color.new(255, 200, 0, 200), -- Yellow for cross-tile edges

    -- Edge thickness
    edge_thickness = 1.5,
    wall_edge_thickness = 2.0,

    -- Height offset to prevent z-fighting
    height_offset = 0.1,

    -- Wall proximity penalty zones
    penalty_zones = {
        enabled = false,
        -- Zone 1: 0-1.5 yards from wall (high penalty)
        zone1_distance = 1.5,       -- Distance in yards
        zone1_penalty = 8.0,        -- Pathfinding penalty multiplier
        zone1_color = color.new(255, 50, 50, 100),   -- Red, semi-transparent

        -- Zone 2: 1.5-3.0 yards from wall (medium penalty)
        zone2_distance = 3.0,       -- Distance in yards
        zone2_penalty = 5.0,        -- Pathfinding penalty multiplier
        zone2_color = color.new(255, 165, 0, 80),    -- Orange, semi-transparent

        -- Zone 3: 3.0-4.5 yards from wall (low penalty)
        zone3_distance = 4.5,       -- Distance in yards
        zone3_penalty = 2.0,        -- Pathfinding penalty multiplier
        zone3_color = color.new(255, 255, 0, 60),    -- Yellow, semi-transparent
    },
}

-- Edge type constants
local EDGE_TYPE = {
    WALL = 0,           -- No neighbor (boundary/wall)
    INTERNAL = 1,       -- Internal neighbor (same tile)
    EXTERNAL = 2,       -- External neighbor (cross-tile, neis >= 0x8000)
}

local DT_EXT_LINK = 0x8000  -- External link flag

-- ===========================================
-- UTILITY FUNCTIONS
-- ===========================================

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

-- Pre-allocated vec3 objects for rendering (avoid per-frame allocations)
local temp_p0 = nil
local temp_p1 = nil
local temp_p2 = nil

local function ensure_temp_vectors()
    if not temp_p0 then
        temp_p0 = vec3.new(0, 0, 0)
        temp_p1 = vec3.new(0, 0, 0)
        temp_p2 = vec3.new(0, 0, 0)
    end
end

--- Draw a filled polygon using optimized rendering
-- For 3-vertex polygons: single triangle (1 draw call)
-- For 4-vertex polygons: 2 triangles as a quad (2 draw calls)
-- For 5+ vertex polygons: triangle fan from first vertex (n-2 draw calls)
-- @param world_verts Array of world-space vertices {x, y, z}
-- @param fill_color Color for fill (optional, uses CONFIG default)
-- @return number Number of triangles drawn
function DrawPolygon.draw_filled(world_verts, fill_color)
    if not world_verts or #world_verts < 3 then
        return 0
    end

    ensure_temp_vectors()
    local col = fill_color or CONFIG.fill_color
    local ho = CONFIG.height_offset
    local n = #world_verts
    local drawn = 0

    -- Single triangle - most efficient case
    if n == 3 then
        local v0, v1, v2 = world_verts[1], world_verts[2], world_verts[3]
        if v0 and v1 and v2 then
            temp_p0.x, temp_p0.y, temp_p0.z = v0.x, v0.y, v0.z + ho
            temp_p1.x, temp_p1.y, temp_p1.z = v1.x, v1.y, v1.z + ho
            temp_p2.x, temp_p2.y, temp_p2.z = v2.x, v2.y, v2.z + ho
            core.graphics.triangle_3d_filled(temp_p0, temp_p1, temp_p2, col)
            return 1
        end
        return 0
    end

    -- Quad (4 vertices) - draw as 2 triangles (simulates filled rectangle)
    -- Triangle 1: v0, v1, v2
    -- Triangle 2: v0, v2, v3
    if n == 4 then
        local v0, v1, v2, v3 = world_verts[1], world_verts[2], world_verts[3], world_verts[4]
        if v0 and v1 and v2 and v3 then
            -- First triangle
            temp_p0.x, temp_p0.y, temp_p0.z = v0.x, v0.y, v0.z + ho
            temp_p1.x, temp_p1.y, temp_p1.z = v1.x, v1.y, v1.z + ho
            temp_p2.x, temp_p2.y, temp_p2.z = v2.x, v2.y, v2.z + ho
            core.graphics.triangle_3d_filled(temp_p0, temp_p1, temp_p2, col)

            -- Second triangle (reuse temp_p0 for v0)
            temp_p1.x, temp_p1.y, temp_p1.z = v2.x, v2.y, v2.z + ho
            temp_p2.x, temp_p2.y, temp_p2.z = v3.x, v3.y, v3.z + ho
            core.graphics.triangle_3d_filled(temp_p0, temp_p1, temp_p2, col)
            return 2
        end
        return 0
    end

    -- 5+ vertices: Use triangle fan from first vertex
    -- This is optimal for convex polygons (n-2 triangles)
    local v0 = world_verts[1]
    if not v0 then return 0 end

    temp_p0.x, temp_p0.y, temp_p0.z = v0.x, v0.y, v0.z + ho

    for i = 2, n - 1 do
        local v1 = world_verts[i]
        local v2 = world_verts[i + 1]

        if v1 and v2 then
            temp_p1.x, temp_p1.y, temp_p1.z = v1.x, v1.y, v1.z + ho
            temp_p2.x, temp_p2.y, temp_p2.z = v2.x, v2.y, v2.z + ho
            core.graphics.triangle_3d_filled(temp_p0, temp_p1, temp_p2, col)
            drawn = drawn + 1
        end
    end

    return drawn
end

-- ===========================================
-- WALL PROXIMITY PENALTY ZONE FUNCTIONS
-- ===========================================

--- Compute the 2D perpendicular (inward normal) for an edge
-- @param v1 Start vertex {x, y, z}
-- @param v2 End vertex {x, y, z}
-- @param center Polygon center {x, y, z} to determine inward direction
-- @return normalized inward normal {x, y} (2D)
local function compute_inward_normal(v1, v2, center)
    -- Edge direction (2D)
    local dx = v2.x - v1.x
    local dy = v2.y - v1.y

    -- Two possible perpendiculars
    local n1x, n1y = -dy, dx
    local n2x, n2y = dy, -dx

    -- Normalize
    local len1 = math.sqrt(n1x*n1x + n1y*n1y)
    if len1 > 0.0001 then
        n1x, n1y = n1x / len1, n1y / len1
        n2x, n2y = n2x / len1, n2y / len1
    else
        return {x = 0, y = 0}
    end

    -- Choose the one pointing toward center (inward)
    local mid_x = (v1.x + v2.x) * 0.5
    local mid_y = (v1.y + v2.y) * 0.5
    local to_center_x = center.x - mid_x
    local to_center_y = center.y - mid_y

    local dot1 = n1x * to_center_x + n1y * to_center_y

    if dot1 > 0 then
        return {x = n1x, y = n1y}
    else
        return {x = n2x, y = n2y}
    end
end

--- Clip a polygon against a half-plane defined by an edge
-- Uses Sutherland-Hodgman algorithm
-- @param poly Array of {x, y} points
-- @param edge_p1 Edge start point
-- @param edge_p2 Edge end point
-- @param inward_normal Inward normal of the clipping edge
-- @return Clipped polygon vertices
local function clip_polygon_by_edge(poly, edge_p1, edge_p2, inward_normal)
    if #poly < 3 then return {} end

    local output = {}
    local n = #poly

    -- Check which side of the line a point is on
    -- Positive = inside (same side as inward normal)
    local function signed_distance(p)
        local dx = p.x - edge_p1.x
        local dy = p.y - edge_p1.y
        return dx * inward_normal.x + dy * inward_normal.y
    end

    local s = poly[n]
    local s_dist = signed_distance(s)

    for i = 1, n do
        local e = poly[i]
        local e_dist = signed_distance(e)

        if e_dist >= 0 then
            -- e is inside
            if s_dist < 0 then
                -- s is outside, add intersection
                local t = s_dist / (s_dist - e_dist)
                output[#output + 1] = {
                    x = s.x + t * (e.x - s.x),
                    y = s.y + t * (e.y - s.y)
                }
            end
            output[#output + 1] = e
        elseif s_dist >= 0 then
            -- e is outside, s is inside, add intersection
            local t = s_dist / (s_dist - e_dist)
            output[#output + 1] = {
                x = s.x + t * (e.x - s.x),
                y = s.y + t * (e.y - s.y)
            }
        end

        s = e
        s_dist = e_dist
    end

    return output
end

--- Generate penalty zone geometry for a wall edge
-- Creates a trapezoidal region extending inward from the wall edge
-- @param v1 Wall edge start vertex {x, y, z}
-- @param v2 Wall edge end vertex {x, y, z}
-- @param distance Inset distance (zone width)
-- @param inner_distance Start distance (0 for zone1, zone1_dist for zone2)
-- @param center Polygon center for inward direction
-- @param poly_verts Original polygon vertices for clipping
-- @return Array of vertices forming the penalty zone quad, or nil
local function generate_wall_zone_quad(v1, v2, distance, inner_distance, center, poly_verts)
    local normal = compute_inward_normal(v1, v2, center)
    if normal.x == 0 and normal.y == 0 then
        return nil
    end

    -- Create quad vertices (trapezoid from wall edge inward)
    -- Outer edge (at wall or inner_distance)
    local o1 = {
        x = v1.x + normal.x * inner_distance,
        y = v1.y + normal.y * inner_distance,
        z = v1.z
    }
    local o2 = {
        x = v2.x + normal.x * inner_distance,
        y = v2.y + normal.y * inner_distance,
        z = v2.z
    }

    -- Inner edge (at distance)
    local i1 = {
        x = v1.x + normal.x * distance,
        y = v1.y + normal.y * distance,
        z = v1.z
    }
    local i2 = {
        x = v2.x + normal.x * distance,
        y = v2.y + normal.y * distance,
        z = v2.z
    }

    -- Create polygon for clipping (2D)
    local zone_poly = {
        {x = o1.x, y = o1.y},
        {x = o2.x, y = o2.y},
        {x = i2.x, y = i2.y},
        {x = i1.x, y = i1.y}
    }

    -- Clip against parent polygon
    local clipped = zone_poly
    local n = #poly_verts

    for i = 1, n do
        local pv1 = poly_verts[i]
        local pv2 = poly_verts[(i % n) + 1]
        local edge_normal = compute_inward_normal(pv1, pv2, center)

        clipped = clip_polygon_by_edge(clipped, pv1, pv2, edge_normal)
        if #clipped < 3 then
            return nil
        end
    end

    -- Convert back to 3D vertices with interpolated Z
    local avg_z = (v1.z + v2.z) * 0.5
    local result = {}
    for _, p in ipairs(clipped) do
        result[#result + 1] = {x = p.x, y = p.y, z = avg_z}
    end

    return result
end

--- Draw penalty zones for a polygon's wall edges (simple rectangular bands)
-- @param poly Polygon object with worldVerts, neis, vertCount, center
-- @param options Table with zone settings (optional, uses CONFIG defaults)
-- @return table {zone1_drawn, zone2_drawn, zone3_drawn} counts
function DrawPolygon.draw_penalty_zones(poly, options)
    if not CONFIG.penalty_zones.enabled then
        return {zone1_drawn = 0, zone2_drawn = 0, zone3_drawn = 0}
    end

    options = options or {}

    local verts = poly.worldVerts
    local neis = poly.neis
    local vc = poly.vertCount or #verts
    local center = poly.center

    if not verts or vc < 3 then
        return {zone1_drawn = 0, zone2_drawn = 0, zone3_drawn = 0}
    end

    if not center then
        return {zone1_drawn = 0, zone2_drawn = 0, zone3_drawn = 0}
    end

    -- Build vertex list
    local world_verts = {}
    for i = 1, vc do
        world_verts[i] = verts[i]
    end

    local zone1_count = 0
    local zone2_count = 0
    local zone3_count = 0

    local zone1_dist = options.zone1_distance or CONFIG.penalty_zones.zone1_distance
    local zone2_dist = options.zone2_distance or CONFIG.penalty_zones.zone2_distance
    local zone3_dist = options.zone3_distance or CONFIG.penalty_zones.zone3_distance
    local zone1_color = options.zone1_color or CONFIG.penalty_zones.zone1_color
    local zone2_color = options.zone2_color or CONFIG.penalty_zones.zone2_color
    local zone3_color = options.zone3_color or CONFIG.penalty_zones.zone3_color

    local ho = CONFIG.height_offset

    -- Pre-allocate temp vectors
    ensure_temp_vectors()

    -- Iterate through edges, find wall edges (neis == 0)
    for i = 1, vc do
        local nei = neis and neis[i] or 0

        if not nei or nei == 0 then  -- Wall edge
            local v1 = world_verts[i]
            local v2 = world_verts[(i % vc) + 1]

            if v1 and v2 then
                -- Calculate inward normal
                local normal = compute_inward_normal(v1, v2, center)
                if normal.x ~= 0 or normal.y ~= 0 then
                    -- Draw Zone 3 first (farthest from wall, 2-3 yards)
                    local z3_o1_x = v1.x + normal.x * zone2_dist
                    local z3_o1_y = v1.y + normal.y * zone2_dist
                    local z3_o2_x = v2.x + normal.x * zone2_dist
                    local z3_o2_y = v2.y + normal.y * zone2_dist
                    local z3_i1_x = v1.x + normal.x * zone3_dist
                    local z3_i1_y = v1.y + normal.y * zone3_dist
                    local z3_i2_x = v2.x + normal.x * zone3_dist
                    local z3_i2_y = v2.y + normal.y * zone3_dist

                    -- Zone 3: outer edge at zone2_dist, inner edge at zone3_dist
                    local p0_z3 = vec3.new(z3_o1_x, z3_o1_y, v1.z + ho)  -- Outer, vertex 1
                    local p1_z3 = vec3.new(z3_o2_x, z3_o2_y, v2.z + ho)  -- Outer, vertex 2
                    local p2_z3 = vec3.new(z3_i2_x, z3_i2_y, v2.z + ho)  -- Inner, vertex 2
                    local p3_z3 = vec3.new(z3_i1_x, z3_i1_y, v1.z + ho)  -- Inner, vertex 1
                    core.graphics.triangle_3d_filled(p0_z3, p1_z3, p2_z3, zone3_color)
                    core.graphics.triangle_3d_filled(p0_z3, p2_z3, p3_z3, zone3_color)
                    zone3_count = zone3_count + 1

                    -- Draw Zone 2 (middle layer, 1-2 yards)
                    local z2_o1_x = v1.x + normal.x * zone1_dist
                    local z2_o1_y = v1.y + normal.y * zone1_dist
                    local z2_o2_x = v2.x + normal.x * zone1_dist
                    local z2_o2_y = v2.y + normal.y * zone1_dist
                    local z2_i1_x = v1.x + normal.x * zone2_dist
                    local z2_i1_y = v1.y + normal.y * zone2_dist
                    local z2_i2_x = v2.x + normal.x * zone2_dist
                    local z2_i2_y = v2.y + normal.y * zone2_dist

                    local p0_z2 = vec3.new(z2_o1_x, z2_o1_y, v1.z + ho)
                    local p1_z2 = vec3.new(z2_o2_x, z2_o2_y, v2.z + ho)
                    local p2_z2 = vec3.new(z2_i2_x, z2_i2_y, v2.z + ho)
                    local p3_z2 = vec3.new(z2_i1_x, z2_i1_y, v1.z + ho)
                    core.graphics.triangle_3d_filled(p0_z2, p1_z2, p2_z2, zone2_color)
                    core.graphics.triangle_3d_filled(p0_z2, p2_z2, p3_z2, zone2_color)
                    zone2_count = zone2_count + 1

                    -- Draw Zone 1 on top (closest to wall, 0-1 yard)
                    local z1_i1_x = v1.x + normal.x * zone1_dist
                    local z1_i1_y = v1.y + normal.y * zone1_dist
                    local z1_i2_x = v2.x + normal.x * zone1_dist
                    local z1_i2_y = v2.y + normal.y * zone1_dist

                    local p0_z1 = vec3.new(v1.x, v1.y, v1.z + ho)
                    local p1_z1 = vec3.new(v2.x, v2.y, v2.z + ho)
                    local p2_z1 = vec3.new(z1_i2_x, z1_i2_y, v2.z + ho)
                    local p3_z1 = vec3.new(z1_i1_x, z1_i1_y, v1.z + ho)
                    core.graphics.triangle_3d_filled(p0_z1, p1_z1, p2_z1, zone1_color)
                    core.graphics.triangle_3d_filled(p0_z1, p2_z1, p3_z1, zone1_color)
                    zone1_count = zone1_count + 1
                end
            end
        end
    end

    return {zone1_drawn = zone1_count, zone2_drawn = zone2_count, zone3_drawn = zone3_count}
end

-- ===========================================
-- CONFIGURATION FUNCTIONS
-- ===========================================

--- Enable/disable penalty zones
function DrawPolygon.set_penalty_zones_enabled(enabled)
    CONFIG.penalty_zones.enabled = enabled
end

--- Check if penalty zones are enabled
function DrawPolygon.get_penalty_zones_enabled()
    return CONFIG.penalty_zones.enabled
end

--- Set penalty zone distances
function DrawPolygon.set_penalty_zone_distances(zone1_dist, zone2_dist, zone3_dist)
    CONFIG.penalty_zones.zone1_distance = zone1_dist
    CONFIG.penalty_zones.zone2_distance = zone2_dist
    CONFIG.penalty_zones.zone3_distance = zone3_dist or (zone2_dist + 1.0)
end

--- Set penalty zone colors
function DrawPolygon.set_penalty_zone_colors(zone1_r, zone1_g, zone1_b, zone1_a, zone2_r, zone2_g, zone2_b, zone2_a, zone3_r, zone3_g, zone3_b, zone3_a)
    CONFIG.penalty_zones.zone1_color = color.new(zone1_r, zone1_g, zone1_b, zone1_a)
    CONFIG.penalty_zones.zone2_color = color.new(zone2_r, zone2_g, zone2_b, zone2_a)
    if zone3_r then
        CONFIG.penalty_zones.zone3_color = color.new(zone3_r, zone3_g, zone3_b, zone3_a)
    end
end

--- Set penalty values
function DrawPolygon.set_penalty_values(zone1_penalty, zone2_penalty, zone3_penalty)
    CONFIG.penalty_zones.zone1_penalty = zone1_penalty
    CONFIG.penalty_zones.zone2_penalty = zone2_penalty
    CONFIG.penalty_zones.zone3_penalty = zone3_penalty or 1.25
end

--- Get penalty zone configuration
function DrawPolygon.get_penalty_zone_config()
    return CONFIG.penalty_zones
end

-- ===========================================
-- EDGE TYPE CONSTANTS (exported)
-- ===========================================
DrawPolygon.EDGE_TYPE = EDGE_TYPE

return DrawPolygon
