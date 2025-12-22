-- LX_Nav2 DrawPolygon Module
-- Renders arbitrary convex and concave polygons using core.graphics primitives
-- Supports filled rendering (triangle fan decomposition) and outline rendering
-- Handles edge classification using neighbor data (walls vs internal edges)
-- Includes wall proximity penalty zone visualization

local color = require("common/color")
local vec3 = require("common/geometry/vector_3")
local vec2 = require("common/geometry/vector_2")

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
        -- Zone 1: 0-1 yards from wall (high penalty)
        zone1_distance = 1.0,       -- Distance in yards
        zone1_penalty = 2.5,        -- Pathfinding penalty multiplier
        zone1_color = color.new(255, 50, 50, 100),   -- Red, semi-transparent
        
        -- Zone 2: 1-2 yards from wall (medium penalty)
        zone2_distance = 2.0,       -- Distance in yards
        zone2_penalty = 1.5,        -- Pathfinding penalty multiplier
        zone2_color = color.new(255, 165, 0, 80),    -- Orange, semi-transparent
        
        -- Zone 3: 2-3 yards from wall (low penalty)
        zone3_distance = 3.0,       -- Distance in yards
        zone3_penalty = 1.25,       -- Pathfinding penalty multiplier
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

--- Get edge color based on edge type
-- @param edge_type EDGE_TYPE constant
-- @return color
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
-- @param edge_type EDGE_TYPE constant
-- @return thickness
local function get_edge_thickness(edge_type)
    if edge_type == EDGE_TYPE.WALL then
        return CONFIG.wall_edge_thickness
    else
        return CONFIG.edge_thickness
    end
end

--- Check if a polygon is convex
-- Uses cross product to check if all vertices turn in the same direction
-- @param verts Array of {x, y, z} vertices
-- @return boolean true if convex
local function is_convex(verts)
    local n = #verts
    if n < 3 then return false end
    
    local sign = 0
    for i = 1, n do
        local v0 = verts[i]
        local v1 = verts[(i % n) + 1]
        local v2 = verts[((i + 1) % n) + 1]
        
        -- 2D cross product (ignore Z for convexity check)
        local dx1 = v1.x - v0.x
        local dy1 = v1.y - v0.y
        local dx2 = v2.x - v1.x
        local dy2 = v2.y - v1.y
        
        local cross = dx1 * dy2 - dy1 * dx2
        
        if cross ~= 0 then
            if sign == 0 then
                sign = cross > 0 and 1 or -1
            elseif (cross > 0 and sign < 0) or (cross < 0 and sign > 0) then
                return false  -- Sign change means concave
            end
        end
    end
    
    return true
end

--- Check if a point is inside a triangle (2D, ignoring Z)
-- @param p Point to test {x, y}
-- @param v0, v1, v2 Triangle vertices
-- @return boolean
local function point_in_triangle(p, v0, v1, v2)
    local function sign(p1, p2, p3)
        return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
    end
    
    local d1 = sign(p, v0, v1)
    local d2 = sign(p, v1, v2)
    local d3 = sign(p, v2, v0)
    
    local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    
    return not (has_neg and has_pos)
end

--- Check if an ear is valid (no other vertices inside)
-- @param verts Array of vertices
-- @param i Index of ear vertex
-- @param prev_i Previous vertex index
-- @param next_i Next vertex index
-- @return boolean
local function is_ear(verts, indices, i, prev_i, next_i)
    local v0 = verts[indices[prev_i]]
    local v1 = verts[indices[i]]
    local v2 = verts[indices[next_i]]
    
    -- Check convexity (cross product > 0 for CCW)
    local dx1 = v1.x - v0.x
    local dy1 = v1.y - v0.y
    local dx2 = v2.x - v1.x
    local dy2 = v2.y - v1.y
    local cross = dx1 * dy2 - dy1 * dx2
    
    if cross <= 0 then
        return false  -- Reflex vertex, not an ear
    end
    
    -- Check that no other vertex is inside this triangle
    for j = 1, #indices do
        if j ~= prev_i and j ~= i and j ~= next_i then
            local p = verts[indices[j]]
            if point_in_triangle(p, v0, v1, v2) then
                return false
            end
        end
    end
    
    return true
