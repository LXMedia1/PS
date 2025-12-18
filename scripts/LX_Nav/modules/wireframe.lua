-- Wireframe Visualization Module
-- Renders navmesh polygons in 3D for debugging
-- Uses TileManager for non-blocking tile loading

local Debug = require("modules/debug")
local TileManager = require("modules/tile_manager")

local color = require("common/color")
local vec3 = require("common/geometry/vector_3")

-- Debug counter
local frame_count = 0
local last_debug_time = 0

local Wireframe = {}

-- TileManager instance (created on first use)
local tile_manager = nil

-- Configuration
local CONFIG = {
    enabled = false,
    draw_range = 50,           -- Only draw polygons within this range (yards)
    draw_filled = true,        -- Draw filled polygons (transparent)
    draw_edges = false,        -- Draw polygon edges
    draw_centers = false,      -- Draw center points
    draw_offmesh = true,       -- Draw off-mesh connections (jump/teleport links)
    fill_color = color.new(0, 200, 100, 60),       -- Semi-transparent green fill
    edge_color = color.new(0, 255, 100, 200),      -- Green edges
    edge_thickness = 1.5,
    center_color = color.new(255, 255, 0, 180),    -- Yellow centers
    center_radius = 0.3,
    external_edge_color = color.new(255, 100, 0, 220),  -- Orange for external edges
    offmesh_color = color.new(255, 0, 255, 220),   -- Magenta for off-mesh connections
    offmesh_bidir_color = color.new(0, 255, 255, 220),  -- Cyan for bidirectional
    offmesh_thickness = 2.5,
    draw_bvnodes = false,      -- Draw bounding volume tree (spatial query structure)
    bvnode_alpha = 40,         -- Transparency for BV boxes
    bvnode_max_depth = 8,      -- Max tree depth to visualize (0=all)
    height_offset = 0.1,       -- Slight offset above ground to prevent z-fighting
}

-- Current state tracking
local current_map_id = nil
local last_tile_x, last_tile_y = nil, nil

-- Tile size constants (from mesh_helper.lua reference)
local TILE_SIZE = 533.33333
local HALF_WORLD = 32 * TILE_SIZE  -- = 17066.66656 (center of world grid)

--- Initialize TileManager if not already created
local function ensure_tile_manager()
    if not tile_manager then
        tile_manager = TileManager.new({
            frame_budget_ms = 3.0,  -- 3ms per frame for loading
            check_every = 128,       -- Check budget every 128 iterations
            max_cached = 25,         -- Cache up to 25 tiles
        })
        Debug.log("[Wireframe] TileManager initialized (3ms budget, 128 check interval)")
    end
    return tile_manager
end

--- Calculate which file tile to load based on WoW position
local function world_to_tile(x, y)
    local tile_x = math.floor((HALF_WORLD - x) / TILE_SIZE)
    local tile_y = math.floor((HALF_WORLD - y) / TILE_SIZE)
    -- Clamp to valid range (0-63)
    tile_x = math.max(0, math.min(63, tile_x))
    tile_y = math.max(0, math.min(63, tile_y))
    return tile_x, tile_y
end

--- Queue tiles around player (3x3 grid) - non-blocking
local function queue_nearby_tiles(map_id, center_x, center_y)
    local mgr = ensure_tile_manager()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local tx, ty = center_x + dx, center_y + dy
            -- Priority: center=0, adjacent=1, diagonal=2
            local prio = math.abs(dx) + math.abs(dy)
            mgr:queue_tile(map_id, tx, ty, prio)
        end
    end
end

--- Get all loaded tiles for rendering
local function get_loaded_tiles(map_id)
    local mgr = ensure_tile_manager()
    return mgr:get_all_tiles(map_id)
end

-- Check if a point is within draw range
local function in_range(px, py, pz, player_pos)
    local dx = px - player_pos.x
    local dy = py - player_pos.y
    local dz = pz - player_pos.z
    local dist_sq = dx*dx + dy*dy + dz*dz
    return dist_sq <= (CONFIG.draw_range * CONFIG.draw_range)
end