end

-- ===========================================
-- TRIANGLE DECOMPOSITION
-- ===========================================

--- Decompose a convex polygon into triangles using fan method
-- @param verts Array of {x, y, z} vertices
-- @return Array of triangles, each {v0, v1, v2}
local function triangulate_fan(verts)
    local triangles = {}
    local n = #verts
    
    if n < 3 then return triangles end
    
    local v0 = verts[1]
    for i = 2, n - 1 do
        table.insert(triangles, {v0, verts[i], verts[i + 1]})
    end
    
    return triangles
end

--- Decompose a potentially concave polygon using ear clipping
-- @param verts Array of {x, y, z} vertices
-- @return Array of triangles, each {v0, v1, v2}
local function triangulate_ear_clip(verts)
    local triangles = {}
    local n = #verts
    
    if n < 3 then return triangles end
    if n == 3 then
        return {{verts[1], verts[2], verts[3]}}
    end
    
    -- Create index array
    local indices = {}
    for i = 1, n do
        indices[i] = i
    end
    
    -- Ear clipping loop
    local count = n
    local iterations = 0
    local max_iterations = n * n  -- Safety limit
    
    while count > 3 and iterations < max_iterations do
        iterations = iterations + 1
        local ear_found = false
        
        for i = 1, count do
            local prev_i = ((i - 2) % count) + 1
            local next_i = (i % count) + 1
            
            if is_ear(verts, indices, i, prev_i, next_i) then
                -- Add triangle
                table.insert(triangles, {
                    verts[indices[prev_i]],
                    verts[indices[i]],
                    verts[indices[next_i]]
                })
                
                -- Remove vertex from list
                table.remove(indices, i)
                count = count - 1
                ear_found = true
                break
            end
        end
        
        -- If no ear found, polygon may be degenerate
        if not ear_found then
            break
        end
    end
    
    -- Add final triangle
    if count == 3 then
        table.insert(triangles, {
            verts[indices[1]],
            verts[indices[2]],
            verts[indices[3]]
        })
    end
    
    return triangles
end