-- Debug: Log detail mesh info for multiple polygons
local detail_debug_count = 0
local detail_debug_max = 10  -- Log first 10 polygons in range
local function debug_detail_mesh(tile, poly, polyIndex)
    if detail_debug_count >= detail_debug_max then return end
    if not tile.detailMeshes or not tile.detailMeshes[polyIndex] then return end

    local detail = tile.detailMeshes[polyIndex]
    local LOG = "detail_mesh_debug.log"

    if detail_debug_count == 0 then
        core.create_log_file(LOG)
    end
    detail_debug_count = detail_debug_count + 1

    local function log(msg)
        core.write_log_file(LOG, msg .. "\n")
    end

    log("=== DETAIL MESH DEBUG ===")
    log(string.format("Polygon %d:", polyIndex))
    log(string.format("  vertCount: %d", poly.vertCount))

    -- Also log mesh header counts for verification
    if tile.meshHeader then
        local mh = tile.meshHeader
        log(string.format("  MeshHeader: polys=%d, verts=%d, maxLinks=%d",
            mh.polyCount or 0, mh.vertCount or 0, mh.maxLinkCount or 0))
        log(string.format("  MeshHeader: detailMeshes=%d, detailVerts=%d, detailTris=%d",
            mh.detailMeshCount or 0, mh.detailVertCount or 0, mh.detailTriCount or 0))
    end

    log(string.format("  detailMesh: vertBase=%d, triBase=%d, vertCount=%d, triCount=%d",
        detail.vertBase, detail.triBase, detail.vertCount, detail.triCount))

    -- Log polygon vertices
    log("  Polygon vertices (worldVerts):")
    for i = 1, poly.vertCount do
        local v = poly.worldVerts[i]
        if v then
            log(string.format("    [%d] verts[%d]=%d -> (%.2f, %.2f, %.2f)",
                i-1, i, poly.verts[i], v.x, v.y, v.z))
        else
            log(string.format("    [%d] verts[%d]=%d -> NIL!", i-1, i, poly.verts[i]))
        end
    end

    -- Log detail vertices for this polygon
    if detail.vertCount > 0 then
        log(string.format("  Detail vertices (starting at vertBase=%d):", detail.vertBase))
        for i = 0, detail.vertCount - 1 do
            local idx = detail.vertBase + i + 1
            local v = tile.detailVerts[idx]
            if v then
                log(string.format("    [%d] idx=%d -> (%.2f, %.2f, %.2f)",
                    poly.vertCount + i, idx, v.x, v.y, v.z))
            else
                log(string.format("    [%d] idx=%d -> NIL!", poly.vertCount + i, idx))
            end
        end
    else
        log("  No detail vertices for this polygon")
    end

    -- Log detail triangles
    log(string.format("  Detail triangles (starting at triBase=%d):", detail.triBase))
    for t = 0, detail.triCount - 1 do
        local triIdx = detail.triBase + t + 1
        local tri = tile.detailTris[triIdx]
        if tri then
            log(string.format("    tri[%d]: v0=%d, v1=%d, v2=%d, flags=%d",
                t, tri.v0, tri.v1, tri.v2, tri.flags))
            -- Check if indices are valid
            local maxIdx = poly.vertCount + detail.vertCount - 1
            if tri.v0 > maxIdx or tri.v1 > maxIdx or tri.v2 > maxIdx then
                log(string.format("      WARNING: Index out of range! max=%d", maxIdx))
            end
        else
            log(string.format("    tri[%d] at idx=%d: NIL!", t, triIdx))
        end
    end

    log("=== END DEBUG ===")
    log("")
end

-- Get vertex for detail triangle rendering
-- If index < polyVertCount -> use main vertex from tile.vertices
-- If index >= polyVertCount -> use detail vertex
local function get_detail_vertex(tile, poly, polyIndex, vertexIndex)
    local polyVertCount = poly.vertCount
    local detail = tile.detailMeshes and tile.detailMeshes[polyIndex]

    if vertexIndex < polyVertCount then
        -- Use main polygon vertex
        local mainIdx = poly.verts[vertexIndex + 1]  -- +1 for Lua 1-indexed
        if mainIdx and tile.vertices[mainIdx + 1] then
            return tile.vertices[mainIdx + 1]
        end
    else
        -- Use detail vertex
        if detail and tile.detailVerts then
            local detailIdx = detail.vertBase + (vertexIndex - polyVertCount)
            if tile.detailVerts[detailIdx + 1] then
                return tile.detailVerts[detailIdx + 1]
            end
        end
    end
    return nil
end

-- Draw polygon using detail triangles (finer terrain following)
local function draw_polygon_detail(tile, poly, polyIndex, player_pos)
    if not poly.center then
        return false
    end

    -- Check if polygon center is in range
    if not in_range(poly.center.x, poly.center.y, poly.center.z, player_pos) then
        return false
    end

    -- Debug: log one polygon's detail mesh data
    debug_detail_mesh(tile, poly, polyIndex)

    local detail = tile.detailMeshes and tile.detailMeshes[polyIndex]
    local drawnAny = false

    -- Draw using detail triangles if available
    if CONFIG.draw_filled and detail and detail.triCount > 0 and tile.detailTris then
        for t = 0, detail.triCount - 1 do
            local triIndex = detail.triBase + t + 1  -- +1 for Lua 1-indexed
            local tri = tile.detailTris[triIndex]
            if tri then
                local v0 = get_detail_vertex(tile, poly, polyIndex, tri.v0)
                local v1 = get_detail_vertex(tile, poly, polyIndex, tri.v1)
                local v2 = get_detail_vertex(tile, poly, polyIndex, tri.v2)

                if v0 and v1 and v2 then
                    local p0 = vec3.new(v0.x, v0.y, v0.z)
                    local p1 = vec3.new(v1.x, v1.y, v1.z)
                    local p2 = vec3.new(v2.x, v2.y, v2.z)
                    core.graphics.triangle_3d_filled(p0, p1, p2, CONFIG.fill_color)
                    drawnAny = true
                end
            end
        end
    end

    -- Fallback: draw using main polygon vertices if no detail triangles
    if CONFIG.draw_filled and not drawnAny and poly.worldVerts and #poly.worldVerts >= 3 then
        local verts = poly.worldVerts
        local vc = poly.vertCount
        local v0 = verts[1]
        if v0 then
            local p0 = vec3.new(v0.x, v0.y, v0.z)
            for i = 2, vc - 1 do
                local v1 = verts[i]
                local v2 = verts[i + 1]
                if v1 and v2 then
                    local p1 = vec3.new(v1.x, v1.y, v1.z)
                    local p2 = vec3.new(v2.x, v2.y, v2.z)
                    core.graphics.triangle_3d_filled(p0, p1, p2, CONFIG.fill_color)
                    drawnAny = true
                end
            end
        end
    end

    -- Draw polygon edges (boundary)
    if CONFIG.draw_edges and poly.worldVerts then
        local verts = poly.worldVerts
        local vc = poly.vertCount
        for i = 1, vc do
            local v1 = verts[i]
            local v2 = verts[(i % vc) + 1]

            if v1 and v2 then
                local p1 = vec3.new(v1.x, v1.y, v1.z)
                local p2 = vec3.new(v2.x, v2.y, v2.z)

                -- Check if this edge is external
                local nei = poly.neis and poly.neis[i] or 0
                local is_external = (nei >= 0x8000)
                local edge_color = is_external and CONFIG.external_edge_color or CONFIG.edge_color

                core.graphics.line_3d(p1, p2, edge_color, CONFIG.edge_thickness)
            end
        end
    end

    -- Draw center point
    if CONFIG.draw_centers then
        local center = vec3.new(poly.center.x, poly.center.y, poly.center.z)
        core.graphics.circle_3d_filled(center, CONFIG.center_radius, CONFIG.center_color)
    end

    return drawnAny
end

-- Draw a 3D bounding box (8 vertices, 12 edges)
local function draw_box_3d(bmin, bmax, box_color)
    -- 8 corners of the box
    local corners = {
        vec3.new(bmin.x, bmin.y, bmin.z),  -- 0: min
        vec3.new(bmax.x, bmin.y, bmin.z),  -- 1
        vec3.new(bmax.x, bmax.y, bmin.z),  -- 2
        vec3.new(bmin.x, bmax.y, bmin.z),  -- 3
        vec3.new(bmin.x, bmin.y, bmax.z),  -- 4
        vec3.new(bmax.x, bmin.y, bmax.z),  -- 5
        vec3.new(bmax.x, bmax.y, bmax.z),  -- 6: max
        vec3.new(bmin.x, bmax.y, bmax.z),  -- 7
    }

    -- 12 edges connecting corners
    local edges = {
        {1,2}, {2,3}, {3,4}, {4,1},  -- bottom face
        {5,6}, {6,7}, {7,8}, {8,5},  -- top face
        {1,5}, {2,6}, {3,7}, {4,8},  -- vertical edges
    }

    for _, edge in ipairs(edges) do
        core.graphics.line_3d(corners[edge[1]], corners[edge[2]], box_color, 1.0)
    end