--- Decompose a polygon into triangles (auto-selects method)
-- @param verts Array of {x, y, z} vertices
-- @param force_ear_clip Force ear clipping even for convex polygons
-- @return Array of triangles, each {v0, v1, v2}
function DrawPolygon.triangulate(verts, force_ear_clip)
    if not verts or #verts < 3 then
        return {}
    end
    
    -- For small polygons or convex polygons, use fan method (faster)
    if not force_ear_clip and (#verts <= 4 or is_convex(verts)) then
        return triangulate_fan(verts)
    end
    
    -- For concave polygons, use ear clipping
    return triangulate_ear_clip(verts)
end

-- ===========================================
-- RENDERING FUNCTIONS
-- ===========================================

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

--- Draw a filled polygon using pre-computed triangulation (for concave polygons)
-- @param world_verts Array of world-space vertices {x, y, z}
-- @param triangles Pre-computed triangle indices from triangulate()
-- @param fill_color Color for fill (optional, uses CONFIG default)
-- @return number Number of triangles drawn
function DrawPolygon.draw_filled_triangulated(world_verts, triangles, fill_color)
    if not world_verts or not triangles or #triangles == 0 then
        return 0
    end
    
    ensure_temp_vectors()
    local col = fill_color or CONFIG.fill_color
    local ho = CONFIG.height_offset
    local drawn = 0
    
    for _, tri in ipairs(triangles) do
        local v0 = tri[1]
        local v1 = tri[2]
        local v2 = tri[3]
        
        if v0 and v1 and v2 then
            temp_p0.x, temp_p0.y, temp_p0.z = v0.x, v0.y, v0.z + ho
            temp_p1.x, temp_p1.y, temp_p1.z = v1.x, v1.y, v1.z + ho
            temp_p2.x, temp_p2.y, temp_p2.z = v2.x, v2.y, v2.z + ho
            core.graphics.triangle_3d_filled(temp_p0, temp_p1, temp_p2, col)
            drawn = drawn + 1
        end
    end
    
    return drawn
end

--- Draw polygon outline (edges between consecutive vertices)
-- @param world_verts Array of world-space vertices {x, y, z}
-- @param neis Neighbor array for edge classification (optional)
-- @param edge_color Color for all edges (optional, overrides classification)
-- @param thickness Line thickness (optional)
-- @return number Number of edges drawn
function DrawPolygon.draw_outline(world_verts, neis, edge_color, thickness)
    if not world_verts or #world_verts < 2 then
        return 0
    end
    
    local ho = CONFIG.height_offset
    local n = #world_verts
    local drawn = 0
    
    for i = 1, n do
        local v1 = world_verts[i]
        local v2 = world_verts[(i % n) + 1]
        
        if v1 and v2 then
            local p1 = vec3.new(v1.x, v1.y, v1.z + ho)
            local p2 = vec3.new(v2.x, v2.y, v2.z + ho)
            
            local col = edge_color
            local thick = thickness
            
            if not col and neis then
                local edge_type = classify_edge(neis[i])
                col = get_edge_color(edge_type)
                thick = thick or get_edge_thickness(edge_type)
            end
            
            col = col or CONFIG.internal_edge_color
            thick = thick or CONFIG.edge_thickness
            
            core.graphics.line_3d(p1, p2, col, thick)
            drawn = drawn + 1
        end
    end
    
    return drawn
end

--- Draw only wall edges (where neis[i] == 0)
-- @param world_verts Array of world-space vertices {x, y, z}
-- @param neis Neighbor array
-- @param wall_color Color for wall edges (optional)
-- @param thickness Line thickness (optional)
-- @return number Number of wall edges drawn
function DrawPolygon.draw_wall_edges(world_verts, neis, wall_color, thickness)
    if not world_verts or #world_verts < 2 or not neis then
        return 0
    end
    
    local ho = CONFIG.height_offset
    local n = #world_verts
    local drawn = 0
    local col = wall_color or CONFIG.wall_edge_color
    local thick = thickness or CONFIG.wall_edge_thickness
    
    for i = 1, n do
        local nei = neis[i]
        if not nei or nei == 0 then  -- Wall edge
            local v1 = world_verts[i]
            local v2 = world_verts[(i % n) + 1]
            
            if v1 and v2 then
                local p1 = vec3.new(v1.x, v1.y, v1.z + ho)
                local p2 = vec3.new(v2.x, v2.y, v2.z + ho)
                
                core.graphics.line_3d(p1, p2, col, thick)
                drawn = drawn + 1
            end
        end
    end
    
    return drawn
end

--- Draw a complete polygon (filled + outline with edge classification)
-- @param poly Polygon object with worldVerts, neis, and vertCount
-- @param options Table with optional settings:
--   - draw_filled: boolean (default true)
--   - draw_outline: boolean (default true)
--   - draw_walls_only: boolean (default false) - only draw wall edges
--   - fill_color: color
--   - wall_color: color
--   - internal_color: color
--   - external_color: color
-- @return table {triangles_drawn, edges_drawn}
function DrawPolygon.draw_polygon(poly, options)
    options = options or {}
    
    local verts = poly.worldVerts
    local neis = poly.neis
    local vc = poly.vertCount or #verts
    
    if not verts or vc < 3 then
        return {triangles = 0, edges = 0}
    end
    
    -- Trim to actual vertex count
    local world_verts = {}
    for i = 1, vc do
        world_verts[i] = verts[i]
    end
    
    local result = {triangles = 0, edges = 0}
    
    -- Draw filled
    if options.draw_filled ~= false then
        result.triangles = DrawPolygon.draw_filled(world_verts, options.fill_color)
    end
    
    -- Draw outline
    if options.draw_outline ~= false then
        if options.draw_walls_only then
            result.edges = DrawPolygon.draw_wall_edges(world_verts, neis, options.wall_color)
        else
            result.edges = DrawPolygon.draw_outline(world_verts, neis)
        end
    end
    
    return result
end

--- Draw polygon in 2D screen space (for minimap/UI)
-- @param world_verts Array of world-space vertices
-- @param fill_color Color for fill (optional)
-- @param outline_color Color for outline (optional)
-- @return boolean true if polygon is visible on screen
function DrawPolygon.draw_2d(world_verts, fill_color, outline_color)
    if not world_verts or #world_verts < 3 then
        return false
    end
    
    -- Convert all vertices to screen space
    local screen_verts = {}
    local all_visible = true
    
    for i, v in ipairs(world_verts) do
        local pos = vec3.new(v.x, v.y, v.z + CONFIG.height_offset)
        local screen = core.graphics.w2s(pos)
        if screen then
            screen_verts[i] = screen
        else
            all_visible = false
        end
    end
    
    if #screen_verts < 3 then
        return false
    end
    
    -- Draw outline in 2D
    if outline_color then
        local n = #screen_verts
        for i = 1, n do
            local s1 = screen_verts[i]
            local s2 = screen_verts[(i % n) + 1]
            if s1 and s2 then
                core.graphics.line_2d(s1, s2, outline_color, 1.0)
            end
        end
    end
    
    return true
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

--- Clip a point to stay within polygon bounds (simple containment check)
-- Uses ray casting algorithm for point-in-polygon test
-- @param point {x, y} point to test
-- @param verts Array of polygon vertices
-- @return boolean true if point is inside polygon
local function point_in_polygon_2d(point, verts)
    local n = #verts
    if n < 3 then return false end
    
    local inside = false
    local j = n
    
    for i = 1, n do
        local vi = verts[i]
        local vj = verts[j]
        
        if ((vi.y > point.y) ~= (vj.y > point.y)) and
           (point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x) then
            inside = not inside
        end
        j = i
    end
    
    return inside
end

--- Compute line segment intersection (2D)
-- @param p1, p2 First line segment endpoints
-- @param p3, p4 Second line segment endpoints
-- @return intersection point {x, y} or nil if no intersection
local function line_segment_intersection(p1, p2, p3, p4)
    local d1x = p2.x - p1.x
    local d1y = p2.y - p1.y
    local d2x = p4.x - p3.x
    local d2y = p4.y - p3.y
    
    local cross = d1x * d2y - d1y * d2x
    if math.abs(cross) < 0.0001 then
        return nil  -- Parallel lines
    end
    
    local dx = p3.x - p1.x
    local dy = p3.y - p1.y
    
    local t = (dx * d2y - dy * d2x) / cross
    local u = (dx * d1y - dy * d1x) / cross
    
    if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
        return {
            x = p1.x + t * d1x,
            y = p1.y + t * d1y
        }
    end
    
    return nil
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

--- Draw penalty zones for a polygon's wall edges
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
    
    if not verts or vc < 3 or not center then
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
    
    -- Iterate through edges, find wall edges (neis == 0)
    for i = 1, vc do
        local nei = neis and neis[i] or 0
        
        if not nei or nei == 0 then  -- Wall edge
            local v1 = world_verts[i]
            local v2 = world_verts[(i % vc) + 1]
            
            if v1 and v2 then
                -- Draw Zone 3 first (farthest from wall, underneath)
                local zone3_verts = generate_wall_zone_quad(v1, v2, zone3_dist, zone2_dist, center, world_verts)
                if zone3_verts and #zone3_verts >= 3 then
                    DrawPolygon.draw_filled(zone3_verts, zone3_color)
                    zone3_count = zone3_count + 1
                end
                
                -- Draw Zone 2 (middle layer)
                local zone2_verts = generate_wall_zone_quad(v1, v2, zone2_dist, zone1_dist, center, world_verts)
                if zone2_verts and #zone2_verts >= 3 then
                    DrawPolygon.draw_filled(zone2_verts, zone2_color)
                    zone2_count = zone2_count + 1
                end
                
                -- Draw Zone 1 on top (closest to wall)
                local zone1_verts = generate_wall_zone_quad(v1, v2, zone1_dist, 0, center, world_verts)
                if zone1_verts and #zone1_verts >= 3 then
                    DrawPolygon.draw_filled(zone1_verts, zone1_color)
                    zone1_count = zone1_count + 1
                end
            end
        end
    end
    
    return {zone1_drawn = zone1_count, zone2_drawn = zone2_count, zone3_drawn = zone3_count}
end

--- Get penalty value for a point based on wall proximity
-- @param point {x, y, z} World position to check
-- @param poly Polygon object with worldVerts, neis, vertCount, center
-- @return penalty multiplier (1.0 = no penalty, higher = more penalty)
function DrawPolygon.get_wall_penalty(point, poly)
    if not CONFIG.penalty_zones.enabled then
        return 1.0
    end
    
    local verts = poly.worldVerts
    local neis = poly.neis
    local vc = poly.vertCount or #verts
    
    if not verts or vc < 3 then
        return 1.0
    end
    
    local min_wall_dist = math.huge
    
    -- Find minimum distance to any wall edge
    for i = 1, vc do
        local nei = neis and neis[i] or 0
        
        if not nei or nei == 0 then  -- Wall edge
            local v1 = verts[i]
            local v2 = verts[(i % vc) + 1]
            
            if v1 and v2 then
                -- Compute distance from point to line segment
                local dx = v2.x - v1.x
                local dy = v2.y - v1.y
                local len_sq = dx*dx + dy*dy
                
                local t = 0
                if len_sq > 0.0001 then
                    t = ((point.x - v1.x) * dx + (point.y - v1.y) * dy) / len_sq
                    t = math.max(0, math.min(1, t))
                end
                
                local closest_x = v1.x + t * dx
                local closest_y = v1.y + t * dy
                
                local dist = math.sqrt((point.x - closest_x)^2 + (point.y - closest_y)^2)
                
                if dist < min_wall_dist then
                    min_wall_dist = dist
                end
            end
        end
    end
    
    -- Determine penalty based on distance
    if min_wall_dist <= CONFIG.penalty_zones.zone1_distance then
        return CONFIG.penalty_zones.zone1_penalty
    elseif min_wall_dist <= CONFIG.penalty_zones.zone2_distance then
        return CONFIG.penalty_zones.zone2_penalty
    elseif min_wall_dist <= CONFIG.penalty_zones.zone3_distance then
        return CONFIG.penalty_zones.zone3_penalty
    end
    
    return 1.0  -- No penalty
end

-- ===========================================
-- CONFIGURATION FUNCTIONS
-- ===========================================

--- Set fill color
function DrawPolygon.set_fill_color(r, g, b, a)
    CONFIG.fill_color = color.new(r, g, b, a)
end

--- Set wall edge color
function DrawPolygon.set_wall_color(r, g, b, a)
    CONFIG.wall_edge_color = color.new(r, g, b, a)
end

--- Set internal edge color
function DrawPolygon.set_internal_color(r, g, b, a)
    CONFIG.internal_edge_color = color.new(r, g, b, a)
end

--- Set external edge color
function DrawPolygon.set_external_color(r, g, b, a)
    CONFIG.external_edge_color = color.new(r, g, b, a)
end

--- Set height offset
function DrawPolygon.set_height_offset(offset)
    CONFIG.height_offset = offset
end

--- Set edge thickness
function DrawPolygon.set_edge_thickness(normal, wall)
    CONFIG.edge_thickness = normal
    CONFIG.wall_edge_thickness = wall or normal
end

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

--- Get current configuration
function DrawPolygon.get_config()
    return CONFIG
end

-- ===========================================
-- EDGE TYPE CONSTANTS (exported)
-- ===========================================
DrawPolygon.EDGE_TYPE = EDGE_TYPE

-- ===========================================
-- EXPORT TO GLOBAL
-- ===========================================
_G.DrawPolygon = DrawPolygon

return DrawPolygon