end

-- Get color for BVNode based on tree depth (red=shallow, blue=deep)
local function get_depth_color(depth, max_depth, alpha)
    local t = math.min(depth / math.max(max_depth, 1), 1.0)
    -- Gradient from red (shallow) through yellow/green to blue (deep)
    local r = math.floor(255 * (1 - t))
    local g = math.floor(255 * math.sin(t * 3.14159))  -- peaks in middle
    local b = math.floor(255 * t)
    return color.new(r, g, b, alpha)
end

-- Draw BVNodes (bounding volume tree) for spatial visualization
local function draw_bvnodes(tile, player_pos)
    if not CONFIG.draw_bvnodes or not tile.bvNodes or #tile.bvNodes == 0 then
        return 0
    end

    local mh = tile.meshHeader
    if not mh or not mh.bmin or not mh.bvQuantFactor then
        return 0
    end

    local drawn = 0
    local quantFactor = mh.bvQuantFactor

    -- Recursive function to traverse BV tree
    local function traverse_node(nodeIdx, depth)
        if nodeIdx < 1 or nodeIdx > #tile.bvNodes then
            return
        end
        if CONFIG.bvnode_max_depth > 0 and depth > CONFIG.bvnode_max_depth then
            return
        end

        local node = tile.bvNodes[nodeIdx]
        if not node then return end

        -- Dequantize bounds: world = tile.bmin + quantized * quantFactor
        -- Then convert Recast to WoW: wowX = rz, wowY = rx, wowZ = ry
        local rMinX = mh.bmin[1] + node.bmin[1] * quantFactor
        local rMinY = mh.bmin[2] + node.bmin[2] * quantFactor
        local rMinZ = mh.bmin[3] + node.bmin[3] * quantFactor
        local rMaxX = mh.bmin[1] + node.bmax[1] * quantFactor
        local rMaxY = mh.bmin[2] + node.bmax[2] * quantFactor
        local rMaxZ = mh.bmin[3] + node.bmax[3] * quantFactor

        -- Convert Recast to WoW
        local wowMin = { x = rMinZ, y = rMinX, z = rMinY }
        local wowMax = { x = rMaxZ, y = rMaxX, z = rMaxY }

        -- Swap if needed (min should be < max)
        if wowMin.x > wowMax.x then wowMin.x, wowMax.x = wowMax.x, wowMin.x end
        if wowMin.y > wowMax.y then wowMin.y, wowMax.y = wowMax.y, wowMin.y end
        if wowMin.z > wowMax.z then wowMin.z, wowMax.z = wowMax.z, wowMin.z end

        -- Check if box center is in range
        local cx = (wowMin.x + wowMax.x) / 2
        local cy = (wowMin.y + wowMax.y) / 2
        local cz = (wowMin.z + wowMax.z) / 2

        if in_range(cx, cy, cz, player_pos) then
            local box_color = get_depth_color(depth, CONFIG.bvnode_max_depth, CONFIG.bvnode_alpha)
            draw_box_3d(wowMin, wowMax, box_color)
            drawn = drawn + 1
        end

        -- If internal node, recurse to children
        if node.i >= 0 then
            -- Children are at indices i+1 and i+2 (Lua 1-indexed)
            traverse_node(node.i + 1, depth + 1)
            traverse_node(node.i + 2, depth + 1)
        end
        -- If leaf (node.i < 0), polygon index = -(node.i + 1), no children
    end

    -- Start traversal from root (index 1)
    traverse_node(1, 0)

    return drawn
end

-- Draw off-mesh connections (jump/teleport links)
local function draw_offmesh_connections(tile, player_pos)
    if not CONFIG.draw_offmesh or not tile.offMeshConnections then
        return 0
    end

    local drawn = 0
    for _, conn in ipairs(tile.offMeshConnections) do
        local start = conn.startPos
        local endp = conn.endPos

        -- Check if either end is in range
        if in_range(start.x, start.y, start.z, player_pos) or
           in_range(endp.x, endp.y, endp.z, player_pos) then

            local p1 = vec3.new(start.x, start.y, start.z)
            local p2 = vec3.new(endp.x, endp.y, endp.z)

            -- Color based on direction
            local link_color = conn.bidirectional and CONFIG.offmesh_bidir_color or CONFIG.offmesh_color

            -- Draw the connection line
            core.graphics.line_3d(p1, p2, link_color, CONFIG.offmesh_thickness)

            -- Draw circles at endpoints
            core.graphics.circle_3d_filled(p1, 0.5, link_color)
            core.graphics.circle_3d_filled(p2, 0.5, link_color)

            drawn = drawn + 1
        end
    end
    return drawn
end

-- Draw a single polygon (legacy, uses polygon fan)
local function draw_polygon(poly, player_pos)
    if not poly.worldVerts or #poly.worldVerts < 3 then
        return false
    end

    -- Check if polygon center is in range
    if not in_range(poly.center.x, poly.center.y, poly.center.z, player_pos) then
        return false
    end

    local verts = poly.worldVerts
    local vc = poly.vertCount

    -- Draw filled polygon using triangle fan from first vertex (no center point)
    -- This keeps all triangles on the actual terrain surface
    if CONFIG.draw_filled and vc >= 3 then
        local v0 = verts[1]
        if v0 then
            local p0 = vec3.new(v0.x, v0.y, v0.z)
            for i = 2, vc - 1 do
                local v1 = verts[i]
                local v2 = verts[i + 1]
                if v1 and v2 then
                    local p1 = vec3.new(v1.x, v1.y, v1.z)
                    local p2 = vec3.new(v2.x, v2.y, v2.z)
                    core.graphics.triangle_3d_filled(p0, p1, p2, CONFIG.fill_color)
                end
            end
        end
    end

    -- Draw edges
    if CONFIG.draw_edges then
        for i = 1, vc do
            local v1 = verts[i]
            local v2 = verts[(i % vc) + 1]

            if v1 and v2 then
                local p1 = vec3.new(v1.x, v1.y, v1.z)
                local p2 = vec3.new(v2.x, v2.y, v2.z)

                -- Check if this edge is external
                local nei = poly.neis and poly.neis[i] or 0
                local is_external = (nei >= 0x8000)
                local edge_color = is_external and CONFIG.external_edge_color or CONFIG.edge_color

                core.graphics.line_3d(p1, p2, edge_color, CONFIG.edge_thickness)
            end
        end
    end

    -- Draw center point
    if CONFIG.draw_centers then
        local center = vec3.new(poly.center.x, poly.center.y, poly.center.z)
        core.graphics.circle_3d_filled(center, CONFIG.center_radius, CONFIG.center_color)
    end

    return true
end

-- Main render function (called every frame)
function Wireframe.render()
    if not CONFIG.enabled then
        return
    end

    Debug.perf_start("Wireframe.render")

    local player = core.object_manager.get_local_player()
    if not player then
        Debug.perf_end("Wireframe.render")
        return
    end

    local player_pos = player:get_position()
    if not player_pos then
        Debug.perf_end("Wireframe.render")
        return
    end

    local map_id = core.get_instance_id()
    if not map_id then
        Debug.perf_end("Wireframe.render")
        return
    end

    -- Initialize tile manager and process loading
    Debug.perf_start("TileManager.init+process")
    local mgr = ensure_tile_manager()
    mgr:process_frame(3.0)  -- 3ms budget per frame
    Debug.perf_end("TileManager.init+process")

    -- Check if we need to queue more tiles
    local tile_x, tile_y = world_to_tile(player_pos.x, player_pos.y)

    if map_id ~= current_map_id or tile_x ~= last_tile_x or tile_y ~= last_tile_y then
        current_map_id = map_id
        last_tile_x = tile_x
        last_tile_y = tile_y
        -- Queue nearby tiles (non-blocking)
        Debug.perf_start("queue_nearby_tiles")
        queue_nearby_tiles(map_id, tile_x, tile_y)
        Debug.perf_end("queue_nearby_tiles")
    end

    -- Get whatever tiles are already loaded
    Debug.perf_start("get_loaded_tiles")
    local tiles = get_loaded_tiles(map_id)
    Debug.perf_end("get_loaded_tiles")

    local polys_drawn = 0
    local polys_checked = 0
    local detail_tris_drawn = 0
    local offmesh_drawn = 0
    local bvnodes_drawn = 0

    Debug.perf_start("draw_all_tiles")
    for _, tile in pairs(tiles) do  -- pairs instead of ipairs (tiles now have string keys)
        for polyIdx, poly in ipairs(tile.polygons) do
            polys_checked = polys_checked + 1
            -- Use detail triangles for better terrain following
            if draw_polygon_detail(tile, poly, polyIdx, player_pos) then
                polys_drawn = polys_drawn + 1
                -- Count detail triangles
                local detail = tile.detailMeshes and tile.detailMeshes[polyIdx]
                if detail and detail.triCount then
                    detail_tris_drawn = detail_tris_drawn + detail.triCount
                end
            end
        end
        -- Draw off-mesh connections (jump/teleport links)
        offmesh_drawn = offmesh_drawn + draw_offmesh_connections(tile, player_pos)

        -- Draw BVNodes (spatial query tree visualization)
        bvnodes_drawn = bvnodes_drawn + draw_bvnodes(tile, player_pos)
    end
    Debug.perf_end("draw_all_tiles")

    -- Log debug info every 2 seconds
    frame_count = frame_count + 1
    local now = core.time()
    if now - last_debug_time >= 2.0 then
        last_debug_time = now
        -- Log TileManager stats
        local stats = mgr:get_stats()
        Debug.log(string.format("[Wireframe] tile(%d,%d) cached=%d queued=%d polys=%d detailTris=%d offmesh=%d bvnodes=%d",
            tile_x, tile_y, stats.cached, stats.queued, polys_drawn, detail_tris_drawn, offmesh_drawn, bvnodes_drawn))
        -- Log center tile bounds with Recast values for debugging
        for _, tile in pairs(tiles) do  -- pairs instead of ipairs
            if tile.tileX == tile_x and tile.tileY == tile_y then
                -- This is the center tile - log everything
                if tile.meshHeader then
                    local mh = tile.meshHeader
                    Debug.log(string.format("[Wireframe] Center tile (%d_%d) Recast bmin(%.1f,%.1f,%.1f) bmax(%.1f,%.1f,%.1f)",
                        tile.tileX, tile.tileY,
                        mh.bmin[1], mh.bmin[2], mh.bmin[3],
                        mh.bmax[1], mh.bmax[2], mh.bmax[3]))
                end
                if tile.boundsWow then
                    local b = tile.boundsWow
                    local inside_x = player_pos.x >= b.min.x and player_pos.x <= b.max.x
                    local inside_y = player_pos.y >= b.min.y and player_pos.y <= b.max.y
                    Debug.log(string.format("[Wireframe] Center tile WoW bounds: X[%.1f,%.1f] Y[%.1f,%.1f] inside=%s",
                        b.min.x, b.max.x, b.min.y, b.max.y, (inside_x and inside_y) and "YES" or "NO"))
                end
                -- Log first polygon center for sanity check
                if tile.polygons and #tile.polygons > 0 then
                    local p = tile.polygons[1]
                    if p.center then
                        Debug.log(string.format("[Wireframe] First poly center: (%.1f,%.1f,%.1f)",
                            p.center.x, p.center.y, p.center.z))
                    end
                end
                break
            end
        end
    end

    Debug.perf_end("Wireframe.render")
end

-- Enable/disable wireframe (only log on state change)
function Wireframe.set_enabled(enabled)
    if CONFIG.enabled ~= enabled then
        CONFIG.enabled = enabled
        if enabled then
            -- Reset state to trigger fresh tile queueing
            current_map_id = nil
            last_tile_x = nil
            last_tile_y = nil
            Debug.log("[Wireframe] Enabled")
        else
            Debug.log("[Wireframe] Disabled")
        end
    end
end

function Wireframe.is_enabled()
    return CONFIG.enabled
end

-- Configure draw range
function Wireframe.set_range(range)
    CONFIG.draw_range = range
end

-- Enable/disable BVNode visualization
function Wireframe.set_bvnodes_enabled(enabled)
    CONFIG.draw_bvnodes = enabled
end

-- Clear tile cache
function Wireframe.clear_cache()
    if tile_manager then
        tile_manager:clear()
    end
    current_map_id = nil
    last_tile_x = nil
    last_tile_y = nil
    Debug.log("[Wireframe] Cache cleared")
end

-- Get the TileManager instance (for external use)
function Wireframe.get_tile_manager()
    return ensure_tile_manager()
end

return Wireframe
