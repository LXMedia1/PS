-- Navigation Query Module
-- A* pathfinding, funnel smoothing, BVH lookup, height sampling

local Heap = require("modules/heap")
local TileConverter = require("modules/tile_converter")

local NavQuery = {}
NavQuery.__index = NavQuery

-- TILE_STRIDE must exceed max polys per tile (typically ~15000)
local TILE_STRIDE = 200000

-- Create path debug log file at module load
core.create_log_file("LX_Nav_path_debug.log")

-- =========================
-- Helper Functions
-- =========================

local function dist2D(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

local function dist3D(ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 2D triangle area matching Detour's dtTriArea2D (cross product AC × AB)
-- Positive = C is RIGHT of line A→B
-- Negative = C is LEFT of line A→B
-- Zero = collinear
-- This matches Detour's convention for the funnel algorithm
local function triArea2D(ax, ay, bx, by, cx, cy)
    local abx, aby = bx - ax, by - ay
    local acx, acy = cx - ax, cy - ay
    return acx * aby - abx * acy  -- AC × AB (Detour convention)
end

-- Check if two 2D points are equal within epsilon
local function veq2(ax, ay, bx, by, eps2)
    eps2 = eps2 or 1e-12
    local dx, dy = bx - ax, by - ay
    return (dx * dx + dy * dy) <= eps2
end

-- DEBUG: Log file for portal ordering
local ORDER_DEBUG_LOG = "LX_Nav_order_debug.log"
local orderDebugLines = {}

-- Determine portal left/right using travel direction (WINDING-AGNOSTIC)
-- Given edge endpoints a,b and travel direction, returns (left, right)
-- Uses signed distance from travel line: point with larger left-distance is LEFT
local function orderPortalLeftRight(ax, ay, az, bx, by, bz, dirX, dirY)
    -- For each point, compute "leftness" = dirX*py - dirY*px
    -- This is the signed perpendicular distance from the travel direction
    -- Positive = left of travel, Negative = right of travel
    local leftA = dirX * ay - dirY * ax
    local leftB = dirX * by - dirY * bx

    local logLine = string.format(
        "  A=(%.1f,%.1f) B=(%.1f,%.1f) dir=(%.2f,%.2f) leftA=%.1f leftB=%.1f => ",
        ax, ay, bx, by, dirX, dirY, leftA, leftB
    )

    if leftA > leftB then
        -- a is more to the left
        orderDebugLines[#orderDebugLines + 1] = logLine .. "A=left, B=right"
        return {x = ax, y = ay, z = az}, {x = bx, y = by, z = bz}
    else
        -- b is more to the left
        orderDebugLines[#orderDebugLines + 1] = logLine .. "B=left, A=right"
        return {x = bx, y = by, z = bz}, {x = ax, y = ay, z = az}
    end
end

-- Function to flush order debug log
local function flushOrderDebug()
    if #orderDebugLines > 0 then
        core.create_log_file(ORDER_DEBUG_LOG)
        core.write_log_file(ORDER_DEBUG_LOG, table.concat(orderDebugLines, "\n"))
        orderDebugLines = {}
    end
end

-- Node ID encoding/decoding
local function node_id(tileId, poly)
    return tileId * TILE_STRIDE + poly
end

local function decode_node(nodeId)
    local tileId = math.floor(nodeId / TILE_STRIDE)
    local poly = nodeId - tileId * TILE_STRIDE
    return tileId, poly
end

-- =========================
-- Height Sampling Helpers
-- =========================

-- Sample height from RAW tile for a specific polygon
-- This is the most accurate method - uses actual detail mesh data
local function sample_height_from_raw_tile(rawTile, polyIndex, x, y)
    if not rawTile or not rawTile.polygons then return nil end

    local poly = rawTile.polygons[polyIndex]
    if not poly then return nil end

    local detail = rawTile.detailMeshes and rawTile.detailMeshes[polyIndex]
    if not detail then
        -- No detail mesh - use polygon center
        return poly.center and poly.center.z or nil
    end

    -- Helper to get vertex for detail triangle (same as wireframe's get_detail_vertex)
    local function get_raw_vert(vertexIndex)
        local polyVertCount = poly.vertCount
        if vertexIndex < polyVertCount then
            -- Main polygon vertex
            local mainIdx = poly.verts[vertexIndex + 1]  -- +1 for Lua 1-indexed
            if mainIdx and rawTile.vertices[mainIdx + 1] then
                return rawTile.vertices[mainIdx + 1]
            end
        else
            -- Detail vertex
            if rawTile.detailVerts then
                local detailIdx = detail.vertBase + (vertexIndex - polyVertCount)
                if rawTile.detailVerts[detailIdx + 1] then
                    return rawTile.detailVerts[detailIdx + 1]
                end
            end
        end
        return nil
    end

    -- Check each detail triangle
    local closestZ = nil
    local closestDistSq = math.huge

    local triCount = detail.triCount or 0
    for t = 0, triCount - 1 do
        local triIndex = detail.triBase + t + 1  -- +1 for Lua 1-indexed
        local tri = rawTile.detailTris[triIndex]
        if tri then
            local v0 = get_raw_vert(tri.v0)
            local v1 = get_raw_vert(tri.v1)
            local v2 = get_raw_vert(tri.v2)

            if v0 and v1 and v2 then
                -- Point in triangle test (2D) using barycentric coords
                local v1x, v1y = v1.x - v0.x, v1.y - v0.y
                local v2x, v2y = v2.x - v0.x, v2.y - v0.y
                local px, py = x - v0.x, y - v0.y
                local d00 = v1x * v1x + v1y * v1y
                local d01 = v1x * v2x + v1y * v2y
                local d02 = v1x * px + v1y * py
                local d11 = v2x * v2x + v2y * v2y
                local d12 = v2x * px + v2y * py

                local denom = d00 * d11 - d01 * d01
                if math.abs(denom) > 1e-10 then
                    local invDenom = 1 / denom
                    local u = (d11 * d02 - d01 * d12) * invDenom
                    local v = (d00 * d12 - d01 * d02) * invDenom

                    if u >= 0 and v >= 0 and (u + v) <= 1 then
                        -- Inside triangle - interpolate height
                        local w = 1 - u - v
                        return w * v0.z + u * v1.z + v * v2.z
                    end
                end

                -- Track closest for fallback
                local tcx = (v0.x + v1.x + v2.x) / 3
                local tcy = (v0.y + v1.y + v2.y) / 3
                local tcz = (v0.z + v1.z + v2.z) / 3
                local distSq = (x - tcx) * (x - tcx) + (y - tcy) * (y - tcy)
                if distSq < closestDistSq then
                    closestDistSq = distSq
                    closestZ = tcz
                end
            end
        end
    end

    return closestZ
end

-- Find polygon in raw tile that contains point (x, y) and sample height
-- Searches ALL polygons, not just corridor - handles wall avoidance pushing points outside corridor
local function find_height_in_raw_tile(rawTile, x, y)
    if not rawTile or not rawTile.polygons then return nil end

    -- Search all polygons to find one containing (x, y)
    for polyIndex, poly in ipairs(rawTile.polygons) do
        if poly.worldVerts and poly.vertCount >= 3 then
            -- Point-in-polygon test using ray casting
            local inside = false
            local n = poly.vertCount
            local j = n
            for i = 1, n do
                local vi = poly.worldVerts[i]
                local vj = poly.worldVerts[j]
                if vi and vj then
                    if ((vi.y > y) ~= (vj.y > y)) and
                       (x < (vj.x - vi.x) * (y - vi.y) / (vj.y - vi.y) + vi.x) then
                        inside = not inside
                    end
                end
                j = i
            end

            if inside then
                -- Found containing polygon - sample height from detail mesh
                return sample_height_from_raw_tile(rawTile, polyIndex, x, y)
            end
        end
    end

    return nil  -- Not found in any polygon
end

-- Closest point on 2D line segment (returns closest point + squared distance)
local function closest_pt_seg2d(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local apx, apy = px - ax, py - ay
    local d = abx * abx + aby * aby
    local t = (d > 0) and ((apx * abx + apy * aby) / d) or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = ax + abx * t, ay + aby * t
    local dx, dy = px - cx, py - cy
    return cx, cy, dx * dx + dy * dy
end

-- Point-in-polygon test (ray casting, XY plane)
-- Detour uses XZ plane, we use XY since WoW Z is up
local function point_in_poly_xy(px, py, vx, vy, n)
    local c = false
    local j = n
    for i = 1, n do
        local vix, viy = vx[i], vy[i]
        local vjx, vjy = vx[j], vy[j]
        if ((viy > py) ~= (vjy > py)) and
           (px < (vjx - vix) * (py - viy) / (vjy - viy) + vix) then
            c = not c
        end
        j = i
    end
    return c
end

-- Closest point on polygon boundary in 2D
local function closest_point_on_poly_xy(x, y, vx, vy, n)
    local bestx, besty, bestd = x, y, math.huge
    for i = 1, n do
        local j = (i % n) + 1
        local cx, cy, dsq = closest_pt_seg2d(x, y, vx[i], vy[i], vx[j], vy[j])
        if dsq < bestd then
            bestd, bestx, besty = dsq, cx, cy
        end
    end
    return bestx, besty, bestd
end

-- Robust triangle height using barycentric coordinates
local function tri_height_xy(px, py, ax, ay, az, bx, by, bz, cx, cy, cz)
    local v0x, v0y = bx - ax, by - ay
    local v1x, v1y = cx - ax, cy - ay
    local v2x, v2y = px - ax, py - ay
    local den = v0x * v1y - v1x * v0y
    if den > -1e-12 and den < 1e-12 then return nil end

    local u = (v2x * v1y - v1x * v2y) / den
    local v = (v0x * v2y - v2x * v0y) / den
    -- Relaxed tolerance for edge cases
    if u >= -1e-4 and v >= -1e-4 and (u + v) <= 1.0001 then
        return az + u * (bz - az) + v * (cz - az)
    end
    return nil
end

-- =========================
-- Off-Mesh Detection Helper
-- =========================

local function is_offmesh_poly(tile, poly)
    return tile.offMeshByPoly and tile.offMeshByPoly[poly] ~= nil
end

-- =========================
-- Internal Link Traversal Utilities
-- =========================
-- These functions decode and traverse Detour's internal links (side=0xFF)
-- to find off-mesh connections (jumps, teleports, etc.) for A* expansion

-- Detour link constants
local DT_NULL_LINK = 0xFFFFFFFF  -- End of link chain marker
local DT_INTERNAL_LINK_SIDE = 0xFF  -- Side value for internal (non-cross-tile) links

-- Decode 64-bit polygon reference to extract tile ID and polygon index
-- Detour encoding: salt(12 bits) + tile(21 bits) + poly(31 bits)
-- refLo contains poly (bits 0-30) and MSB of tile (bit 31)
-- refHi contains tile (bits 0-19) and salt (bits 20-31)
local function decode_poly_ref(refLo, refHi)
    if not refLo or refLo == 0 then
        return 0, 0  -- Invalid reference
    end

    -- Extract polygon index: bits 0-30 of refLo (31 bits)
    local poly = refLo % 0x80000000  -- bits 0-30

    -- Extract tile ID: bit 31 of refLo + bits 0-19 of refHi (21 bits total)
    local tileLo = math.floor(refLo / 0x80000000)  -- bit 31 of refLo (0 or 1)
    local tileHi = (refHi or 0) % 0x100000  -- bits 0-19 of refHi
    local tileId = tileLo + tileHi * 2  -- Combine: tileLo is LSB, tileHi shifted left by 1

    return tileId, poly
end

-- Get link data from flat array format
-- Links are stored as 5 consecutive values per link:
--   [base+1] = refLo (low 32 bits of target polygon ref)
--   [base+2] = refHi (high 32 bits of target polygon ref)
--   [base+3] = next link index (or DT_NULL_LINK)
--   [base+4] = edge + side*256 (packed)
--   [base+5] = bmin + bmax*256 (packed)
local function get_link(soa, linkIdx)
    if not soa.links or linkIdx == DT_NULL_LINK then
        return nil
    end

    local base = linkIdx * 5
    if base + 5 > #soa.links then
        return nil
    end

    local refLo = soa.links[base + 1]
    local refHi = soa.links[base + 2]
    local nextLink = soa.links[base + 3]
    local edgeSide = soa.links[base + 4]
    local bminBmax = soa.links[base + 5]

    return {
        refLo = refLo,
        refHi = refHi,
        next = nextLink,
        edge = edgeSide % 256,
        side = math.floor(edgeSide / 256),
        bmin = bminBmax % 256,
        bmax = math.floor(bminBmax / 256)
    }
end

-- Get all internal links for a polygon (side=0xFF only)
-- Returns array of {link, targetTileId, targetPoly} or empty array
-- Internal links are used for off-mesh connections within the same tile
local function get_internal_links(tile, poly)
    local results = {}

    if not tile.pFirstLink or not tile.links then
        return results
    end

    -- Get first link index for this polygon
    local linkIdx = tile.pFirstLink[poly]
    if not linkIdx or linkIdx == DT_NULL_LINK then
        return results
    end

    -- Traverse the link chain
    local maxIterations = 100  -- Safety limit to prevent infinite loops
    local iterations = 0

    while linkIdx ~= DT_NULL_LINK and iterations < maxIterations do
        iterations = iterations + 1

        local link = get_link(tile, linkIdx)
        if not link then
            break
        end

        -- Only process internal links (side = 0xFF)
        if link.side == DT_INTERNAL_LINK_SIDE then
            local targetTileId, targetPoly = decode_poly_ref(link.refLo, link.refHi)

            -- Valid internal links should target the same tile
            if targetPoly > 0 and targetPoly <= tile.polyCount then
                table.insert(results, {
                    link = link,
                    targetTileId = targetTileId,
                    targetPoly = targetPoly
                })
            end
        end

        -- Move to next link in chain
        linkIdx = link.next
    end

    return results
end

-- Check if a link represents an off-mesh connection (jump, teleport, etc.)
-- Off-mesh polygons are indexed in tile.offMeshByPoly
local function is_offmesh_link(tile, targetPoly)
    if not tile.offMeshByPoly or not targetPoly or targetPoly <= 0 then
        return false
    end
    return tile.offMeshByPoly[targetPoly] ~= nil
end

-- Get off-mesh connection data for a polygon
-- Returns the connection struct or nil if not an off-mesh polygon
local function get_offmesh_connection(tile, poly)
    if not tile.offMeshByPoly or not tile.offMeshConnections then
        return nil
    end
    local connIdx = tile.offMeshByPoly[poly]
    if not connIdx then
        return nil
    end
    return tile.offMeshConnections[connIdx]
end

-- =========================
-- Edge Avoidance Helper
-- =========================

local EDGE_MARGIN = 10.0  -- 10 yards from dangerous edges
local FLOOR_HEIGHT_OFFSET = 0.5  -- Small offset above ground for path visualization

local function adjust_waypoint_for_safety(tile, poly, x, y, margin)
    local pv = tile.pVertCount[poly]
    local base = (poly - 1) * 6

    -- Gather poly verts
    local vx, vy = {}, {}
    for i = 1, pv do
        local vi = tile.pVerts[base + i]
        vx[i] = tile.vx[vi]
        vy[i] = tile.vy[vi]
    end

    -- Only adjust if inside polygon
    if not point_in_poly_xy(x, y, vx, vy, pv) then
        return x, y
    end

    local m2 = margin * margin
    for i = 1, pv do
        local j = (i % pv) + 1
        local nei = tile.pNeis[base + i]
        -- Dangerous edges: walls (0) or external edges (>= 0x8000)
        local dangerous = (nei == 0) or (nei >= 0x8000)

        if dangerous then
            local cx, cy, dsq = closest_pt_seg2d(x, y, vx[i], vy[i], vx[j], vy[j])
            if dsq < m2 and dsq > 1e-10 then
                local dist = math.sqrt(dsq)
                local push = (margin - dist) / dist
                x = x + (x - cx) * push
                y = y + (y - cy) * push
            end
        end
    end

    return x, y
end

-- =========================
-- Floor Height Snapping (Async)
-- =========================

local vec3 = require("common/geometry/vector_3")

-- Async floor snapping state (module-level, shared across NavQuery instances)
local floor_snap_state = {
    active = false,
    waypoints = nil,
    current_index = 1,
    start_z = 0,
}

-- Floor snapping is now handled inline in poly_path_to_waypoints()
-- This function is kept for compatibility but does nothing
local function snap_waypoint_to_floor(wp, fallback_z)
    -- Height is already set correctly with floor-level continuity in funnel
    -- No additional processing needed
end

-- Process floor snapping incrementally (call each frame from main.lua)
-- Returns: true if still processing, false if done/idle
local function process_floor_snapping(max_per_frame)
    max_per_frame = max_per_frame or 3  -- Process 3 waypoints per frame

    if not floor_snap_state.active then return false end

    local waypoints = floor_snap_state.waypoints
    if not waypoints then
        floor_snap_state.active = false
        return false
    end

    local i = floor_snap_state.current_index
    local processed = 0

    while i <= #waypoints and processed < max_per_frame do
        snap_waypoint_to_floor(waypoints[i], floor_snap_state.start_z)
        i = i + 1
        processed = processed + 1
    end

    floor_snap_state.current_index = i

    if i > #waypoints then
        floor_snap_state.active = false
        return false  -- Done
    end

    return true  -- Still processing
end

-- Start async floor snapping for a path
local function start_floor_snapping(waypoints, start_z)
    floor_snap_state.active = true
    floor_snap_state.waypoints = waypoints
    floor_snap_state.current_index = 1
    floor_snap_state.start_z = start_z or 0
end

-- Check if floor snapping is in progress
local function is_floor_snapping_active()
    return floor_snap_state.active
end

-- =========================
-- NavQuery Constructor
-- =========================

function NavQuery.new(world, rawTileManager)
    local self = setmetatable({}, NavQuery)

    -- World reference (has tilesById: tileId -> SoA tile)
    self.world = world

    -- Optional: raw tile manager for accurate height sampling (uses wireframe's tile data)
    self.rawTileManager = rawTileManager

    -- A* state (reused across searches)
    self.heap = Heap.new()
    self.searchId = 0  -- Search stamp (increment per search to avoid clearing)
    self.seen = {}     -- seen[nodeId] = searchId if visited
    self.closed = {}   -- closed[nodeId] = searchId if expanded
    self.g = {}        -- g[nodeId] = cost from start
    self.f = {}        -- f[nodeId] = g + heuristic
    self.parent = {}   -- parent[nodeId] = previous node

    return self
end

-- Set the raw tile manager (can be set after construction)
function NavQuery:set_raw_tile_manager(mgr)
    self.rawTileManager = mgr
end

-- =========================
-- Step Cost Function
-- =========================

local NavConstants = require("modules/nav_constants")

-- Slope threshold for climbing (must match wireframe.lua)
local MAX_WALKABLE_SLOPE_UP = 0.7    -- ~35 degrees up
local MAX_WALKABLE_SLOPE_DOWN = 1.2  -- ~50 degrees down (steeper allowed going down)
local MAX_WAYPOINT_SLOPE = 0.6       -- Max slope between waypoints (~31 degrees)

-- Penalty multiplier for polygons near boundaries (walls/cliffs/edges)
local BOUNDARY_PENALTY = 1.2  -- Slight preference for interior polygons (was 8.0, too aggressive)

-- =========================
-- Off-Mesh Connection Cost Constants
-- =========================
-- Off-mesh connection types (matched to userId encoding in navmesh generation)
-- Common conventions: 0=walk, 1=jump, 2=teleport/portal, 3=ladder, 4=elevator
local OFFMESH_TYPE = {
    WALK = 0,       -- Standard walkable connection
    JUMP = 1,       -- Jump/drop connection (moderate penalty)
    TELEPORT = 2,   -- Teleport/portal (high penalty, prefer walkable)
    LADDER = 3,     -- Ladder climb (moderate penalty)
    ELEVATOR = 4,   -- Elevator/lift (moderate penalty)
}

-- Cost multipliers for off-mesh connection types
local OFFMESH_TYPE_COST = {
    [OFFMESH_TYPE.WALK] = 1.0,       -- No extra penalty for walkable
    [OFFMESH_TYPE.JUMP] = 1.5,       -- Moderate penalty for jumps
    [OFFMESH_TYPE.TELEPORT] = 5.0,   -- High penalty - prefer walkable routes
    [OFFMESH_TYPE.LADDER] = 2.0,     -- Moderate penalty for ladder
    [OFFMESH_TYPE.ELEVATOR] = 1.8,   -- Slight penalty for elevator wait time
}

-- Base multiplier for all off-mesh transitions
local OFFMESH_BASE_PENALTY = 2.0

-- Narrow connection penalty threshold and multiplier
local OFFMESH_NARROW_RADIUS = 1.0    -- Connections with radius below this get penalty
local OFFMESH_NARROW_PENALTY = 1.5   -- Additional multiplier for narrow connections

-- Transition type names for path output (maps userId to human-readable strings)
local OFFMESH_TYPE_NAME = {
    [OFFMESH_TYPE.WALK] = "WALK",
    [OFFMESH_TYPE.JUMP] = "JUMP",
    [OFFMESH_TYPE.TELEPORT] = "TELEPORT",
    [OFFMESH_TYPE.LADDER] = "LADDER",
    [OFFMESH_TYPE.ELEVATOR] = "ELEVATOR",
}

local function step_cost(tileA, polyA, tileB, polyB)
    -- Get polygon centers
    local ax, ay, az = tileA.pCx[polyA], tileA.pCy[polyA], tileA.pCz[polyA]
    local bx, by, bz = tileB.pCx[polyB], tileB.pCy[polyB], tileB.pCz[polyB]

    -- Calculate 2D distance
    local dx, dy = bx - ax, by - ay
    local xyDist = math.sqrt(dx * dx + dy * dy)

    -- Calculate slope (height change per XY distance)
    if xyDist > 0.1 then
        local heightDiff = bz - az  -- Positive = going UP, Negative = going DOWN
        local slope = heightDiff / xyDist

        -- Block paths that are too steep in either direction
        if slope > MAX_WALKABLE_SLOPE_UP then
            return 1e30  -- Can't climb this steep
        end
        if slope < -MAX_WALKABLE_SLOPE_DOWN then
            return 1e30  -- Can't descend this steep (cliff)
        end
    end

    -- Base cost: 2D distance
    local c = xyDist

    -- Check polygon flags for walkability
    local flags = tileB.pFlags[polyB] or 0
    if bit and bit.band then
        -- Unwalkable = infinite cost (skip this poly)
        if bit.band(flags, NavConstants.Flags.UNWALKABLE) ~= 0 then
            return 1e30
        end
        -- Swimming costs more
        if bit.band(flags, NavConstants.Flags.SWIM) ~= 0 then
            c = c * 1.5
        end
    else
        -- Fallback without bit library (check if UNWALKABLE bit is set)
        local flagCopy = flags
        local unwalkable = math.floor(flagCopy / NavConstants.Flags.UNWALKABLE) % 2
        if unwalkable == 1 then
            return 1e30
        end
    end

    -- Area type cost modifiers
    local area = tileB.pArea[polyB] or 0
    if area == NavConstants.Area.ROAD then
        c = c * 0.9  -- Prefer roads
    elseif area == NavConstants.Area.WATER then
        c = c * 1.5  -- Water is slower
    elseif area == NavConstants.Area.DANGER then
        c = c * 20.0  -- Avoid dangerous areas
    end

    -- BOUNDARY PENALTY: Penalize polygons that have boundary edges (walls/cliffs)
    -- This makes A* prefer interior paths over edge-hugging paths
    local baseB = (polyB - 1) * 6
    local nvB = tileB.pVertCount[polyB]
    local boundaryEdges = 0

    for e = 1, nvB do
        local nei = tileB.pNeis[baseB + e]
        if nei == 0 then
            -- This edge has no neighbor (wall/cliff/boundary)
            boundaryEdges = boundaryEdges + 1
        end
    end

    -- Apply penalty based on number of boundary edges
    if boundaryEdges > 0 then
        -- More boundary edges = higher penalty
        c = c * (1.0 + (boundaryEdges * (BOUNDARY_PENALTY - 1.0) / nvB))
    end

    return c
end

-- =========================
-- Off-Mesh Step Cost Calculation
-- =========================

-- Calculate cost for traversing an off-mesh connection
-- Parameters:
--   conn: off-mesh connection with startPos, endPos, radius, userId, flags
-- Returns: cost value (higher = less preferred)
local function step_cost_offmesh(conn)
    if not conn or not conn.startPos or not conn.endPos then
        return 1e30  -- Invalid connection
    end

    -- Base cost: 3D distance between start and end positions
    local baseDist = dist3D(
        conn.startPos.x, conn.startPos.y, conn.startPos.z,
        conn.endPos.x, conn.endPos.y, conn.endPos.z
    )

    -- Minimum distance to prevent zero-cost teleports
    if baseDist < 1.0 then
        baseDist = 1.0
    end

    -- Apply base off-mesh penalty (makes walkable paths preferred when available)
    local cost = baseDist * OFFMESH_BASE_PENALTY

    -- Apply connection type penalty based on userId
    -- userId encodes the connection type in navmesh generation
    local connType = conn.userId or OFFMESH_TYPE.WALK
    local typeCost = OFFMESH_TYPE_COST[connType]
    if typeCost then
        cost = cost * typeCost
    else
        -- Unknown type - apply moderate penalty (treat as jump)
        cost = cost * OFFMESH_TYPE_COST[OFFMESH_TYPE.JUMP]
    end

    -- Apply narrow connection penalty
    -- Narrow connections are harder to navigate and more risky
    local radius = conn.radius or 0.5
    if radius < OFFMESH_NARROW_RADIUS then
        cost = cost * OFFMESH_NARROW_PENALTY
    end

    return cost
end

-- =========================
-- A* Pathfinding
-- =========================

-- Find polygon path from start to goal
-- Returns: array of nodeIds, or nil + error message
function NavQuery:find_poly_path(startTileId, startPoly, endTileId, endPoly, maxExpansions)
    local world = self.world
    local heap = self.heap
    local seen, closed = self.seen, self.closed
    local g, f, parent = self.g, self.f, self.parent

    -- Increment search ID (avoids clearing arrays)
    self.searchId = self.searchId + 1
    local sid = self.searchId

    maxExpansions = maxExpansions or 200000  -- Increased for large TILE_STRIDE
    heap:clear()

    local startNode = node_id(startTileId, startPoly)
    local goalNode = node_id(endTileId, endPoly)

    -- Get tiles
    local startTile = world.tilesById[startTileId]
    local goalTile = world.tilesById[endTileId]

    if not startTile or not goalTile then
        return nil, "tiles_not_loaded"
    end

    -- Initialize start node
    g[startNode] = 0
    local h0 = dist2D(startTile.pCx[startPoly], startTile.pCy[startPoly],
                      goalTile.pCx[endPoly], goalTile.pCy[endPoly])
    f[startNode] = h0
    parent[startNode] = 0
    seen[startNode] = sid

    heap:push(startNode, f[startNode])

    local expansions = 0

    while heap:size() > 0 do
        local cur = heap:pop()

        -- Goal check
        if cur == goalNode then
            -- Reconstruct path
            local path = {}
            local n = cur
            while n ~= 0 do
                path[#path + 1] = n
                n = parent[n] or 0
            end
            -- Reverse path
            for i = 1, math.floor(#path / 2) do
                path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
            end
            return path, nil, expansions
        end

        -- Mark as closed
        closed[cur] = sid
        expansions = expansions + 1

        if expansions > maxExpansions then
            return nil, "expansion_cap", expansions
        end

        local curTileId, curPoly = decode_node(cur)
        local curTile = world.tilesById[curTileId]

        if not curTile then
            goto continue
        end

        -- Iterate neighbors
        local base = (curPoly - 1) * 6
        local nv = curTile.pVertCount[curPoly]

        for e = 1, nv do
            local nei = curTile.pNeis[base + e]

            if nei ~= 0 then
                local nTileId, nPoly

                if nei < 0x8000 then
                    -- Intra-tile neighbor
                    nTileId = curTileId
                    nPoly = nei
                else
                    -- Cross-tile neighbor (resolved by EdgeResolver)
                    nTileId = curTile.extToTile[base + e]
                    nPoly = curTile.extToPoly[base + e]
                end

                -- Skip unresolved external edges
                if nTileId ~= 0 and nPoly ~= 0 then
                    local nb = node_id(nTileId, nPoly)

                    -- Skip if already closed
                    if closed[nb] ~= sid then
                        local nTile = world.tilesById[nTileId]

                        if nTile then
                            local tentative = (g[cur] or 1e30) + step_cost(curTile, curPoly, nTile, nPoly)

                            if seen[nb] ~= sid or tentative < (g[nb] or 1e30) then
                                parent[nb] = cur
                                g[nb] = tentative

                                local hx = dist2D(nTile.pCx[nPoly], nTile.pCy[nPoly],
                                                 goalTile.pCx[endPoly], goalTile.pCy[endPoly])
                                local nf = tentative + hx
                                f[nb] = nf

                                if seen[nb] ~= sid then
                                    seen[nb] = sid
                                    heap:push(nb, nf)
                                else
                                    heap:decrease(nb, nf)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- =========================
        -- Off-Mesh Connection Expansion
        -- =========================
        -- Off-mesh polygons (jumps, teleports, etc.) connect via internal links (side=0xFF)
        -- rather than via edge neighbors. We check internal links to enable pathfinding
        -- across non-walkable transitions.
        -- ROOT CAUSE FIX: Only process internal links for actual off-mesh polygons
        -- Regular walkable polygons should NOT use internal links

        local internalLinks = {}
        if is_offmesh_poly(curTile, curPoly) then
            internalLinks = get_internal_links(curTile, curPoly)
        end
        for _, linkData in ipairs(internalLinks) do
            local nTileId = linkData.targetTileId
            local nPoly = linkData.targetPoly

            -- Internal links typically target the same tile
            -- If tileId is 0, use current tile
            if nTileId == 0 then
                nTileId = curTileId
            end

            local nTile = world.tilesById[nTileId]
            if nTile and nPoly > 0 and nPoly <= nTile.polyCount then
                local nb = node_id(nTileId, nPoly)

                -- Skip if already closed
                if closed[nb] ~= sid then
                    -- Get off-mesh connection data for cost calculation
                    local conn = get_offmesh_connection(curTile, curPoly)
                    local offmeshCost = nil
                    local skipLink = false

                    if conn and conn.startPos and conn.endPos then
                        -- Handle unidirectional connections
                        -- For unidirectional links, only allow traversal in the forward direction
                        -- (from start polygon to landing polygon)
                        if not conn.bidirectional then
                            -- Check if current polygon is the off-mesh polygon (the "source")
                            -- Only allow if we're at the off-mesh polygon going to the target
                            local curIsOffmesh = is_offmesh_link(curTile, curPoly)
                            if not curIsOffmesh then
                                -- Current is a regular polygon trying to enter the off-mesh
                                -- connection backwards - skip this link
                                skipLink = true
                            end
                        end

                        if not skipLink then
                            -- Calculate off-mesh cost using specialized function
                            -- Considers: 3D distance, connection type, radius penalties
                            offmeshCost = step_cost_offmesh(conn)
                        end
                    elseif not skipLink then
                        -- Fallback: use polygon center distance with base off-mesh penalty
                        -- This handles cases where connection data is missing
                        offmeshCost = step_cost(curTile, curPoly, nTile, nPoly)
                        if offmeshCost < 1e30 then
                            offmeshCost = offmeshCost * OFFMESH_BASE_PENALTY
                        end
                    end

                    if offmeshCost and offmeshCost < 1e30 then
                        local tentative = (g[cur] or 1e30) + offmeshCost

                        if seen[nb] ~= sid or tentative < (g[nb] or 1e30) then
                            parent[nb] = cur
                            g[nb] = tentative

                            local hx = dist2D(nTile.pCx[nPoly], nTile.pCy[nPoly],
                                             goalTile.pCx[endPoly], goalTile.pCy[endPoly])
                            local nf = tentative + hx
                            f[nb] = nf

                            if seen[nb] ~= sid then
                                seen[nb] = sid
                                heap:push(nb, nf)
                            else
                                heap:decrease(nb, nf)
                            end
                        end
                    end
                end
            end
        end

        ::continue::
    end

    return nil, "no_path", expansions
end

-- =========================
-- Portal / Shared Edge (FIX #2a: Use adjacency data from neis[])
-- =========================

-- Get the actual transition edge from polyA to polyB using adjacency data
-- This is deterministic and matches how the navmesh encodes adjacency
-- Returns: x0, y0, x1, y1 (edge endpoints in world coords, 2D only)
function NavQuery:get_transition_edge(tileAId, polyA, tileBId, polyB)
    local world = self.world
    local tileA = world.tilesById[tileAId]

    if not tileA then
        return nil
    end

    local baseA = (polyA - 1) * 6
    local nvA = tileA.pVertCount[polyA]

    -- Intra-tile: find edge where neis[e] == polyB
    if tileAId == tileBId then
        for e = 1, nvA do
            if tileA.pNeis[baseA + e] == polyB then
                local v0 = tileA.pVerts[baseA + e]
                local v1 = tileA.pVerts[baseA + (e % nvA) + 1]
                return tileA.vx[v0], tileA.vy[v0],
                       tileA.vx[v1], tileA.vy[v1]
            end
        end
        return nil
    end

    -- Cross-tile: find edge where extToTile/extToPoly match
    for e = 1, nvA do
        local idx = baseA + e
        if tileA.extToTile[idx] == tileBId and tileA.extToPoly[idx] == polyB then
            local v0 = tileA.pVerts[baseA + e]
            local v1 = tileA.pVerts[baseA + (e % nvA) + 1]
            return tileA.vx[v0], tileA.vy[v0],
                   tileA.vx[v1], tileA.vy[v1]
        end
    end

    return nil
end

-- =========================
-- Portal Ordering (FIX #2b: Use LOCAL corridor direction)
-- =========================

-- Order portal using LOCAL direction (previous waypoint/portal → portal midpoint)
-- NOT global direction (polygon center → polygon center) which can flip in curves
local function orderPortalLocal(prevX, prevY, portalMidX, portalMidY, x0, y0, x1, y1)
    local s0 = triArea2D(prevX, prevY, portalMidX, portalMidY, x0, y0)
    local s1 = triArea2D(prevX, prevY, portalMidX, portalMidY, x1, y1)

    -- More negative = more left (Detour convention)
    if s0 < s1 then
        return x0, y0, x1, y1  -- p0 is left, p1 is right
    else
        return x1, y1, x0, y0  -- p1 is left, p0 is right
    end
end

-- =========================
-- Clamp to Polygon (FIX #2c: Clamp start/end to corridor)
-- =========================

-- Find closest point on line segment (2D)
local function closest_point_on_segment(px, py, ax, ay, bx, by)
    local abx, aby = bx - ax, by - ay
    local apx, apy = px - ax, py - ay
    local ab2 = abx * abx + aby * aby
    if ab2 < 1e-12 then
        return ax, ay  -- Degenerate segment
    end
    local t = (apx * abx + apy * aby) / ab2
    t = math.max(0, math.min(1, t))
    return ax + t * abx, ay + t * aby
end

-- Clamp point to polygon boundary if outside (2D projection)
function NavQuery:clamp_to_poly(tileId, poly, x, y)
    local tile = self.world.tilesById[tileId]
    if not tile then return x, y end

    -- If point is inside polygon, return as-is
    if self:point_in_poly(tile, poly, x, y) then
        return x, y
    end

    -- Find closest point on polygon edges
    local base = (poly - 1) * 6
    local nv = tile.pVertCount[poly]
    local bestDist2 = 1e30
    local bestX, bestY = x, y

    for e = 1, nv do
        local v0 = tile.pVerts[base + e]
        local v1 = tile.pVerts[base + (e % nv) + 1]
        local ax, ay = tile.vx[v0], tile.vy[v0]
        local bx, by = tile.vx[v1], tile.vy[v1]

        local cx, cy = closest_point_on_segment(x, y, ax, ay, bx, by)
        local dx, dy = cx - x, cy - y
        local d2 = dx * dx + dy * dy

        if d2 < bestDist2 then
            bestDist2 = d2
            bestX, bestY = cx, cy
        end
    end

    return bestX, bestY
end

-- =========================
-- Funnel Algorithm (String Pulling)
-- =========================

-- Convert polygon path to smooth waypoints
-- polyPath: array of nodeIds from find_poly_path
-- Helper: Sample height from polygon's detail mesh with fallback
-- ownerIdx: index into polyPath (1-based), 0 means end waypoint
local function sample_wp_height(nav, polyPath, ownerIdx, x, y, prevZ)
    if ownerIdx == 0 then return nil end

    local function h_for(idx)
        if not polyPath[idx] then return nil end
        local tileId, poly = decode_node(polyPath[idx])
        local tile = nav.world.tilesById[tileId]
        if not tile then return nil end
        return nav:get_height_at(tile, poly, x, y)
    end

    -- Try owner polygon first
    local h1 = h_for(ownerIdx)
    if h1 then return h1 end

    -- Waypoint on portal edge: try previous polygon
    local h0 = h_for(ownerIdx - 1)
    if h0 then return h0 end

    return nil
end

-- =========================
-- Off-Mesh (Jump) Detection
-- =========================

-- Scan polygon path for off-mesh connection segments (jumps/teleports)
-- Returns array of {index, tileId, poly, conn} for each jump segment
function NavQuery:scan_for_offmesh(polyPath)
    local segments = {}
    for i = 1, #polyPath do
        local tileId, poly = decode_node(polyPath[i])
        local tile = self.world.tilesById[tileId]
        if tile and is_offmesh_poly(tile, poly) then
            local ci = tile.offMeshByPoly[poly]
            if ci then
                segments[#segments + 1] = {
                    index = i,
                    tileId = tileId,
                    poly = poly,
                    conn = tile.offMeshConnections[ci]
                }
            end
        end
    end
    return segments
end

-- =========================
-- Corridor Raycast & Visibility (Detour-style)
-- =========================

-- 2D cross product (used for half-plane tests)
local function cross2D(ax, ay, bx, by)
    return ax * by - ay * bx
end

-- Get polygon vertices in XY for a given tile/poly
-- Returns: array of {x, y}, vertex count
local function getPolyVertsXY(world, tileId, poly)
    local tile = world.tilesById[tileId]
    if not tile then return nil, 0 end

    local base = (poly - 1) * 6
    local nv = tile.pVertCount[poly]
    local verts = {}

    for i = 1, nv do
        local vi = tile.pVerts[base + i]
        verts[i] = {x = tile.vx[vi], y = tile.vy[vi]}
    end

    return verts, nv
end

-- Get neighbor polygon across edge e (returns polyRef or nil if boundary)
local function getNeighborAcrossEdge(world, tileId, poly, edgeIdx)
    local tile = world.tilesById[tileId]
    if not tile then return nil, nil end

    local base = (poly - 1) * 6
    local nei = tile.pNeis[base + edgeIdx]

    if nei == 0 then
        return nil, nil  -- Boundary edge (no neighbor)
    elseif nei >= 0x8000 then
        -- External edge (cross-tile)
        local extTile = tile.extToTile[base + edgeIdx]
        local extPoly = tile.extToPoly[base + edgeIdx]
        if extTile and extPoly then
            return extTile, extPoly
        end
        return nil, nil
    else
        -- Internal neighbor
        return tileId, nei
    end
end

-- Find where segment exits a convex polygon (2D in XY plane)
-- Assumes p0 is inside the polygon
-- Returns: tExit (0-1), exitEdge (1..n), or (1, nil) if stays inside
local EPS_RAYCAST = 1e-5

local function firstExitConvexPoly(verts, nv, p0x, p0y, p1x, p1y)
    local bestT = 1.0
    local bestE = nil

    for i = 1, nv do
        local a = verts[i]
        local b = verts[(i % nv) + 1]

        local ex = b.x - a.x
        local ey = b.y - a.y

        -- Signed distances to edge half-plane using cross(edge, point-a)
        -- For CCW polys, "inside" is cross >= 0 (left of each directed edge)
        local d0 = cross2D(ex, ey, p0x - a.x, p0y - a.y)
        local d1 = cross2D(ex, ey, p1x - a.x, p1y - a.y)

        if d1 < -EPS_RAYCAST then
            -- Segment endpoint is outside w.r.t. this edge
            if d0 < -EPS_RAYCAST then
                -- Start is outside too (shouldn't happen if p0 is inside)
                return 0.0, i
            end

            -- Intersection parameter where we cross this edge plane
            local denom = d0 - d1
            if math.abs(denom) > EPS_RAYCAST then
                local t = d0 / denom
                if t < bestT then
                    bestT = t
                    bestE = i
                end
            end
        end
    end

    return bestT, bestE
end

-- Corridor-limited raycast: checks if segment A→B stays within corridor
-- Returns: visible (bool), hitT (0-1), hitPolyIdx, hitEdge
local function raycastCorridor(Ax, Ay, Bx, By, polyPath, startIdx, endIdx, world)
    local px, py = Ax, Ay

    for k = startIdx, endIdx do
        local tileId, poly = decode_node(polyPath[k])
        local verts, nv = getPolyVertsXY(world, tileId, poly)

        if not verts then
            return false, 0, k, nil
        end

        local tExit, eExit = firstExitConvexPoly(verts, nv, px, py, Bx, By)

        if not eExit then
            -- Segment endpoint lies in this poly (never exits)
            if k == endIdx then
                return true, 1.0, nil, nil  -- Visible!
            end
            -- Expected to reach later polys but didn't exit - treat as failure
            return false, 1.0, k, nil
        end

        if k == endIdx then
            -- We're at target poly, segment stays inside or exits at boundary
            return true, 1.0, nil, nil
        end

        -- Check if exit edge leads to next corridor polygon
        local nextTileId, nextPoly = decode_node(polyPath[k + 1])
        local neiTileId, neiPoly = getNeighborAcrossEdge(world, tileId, poly, eExit)

        if neiTileId ~= nextTileId or neiPoly ~= nextPoly then
            -- Exiting through wrong edge (not the portal to next poly)
            return false, tExit, k, eExit
        end

        -- Step a tiny bit past the boundary
        local tStep = math.min(1.0, tExit + 1e-4)
        px = Ax + (Bx - Ax) * tStep
        py = Ay + (By - Ay) * tStep
    end

    return true, 1.0, nil, nil
end

-- Get polygon center XY
local function getPolyCenterXY(world, nodeId)
    local tileId, poly = decode_node(nodeId)
    local tile = world.tilesById[tileId]
    if tile then
        return tile.pCx[poly], tile.pCy[poly], tile.pCz[poly]
    end
    return nil, nil, nil
end

-- Debug logging for path analysis
local PATH_DEBUG_LOG = "LX_Nav_path_analysis.log"
local PATH_DEBUG_ENABLED = false  -- DISABLED: causes 1+ second freeze when enabled

local function logPathDebug(msg)
    if PATH_DEBUG_ENABLED then
        core.write_log_file(PATH_DEBUG_LOG, msg .. "\n")
    end
end

local function logPolygonData(world, polyPath)
    logPathDebug("=== POLYGON PATH DATA ===")
    logPathDebug(string.format("Total polygons in path: %d", #polyPath))

    for i = 1, #polyPath do
        local tileId, poly = decode_node(polyPath[i])
        local tile = world.tilesById[tileId]

        if tile then
            local base = (poly - 1) * 6
            local nv = tile.pVertCount[poly]
            local cx, cy, cz = tile.pCx[poly], tile.pCy[poly], tile.pCz[poly]

            logPathDebug(string.format("\n[Poly %d] tile=%d, poly=%d, center=(%.2f, %.2f, %.2f), verts=%d",
                i, tileId, poly, cx or 0, cy or 0, cz or 0, nv or 0))

            -- Log vertices
            for v = 1, (nv or 0) do
                local vi = tile.pVerts[base + v]
                if vi then
                    local vx, vy = tile.vx[vi], tile.vy[vi]
                    logPathDebug(string.format("  vert[%d]: idx=%d, pos=(%.2f, %.2f)", v, vi, vx or 0, vy or 0))
                end
            end

            -- Log neighbors
            for e = 1, (nv or 0) do
                local nei = tile.pNeis[base + e]
                local neiStr = "boundary"
                if nei and nei > 0 then
                    if nei >= 0x8000 then
                        local extTile = tile.extToTile[base + e]
                        local extPoly = tile.extToPoly[base + e]
                        neiStr = string.format("external(tile=%s, poly=%s)", tostring(extTile), tostring(extPoly))
                    else
                        neiStr = string.format("internal(poly=%d)", nei)
                    end
                end
                logPathDebug(string.format("  edge[%d]: nei=%s (raw=%s)", e, neiStr, tostring(nei)))
            end
        else
            logPathDebug(string.format("\n[Poly %d] tile=%d, poly=%d - TILE NOT LOADED", i, tileId, poly))
        end
    end
    logPathDebug("")
end

-- =========================
-- Portal Steering (Research-based optimal waypoint placement)
-- =========================

-- Find the optimal steering point on a portal edge
-- Maximizes progress toward goal while staying on the portal
-- Shrinks portal inward to keep distance from walls at endpoints
local PORTAL_SHRINK = 3.0  -- yards - shrink portal endpoints inward

local function steerPointOnPortal(curr, goal, portalA, portalB, w)
    w = w or 0.5  -- Weight for deviation penalty

    local function dot(ax, ay, bx, by) return ax * bx + ay * by end
    local function len(ax, ay) return math.sqrt(ax * ax + ay * ay) end

    -- Shrink the portal inward to avoid placing waypoints at wall-adjacent endpoints
    local edgeX = portalB.x - portalA.x
    local edgeY = portalB.y - portalA.y
    local edgeLen = len(edgeX, edgeY)

    local shrinkA, shrinkB = portalA, portalB
    if edgeLen > PORTAL_SHRINK * 2.5 then
        -- Shrink both endpoints inward
        local shrinkT = PORTAL_SHRINK / edgeLen
        shrinkA = {x = portalA.x + edgeX * shrinkT, y = portalA.y + edgeY * shrinkT}
        shrinkB = {x = portalB.x - edgeX * shrinkT, y = portalB.y - edgeY * shrinkT}
    elseif edgeLen > 1.0 then
        -- Portal too small to shrink fully - just use midpoint region
        shrinkA = {x = portalA.x + edgeX * 0.3, y = portalA.y + edgeY * 0.3}
        shrinkB = {x = portalB.x - edgeX * 0.3, y = portalB.y - edgeY * 0.3}
    end

    -- Direction to goal
    local dx, dy = goal.x - curr.x, goal.y - curr.y
    local dl = len(dx, dy)
    if dl < 1e-6 then
        return {x = (shrinkA.x + shrinkB.x) * 0.5, y = (shrinkA.y + shrinkB.y) * 0.5}
    end
    dx, dy = dx / dl, dy / dl

    -- Distance from point to infinite line through curr->goal
    local function distPointToLine(p)
        local nx, ny = -dy, dx  -- Line normal
        return math.abs((p.x - curr.x) * nx + (p.y - curr.y) * ny)
    end

    -- Find point on segment AB closest to the line curr->goal
    local function closestPointOnSegmentToLine(a, b)
        local nx, ny = -dy, dx  -- Line normal
        local function signedDist(p)
            return (p.x - curr.x) * nx + (p.y - curr.y) * ny
        end
        local da = signedDist(a)
        local db = signedDist(b)
        if da == 0 then return {x = a.x, y = a.y} end
        if db == 0 then return {x = b.x, y = b.y} end
        if da * db < 0 then
            -- Line crosses segment - find intersection
            local t = da / (da - db)
            return {x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t}
        end
        -- No crossing; return closer endpoint
        if math.abs(da) < math.abs(db) then
            return {x = a.x, y = a.y}
        else
            return {x = b.x, y = b.y}
        end
    end

    -- Candidate points on the SHRUNK portal (away from wall endpoints)
    local A = shrinkA
    local B = shrinkB
    local M = {x = (A.x + B.x) * 0.5, y = (A.y + B.y) * 0.5}  -- Midpoint
    local Q = closestPointOnSegmentToLine(A, B)  -- Closest to goal line

    local candidates = {A, B, M, Q}

    -- Score each candidate: progress toward goal minus deviation penalty
    local bestP = M  -- Default to midpoint
    local bestScore = -1e30

    for _, p in ipairs(candidates) do
        local vx, vy = p.x - curr.x, p.y - curr.y
        local progress = dot(vx, vy, dx, dy)
        local deviation = distPointToLine(p)
        local score = progress - w * deviation

        if score > bestScore then
            bestScore = score
            bestP = p
        end
    end

    return bestP
end

-- Get portal edge endpoints between two adjacent polygons in the corridor
-- Uses travel direction to determine left/right ordering (winding-agnostic)
-- Returns: left {x,y,z}, right {x,y,z} or nil, nil if not found
local function getPortalEndpoints(polyPath, fromIdx, toIdx, world, dirX, dirY)
    if fromIdx < 1 or toIdx > #polyPath then
        return nil, nil
    end

    local tileAId, polyA = decode_node(polyPath[fromIdx])
    local tileBId, polyB = decode_node(polyPath[toIdx])
    local tileA = world.tilesById[tileAId]

    if not tileA then
        return nil, nil
    end

    local baseA = (polyA - 1) * 6
    local nvA = tileA.pVertCount[polyA]

    -- Find the edge connecting polyA to polyB
    local x0, y0, z0, x1, y1, z1

    if tileAId == tileBId then
        -- Intra-tile: find edge where neis[e] == polyB
        for e = 1, nvA do
            if tileA.pNeis[baseA + e] == polyB then
                local v0 = tileA.pVerts[baseA + e]
                local v1 = tileA.pVerts[baseA + (e % nvA) + 1]
                x0, y0, z0 = tileA.vx[v0], tileA.vy[v0], tileA.vz[v0]
                x1, y1, z1 = tileA.vx[v1], tileA.vy[v1], tileA.vz[v1]
                break
            end
        end
    else
        -- Cross-tile: find edge where extToTile/extToPoly match
        for e = 1, nvA do
            local idx = baseA + e
            if tileA.extToTile[idx] == tileBId and tileA.extToPoly[idx] == polyB then
                local v0 = tileA.pVerts[baseA + e]
                local v1 = tileA.pVerts[baseA + (e % nvA) + 1]
                x0, y0, z0 = tileA.vx[v0], tileA.vy[v0], tileA.vz[v0]
                x1, y1, z1 = tileA.vx[v1], tileA.vy[v1], tileA.vz[v1]
                break
            end
        end
    end

    if not x0 then
        return nil, nil
    end

    -- Use travel direction to determine left/right (winding-agnostic)
    return orderPortalLeftRight(x0, y0, z0 or 0, x1, y1, z1 or 0, dirX, dirY)
end

-- Build portal sequence for funnel algorithm
-- Returns: portalsL[], portalsR[] (left and right endpoints for each portal)
local function getPathPortals(polyPath, startPos, endPos, world)
    local portalsL = {}
    local portalsR = {}

    -- First portal: start position (apex)
    portalsL[1] = {x = startPos.x, y = startPos.y, z = startPos.z}
    portalsR[1] = {x = startPos.x, y = startPos.y, z = startPos.z}

    -- Get portal for each pair of consecutive polygons
    for i = 1, #polyPath - 1 do
        -- Compute travel direction from poly i center to poly i+1 center
        local tileIdA, polyA = decode_node(polyPath[i])
        local tileIdB, polyB = decode_node(polyPath[i + 1])
        local tileA = world.tilesById[tileIdA]
        local tileB = world.tilesById[tileIdB]

        if tileA and tileB then
            local fromX, fromY = tileA.pCx[polyA], tileA.pCy[polyA]
            local toX, toY = tileB.pCx[polyB], tileB.pCy[polyB]
            local dirX, dirY = toX - fromX, toY - fromY

            local left, right = getPortalEndpoints(polyPath, i, i + 1, world, dirX, dirY)
            if left and right then
                portalsL[#portalsL + 1] = left
                portalsR[#portalsR + 1] = right
            end
        end
    end

    -- Last portal: end position
    portalsL[#portalsL + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
    portalsR[#portalsR + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}

    return portalsL, portalsR
end

-- Funnel algorithm (string-pulling) for path smoothing
-- Takes portal left/right arrays, returns smoothed waypoint list
local function stringPull(portalsL, portalsR)
    local pts = {}
    pts[1] = {x = portalsL[1].x, y = portalsL[1].y, z = portalsL[1].z}

    local apexIndex = 1
    local leftIndex = 1
    local rightIndex = 1

    local portalApex = portalsL[1]
    local portalLeft = portalsL[1]
    local portalRight = portalsR[1]

    local i = 2
    while i <= #portalsL do
        local left = portalsL[i]
        local right = portalsR[i]

        -- Update right side of funnel
        if triArea2D(portalApex.x, portalApex.y, portalRight.x, portalRight.y, right.x, right.y) <= 0 then
            if veq2(portalApex.x, portalApex.y, portalRight.x, portalRight.y) or
               triArea2D(portalApex.x, portalApex.y, portalLeft.x, portalLeft.y, right.x, right.y) > 0 then
                -- Tighten right
                portalRight = right
                rightIndex = i
            else
                -- Right crosses left - emit left vertex and restart
                pts[#pts + 1] = {x = portalLeft.x, y = portalLeft.y, z = portalLeft.z}
                -- Check if we just added the final portal (destination)
                local endPortal = portalsL[#portalsL]
                if math.abs(portalLeft.x - endPortal.x) < 0.001 and
                   math.abs(portalLeft.y - endPortal.y) < 0.001 then
                    return pts  -- Reached destination, stop
                end
                portalApex = portalLeft
                apexIndex = leftIndex
                portalLeft = portalApex
                portalRight = portalApex
                leftIndex = apexIndex
                rightIndex = apexIndex
                i = apexIndex  -- Restart from apex
            end
        end

        -- Update left side of funnel
        if triArea2D(portalApex.x, portalApex.y, portalLeft.x, portalLeft.y, left.x, left.y) >= 0 then
            if veq2(portalApex.x, portalApex.y, portalLeft.x, portalLeft.y) or
               triArea2D(portalApex.x, portalApex.y, portalRight.x, portalRight.y, left.x, left.y) < 0 then
                -- Tighten left
                portalLeft = left
                leftIndex = i
            else
                -- Left crosses right - emit right vertex and restart
                pts[#pts + 1] = {x = portalRight.x, y = portalRight.y, z = portalRight.z}
                -- Check if we just added the final portal (destination)
                local endPortal = portalsL[#portalsL]
                if math.abs(portalRight.x - endPortal.x) < 0.001 and
                   math.abs(portalRight.y - endPortal.y) < 0.001 then
                    return pts  -- Reached destination, stop
                end
                portalApex = portalRight
                apexIndex = rightIndex
                portalLeft = portalApex
                portalRight = portalApex
                leftIndex = apexIndex
                rightIndex = apexIndex
                i = apexIndex  -- Restart from apex
            end
        end

        i = i + 1
    end

    -- Add end point (only if not already added)
    local lastL = portalsL[#portalsL]
    local lastPt = pts[#pts]
    if not lastPt or math.abs(lastPt.x - lastL.x) > 0.001 or math.abs(lastPt.y - lastL.y) > 0.001 then
        pts[#pts + 1] = {x = lastL.x, y = lastL.y, z = lastL.z}
    end

    return pts
end

-- Validate waypoint slopes - returns false if path has too-steep segments
-- This catches cliff transitions that A* missed (polygon center averaging)
local function validateWaypointSlopes(waypoints)
    if #waypoints < 2 then return true end

    for i = 1, #waypoints - 1 do
        local a = waypoints[i]
        local b = waypoints[i + 1]

        local dx, dy = b.x - a.x, b.y - a.y
        local xyDist = math.sqrt(dx * dx + dy * dy)

        if xyDist > 0.5 then  -- Only check if there's horizontal movement
            local dz = (b.z or 0) - (a.z or 0)
            local slope = math.abs(dz) / xyDist

            if slope > MAX_WAYPOINT_SLOPE then
                -- Too steep - this path goes over a cliff
                return false, i, slope
            end
        end
    end

    return true
end

-- Portal-based path straightening (research-based optimal algorithm)
-- Places waypoints on portal edges, not polygon centers
local function straightenPathGreedy(polyPath, startPos, endPos, world)
    -- Initialize debug log
    if PATH_DEBUG_ENABLED then
        core.create_log_file(PATH_DEBUG_LOG)
        logPathDebug("=== PORTAL-BASED PATH STRAIGHTENING ===")
        logPathDebug(string.format("Start: (%.2f, %.2f, %.2f)", startPos.x, startPos.y, startPos.z))
        logPathDebug(string.format("End: (%.2f, %.2f, %.2f)", endPos.x, endPos.y, endPos.z))
        logPathDebug(string.format("Polygon path length: %d", #polyPath))
        logPolygonData(world, polyPath)
    end

    if #polyPath == 0 then
        logPathDebug("Empty polyPath, returning direct line to end")
        return {{x = endPos.x, y = endPos.y, z = endPos.z}}
    end

    if #polyPath == 1 then
        logPathDebug("Single polygon, returning start->end")
        return {
            {x = startPos.x, y = startPos.y, z = startPos.z},
            {x = endPos.x, y = endPos.y, z = endPos.z}
        }
    end

    local waypoints = {}
    local owners = {}
    waypoints[1] = {x = startPos.x, y = startPos.y, z = startPos.z}
    owners[1] = 1  -- Start owned by first polygon

    local i = 1  -- Current corridor index
    local iteration = 0
    local maxIterations = #polyPath + 5  -- Safety limit

    while i < #polyPath and iteration < maxIterations do
        iteration = iteration + 1
        local curr = waypoints[#waypoints]

        logPathDebug(string.format("\n--- Iteration %d: at corridor index %d, pos=(%.2f, %.2f) ---",
            iteration, i, curr.x, curr.y))

        -- Try to go directly to end through entire remaining corridor
        local visible, hitT, hitK, hitEdge = raycastCorridor(
            curr.x, curr.y, endPos.x, endPos.y,
            polyPath, i, #polyPath, world
        )

        logPathDebug(string.format("Raycast to END: visible=%s, hitK=%s, hitEdge=%s, hitT=%.3f",
            tostring(visible), tostring(hitK), tostring(hitEdge), hitT or 0))

        if visible then
            -- Direct line to end is clear!
            waypoints[#waypoints + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
            owners[#owners + 1] = #polyPath  -- End owned by last polygon
            logPathDebug("Direct path to END is clear - adding final waypoint")
            break
        end

        -- Blocked at corridor index hitK
        -- Steer to the NEXT portal (hitK -> hitK+1)
        local k = hitK or i
        if k >= #polyPath then
            -- Safety fallback - just go to end
            waypoints[#waypoints + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
            owners[#owners + 1] = #polyPath  -- End owned by last polygon
            logPathDebug("k >= #polyPath, adding end as fallback")
            break
        end

        -- Get the portal between poly[k] and poly[k+1]
        local portalA, portalB = getPortalEndpoints(polyPath, k, k + 1, world)

        if not portalA then
            -- Fallback: use polygon center (shouldn't happen with valid corridor)
            local cx, cy, cz = getPolyCenterXY(world, polyPath[k + 1])
            if cx then
                waypoints[#waypoints + 1] = {x = cx, y = cy, z = cz or startPos.z}
                owners[#owners + 1] = k + 1  -- Owned by polygon we're entering
                logPathDebug(string.format("No portal found, using poly center: (%.2f, %.2f)", cx, cy))
            end
            i = k + 1
        else
            -- Find optimal steering point on the portal
            local steerPt = steerPointOnPortal(curr, endPos, portalA, portalB, 0.5)

            -- Z will be fixed by fixWaypointHeights (placeholder for now)
            waypoints[#waypoints + 1] = {x = steerPt.x, y = steerPt.y, z = curr.z}
            owners[#owners + 1] = k + 1  -- Owned by polygon we're entering

            logPathDebug(string.format("Portal k=%d: A=(%.2f,%.2f) B=(%.2f,%.2f)", k, portalA.x, portalA.y, portalB.x, portalB.y))
            logPathDebug(string.format("Steer point: (%.2f, %.2f) owner=%d", steerPt.x, steerPt.y, k + 1))

            i = k + 1
        end
    end

    -- Ensure we end at endPos
    local lastWp = waypoints[#waypoints]
    if math.abs(lastWp.x - endPos.x) > 0.1 or math.abs(lastWp.y - endPos.y) > 0.1 then
        waypoints[#waypoints + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
        owners[#owners + 1] = #polyPath  -- End owned by last polygon
        logPathDebug("Added final endpoint")
    end

    logPathDebug(string.format("\n=== FINAL PATH: %d waypoints, %d owners ===", #waypoints, #owners))
    for wi, wp in ipairs(waypoints) do
        logPathDebug(string.format("WP[%d]: (%.2f, %.2f, %.2f) owner=%d", wi, wp.x, wp.y, wp.z, owners[wi] or 0))
    end

    return waypoints, owners
end

-- Safe distance: find distance to nearest boundary edge and push waypoint away
local SAFE_DISTANCE = 5.0  -- yards - keep waypoints this far from walls/cliffs

local function findDistanceToWall(world, tileId, poly, px, py)
    local tile = world.tilesById[tileId]
    if not tile then return math.huge, 0, 0 end

    local base = (poly - 1) * 6
    local nv = tile.pVertCount[poly]

    local minDist = math.huge
    local wallNx, wallNy = 0, 0

    for i = 1, nv do
        local nei = tile.pNeis[base + i]

        -- Check if this is a boundary edge (no neighbor or external)
        local isBoundary = (nei == 0) or (nei >= 0x8000 and not tile.extToTile[base + i])

        if isBoundary then
            local vi = tile.pVerts[base + i]
            local vj = tile.pVerts[base + (i % nv) + 1]
            local ax, ay = tile.vx[vi], tile.vy[vi]
            local bx, by = tile.vx[vj], tile.vy[vj]

            -- Find closest point on edge
            local cx, cy, distSq = closest_pt_seg2d(px, py, ax, ay, bx, by)
            local dist = math.sqrt(distSq)

            if dist < minDist then
                minDist = dist
                -- Normal pointing inward (perpendicular to edge, towards poly interior)
                local ex, ey = bx - ax, by - ay
                local len = math.sqrt(ex * ex + ey * ey)
                if len > 0 then
                    -- Rotate 90 degrees CCW for inward normal (assuming CCW winding)
                    wallNx, wallNy = -ey / len, ex / len
                end
            end
        end
    end

    return minDist, wallNx, wallNy
end

-- =========================
-- Corridor Follower (Research-based human-like paths)
-- =========================

-- Configuration for corridor follower
local CORRIDOR_CONFIG = {
    step_length = 0.8,           -- Step size in yards (0.6-1.0 recommended)
    desired_clearance = 1.5,     -- Desired distance from walls (yards) - reduced from 2.0
    wall_query_radius = 3.0,     -- How far to look for walls - reduced from 4.0
    repulsion_gain = 0.6,        -- Wall repulsion strength - reduced from 1.2 to prevent oscillation
    lookahead_corners = 3,       -- How many corners ahead to consider
    max_turn_per_step = 45,      -- Max heading change per step (degrees) - increased from 35
    min_waypoint_spacing = 0.5,  -- Minimum distance between output waypoints
}

-- Simple function to get portal midpoints along corridor (more reliable than visibility-based)
local function getPortalMidpoints(polyPath, startPos, endPos, world)
    local steerTargets = {}
    local owners = {}

    -- Start position
    steerTargets[1] = {x = startPos.x, y = startPos.y, z = startPos.z}
    owners[1] = 1

    -- Get midpoint of each portal between consecutive polygons
    for i = 1, #polyPath - 1 do
        local portalA, portalB = getPortalEndpoints(polyPath, i, i + 1, world)
        if portalA and portalB then
            -- Use shrunk midpoint (away from walls)
            local edgeX = portalB.x - portalA.x
            local edgeY = portalB.y - portalA.y
            local edgeLen = math.sqrt(edgeX * edgeX + edgeY * edgeY)

            local midX, midY
            if edgeLen > PORTAL_SHRINK * 2.5 then
                -- Use midpoint of shrunk portal
                local shrinkT = PORTAL_SHRINK / edgeLen
                local shrinkA = {x = portalA.x + edgeX * shrinkT, y = portalA.y + edgeY * shrinkT}
                local shrinkB = {x = portalB.x - edgeX * shrinkT, y = portalB.y - edgeY * shrinkT}
                midX = (shrinkA.x + shrinkB.x) * 0.5
                midY = (shrinkA.y + shrinkB.y) * 0.5
            else
                -- Portal too small, use simple midpoint
                midX = (portalA.x + portalB.x) * 0.5
                midY = (portalA.y + portalB.y) * 0.5
            end

            steerTargets[#steerTargets + 1] = {x = midX, y = midY, z = startPos.z}
            owners[#owners + 1] = i + 1
        end
    end

    -- End position
    steerTargets[#steerTargets + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
    owners[#owners + 1] = #polyPath

    return steerTargets, owners
end

-- Distance to nearest wall in corridor (Detour-style)
-- Returns: dist, normalX, normalY (normal points AWAY from wall)
local function distance_to_wall_in_corridor(world, polyPath, curIndex, px, py, radius)
    local bestDist = radius
    local bestNx, bestNy = 0, 0

    -- Examine current poly and a few ahead/behind in corridor
    local fromIdx = math.max(1, curIndex - 2)
    local toIdx = math.min(#polyPath, curIndex + 4)

    for i = fromIdx, toIdx do
        local tileId, poly = decode_node(polyPath[i])
        local tile = world.tilesById[tileId]
        if not tile then goto continue_poly end

        local base = (poly - 1) * 6
        local nv = tile.pVertCount[poly]

        for e = 1, nv do
            local nei = tile.pNeis[base + e]

            -- Boundary edge: no neighbor (wall) or unresolved external
            local isWall = (nei == 0)
            if nei >= 0x8000 then
                local extTile = tile.extToTile and tile.extToTile[base + e]
                isWall = not extTile or extTile == 0
            end

            if isWall then
                local vi = tile.pVerts[base + e]
                local vj = tile.pVerts[base + (e % nv) + 1]
                local ax, ay = tile.vx[vi], tile.vy[vi]
                local bx, by = tile.vx[vj], tile.vy[vj]

                -- Closest point on edge segment
                local cx, cy, distSq = closest_pt_seg2d(px, py, ax, ay, bx, by)
                local dist = math.sqrt(distSq)

                if dist < bestDist and dist > 1e-6 then
                    bestDist = dist
                    -- Normal pointing from wall toward point (away from wall)
                    bestNx = (px - cx) / dist
                    bestNy = (py - cy) / dist
                end
            end
        end

        ::continue_poly::
    end

    return bestDist, bestNx, bestNy
end

-- Find which corridor polygon contains a point (for corridor index tracking)
local function find_corridor_index(world, polyPath, fromIdx, px, py, nq)
    -- Search forward from current index
    for i = fromIdx, math.min(#polyPath, fromIdx + 5) do
        local tileId, poly = decode_node(polyPath[i])
        local tile = world.tilesById[tileId]
        if tile and nq:point_in_poly(tile, poly, px, py) then
            return i
        end
    end
    -- Search backward if not found
    for i = fromIdx - 1, math.max(1, fromIdx - 3), -1 do
        local tileId, poly = decode_node(polyPath[i])
        local tile = world.tilesById[tileId]
        if tile and nq:point_in_poly(tile, poly, px, py) then
            return i
        end
    end
    return fromIdx  -- Keep current if not found
end

-- Corridor follower: generates smooth path using proper funnel algorithm
-- Uses getPathPortals + stringPull for optimal path smoothing
local function corridor_follower(polyPath, startPos, endPos, world, nq)
    if #polyPath == 0 then
        return {{x = endPos.x, y = endPos.y, z = endPos.z}}, {1}
    end

    if #polyPath == 1 then
        return {
            {x = startPos.x, y = startPos.y, z = startPos.z},
            {x = endPos.x, y = endPos.y, z = endPos.z}
        }, {1, 1}
    end

    -- Build portal sequence with correct left/right ordering
    local portalsL, portalsR = getPathPortals(polyPath, startPos, endPos, world)

    -- Flush order debug log
    flushOrderDebug()

    -- TEST: Log portal data for verification
    core.create_log_file("LX_Nav_funnel_test.log")
    local testLog = string.format("=== FUNNEL TEST ===\nPolygons: %d, Portals: %d\n\n", #polyPath, #portalsL)
    for i = 1, math.min(10, #portalsL) do
        local l, r = portalsL[i], portalsR[i]
        testLog = testLog .. string.format("Portal %d: L=(%.1f,%.1f) R=(%.1f,%.1f)\n",
            i, l.x, l.y, r.x, r.y)
    end

    -- Run funnel algorithm (string-pulling)
    local waypoints = stringPull(portalsL, portalsR)

    -- Remove backwards waypoints (WP[2] that goes opposite to destination)
    if waypoints and #waypoints >= 3 then
        local wp1 = waypoints[1]
        local wp2 = waypoints[2]
        local wpLast = waypoints[#waypoints]

        -- Direction from start to destination
        local dx_dest = wpLast.x - wp1.x
        local dy_dest = wpLast.y - wp1.y

        -- Direction from start to WP[2]
        local dx_wp2 = wp2.x - wp1.x
        local dy_wp2 = wp2.y - wp1.y

        -- Dot product: if negative, WP[2] is backwards
        local dot = dx_dest * dx_wp2 + dy_dest * dy_wp2

        if dot < 0 then
            -- WP[2] is backwards, remove it
            table.remove(waypoints, 2)
        end
    end

    -- Validate slopes - reject paths that go over cliffs
    local valid, failIdx, failSlope = validateWaypointSlopes(waypoints)
    if not valid then
        testLog = testLog .. string.format("\nPATH REJECTED: Too steep at WP[%d]->WP[%d], slope=%.2f (max=%.2f)\n",
            failIdx, failIdx + 1, failSlope, MAX_WAYPOINT_SLOPE)
        core.write_log_file("LX_Nav_funnel_test.log", testLog)
        return nil, nil  -- Path rejected due to cliff
    end

    -- Generate owners: map each waypoint to a polygon index
    -- For funnel output, approximate based on position in corridor
    local owners = {}
    for i = 1, #waypoints do
        -- Simple approximation: distribute evenly across corridor
        owners[i] = math.max(1, math.min(#polyPath, math.ceil(i / #waypoints * #polyPath)))
    end
    owners[1] = 1  -- First waypoint is at start polygon
    owners[#owners] = #polyPath  -- Last waypoint is at end polygon

    testLog = testLog .. string.format("\nWaypoints: %d\n", #waypoints)
    for i = 1, math.min(10, #waypoints) do
        local wp = waypoints[i]
        testLog = testLog .. string.format("  WP[%d]: (%.1f, %.1f, %.1f) owner=%d\n",
            i, wp.x, wp.y, wp.z or 0, owners[i])
    end
    core.write_log_file("LX_Nav_funnel_test.log", testLog)

    return waypoints, owners
end

-- Simple safe distance: just push away from the nearest boundary edge
local function applySafeDistance(waypoints, polyPath, world)
    local MIN_DIST = 3.0  -- Minimum distance from walls

    for idx = 2, #waypoints - 1 do  -- Skip start and end
        local wp = waypoints[idx]
        local nearestDist = math.huge
        local nearestPushX, nearestPushY = 0, 0

        -- Find the single nearest boundary edge
        for i = 1, #polyPath do
            local tileId, poly = decode_node(polyPath[i])
            local tile = world.tilesById[tileId]
            if not tile then goto continue_poly end

            local base = (poly - 1) * 6
            local nv = tile.pVertCount[poly]

            for e = 1, nv do
                local nei = tile.pNeis[base + e]

                if nei == 0 then  -- Boundary edge
                    local vi = tile.pVerts[base + e]
                    local vj = tile.pVerts[base + (e % nv) + 1]
                    local ax, ay = tile.vx[vi], tile.vy[vi]
                    local bx, by = tile.vx[vj], tile.vy[vj]

                    local cx, cy, distSq = closest_pt_seg2d(wp.x, wp.y, ax, ay, bx, by)
                    local dist = math.sqrt(distSq)

                    if dist < nearestDist and dist > 0.1 then
                        nearestDist = dist
                        nearestPushX = (wp.x - cx) / dist
                        nearestPushY = (wp.y - cy) / dist
                    end
                end
            end
            ::continue_poly::
        end

        -- Only push if too close to nearest boundary
        if nearestDist < MIN_DIST then
            local pushAmount = MIN_DIST - nearestDist
            wp.x = wp.x + nearestPushX * pushAmount
            wp.y = wp.y + nearestPushY * pushAmount
        end
    end

    return waypoints
end

-- Repair waypoint ownership if it was pushed outside its original owner polygon
-- Only searches within ±2 corridor positions to avoid wrong-floor selection
local function repairOwnerInCorridor(world, polyPath, ownerIdx, x, y, nq, radius)
    radius = radius or 2
    local from = math.max(1, ownerIdx - radius)
    local to = math.min(#polyPath, ownerIdx + radius)

    -- First check if still inside current owner
    local currTileId, currPoly = decode_node(polyPath[ownerIdx])
    local currTile = world.tilesById[currTileId]
    if currTile and nq:point_in_poly(currTile, currPoly, x, y) then
        return ownerIdx  -- Still inside, no repair needed
    end

    -- Search nearby corridor polygons
    for k = from, to do
        if k ~= ownerIdx then
            local tileId, poly = decode_node(polyPath[k])
            local tile = world.tilesById[tileId]
            if tile and nq:point_in_poly(tile, poly, x, y) then
                return k  -- Found containing polygon
            end
        end
    end

    return ownerIdx  -- No better match found, keep original
end

-- Get vertex position for detail triangle
-- If vertIdx < polyVertCount: use main polygon vertex
-- If vertIdx >= polyVertCount: use detail vertex at vertBase + (vertIdx - polyVertCount)
local function get_detail_vert(tile, poly, vertIdx)
    local base = (poly - 1) * 6
    local nv = tile.pVertCount[poly]

    if vertIdx < nv then
        -- Main polygon vertex
        local vi = tile.pVerts[base + vertIdx + 1]
        return tile.vx[vi], tile.vy[vi], tile.vz[vi]
    else
        -- Detail vertex
        local detail = tile.detailMeshes and tile.detailMeshes[poly]
        if detail then
            local di = detail.vertBase + (vertIdx - nv) + 1  -- +1 for Lua 1-based
            return tile.detailVx[di], tile.detailVy[di], tile.detailVz[di]
        end
    end
    return nil, nil, nil
end

-- Check if point (px, py) is inside triangle (ax,ay), (bx,by), (cx,cy) in 2D
-- Returns true and barycentric coords (u, v, w) if inside
local function point_in_triangle_2d(px, py, ax, ay, bx, by, cx, cy)
    local v0x, v0y = cx - ax, cy - ay
    local v1x, v1y = bx - ax, by - ay
    local v2x, v2y = px - ax, py - ay

    local dot00 = v0x * v0x + v0y * v0y
    local dot01 = v0x * v1x + v0y * v1y
    local dot02 = v0x * v2x + v0y * v2y
    local dot11 = v1x * v1x + v1y * v1y
    local dot12 = v1x * v2x + v1y * v2y

    local denom = dot00 * dot11 - dot01 * dot01
    if math.abs(denom) < 1e-10 then return false end

    local invDenom = 1 / denom
    local u = (dot11 * dot02 - dot01 * dot12) * invDenom
    local v = (dot00 * dot12 - dot01 * dot02) * invDenom

    if u >= 0 and v >= 0 and (u + v) <= 1 then
        local w = 1 - u - v
        return true, w, v, u  -- Barycentric coords for vertices a, b, c
    end
    return false
end

-- Sample height at (x, y) from polygon's detail mesh triangles
-- Returns height if found, nil otherwise
local function sample_detail_height(tile, poly, x, y)
    local detail = tile.detailMeshes and tile.detailMeshes[poly]
    if not detail then
        return nil
    end

    local triCount = detail.triCount or 0
    if triCount == 0 then
        return nil
    end

    -- First pass: find exact triangle containing point
    local closestZ = nil
    local closestDistSq = math.huge

    for t = 0, triCount - 1 do
        local triIdx = (detail.triBase + t) * 4  -- Flattened array: each tri = 4 values
        local v0i = tile.detailTris[triIdx + 1]
        local v1i = tile.detailTris[triIdx + 2]
        local v2i = tile.detailTris[triIdx + 3]

        if v0i ~= nil and v1i ~= nil and v2i ~= nil then
            local ax, ay, az = get_detail_vert(tile, poly, v0i)
            local bx, by, bz = get_detail_vert(tile, poly, v1i)
            local cx, cy, cz = get_detail_vert(tile, poly, v2i)

            if ax and bx and cx then
                local inside, wa, wb, wc = point_in_triangle_2d(x, y, ax, ay, bx, by, cx, cy)
                if inside then
                    -- Exact match - barycentric interpolation for Z
                    return wa * az + wb * bz + wc * cz
                end

                -- Track closest triangle center for fallback
                local tcx = (ax + bx + cx) / 3
                local tcy = (ay + by + cy) / 3
                local tcz = (az + bz + cz) / 3
                local distSq = (x - tcx) * (x - tcx) + (y - tcy) * (y - tcy)
                if distSq < closestDistSq then
                    closestDistSq = distSq
                    closestZ = tcz
                end
            end
        end
    end

    -- Fallback: use closest triangle center height
    return closestZ
end

-- Height debug log
local HEIGHT_DEBUG_LOG = "LX_Nav_height.log"
local function logHeight(msg)
    core.write_log_file(HEIGHT_DEBUG_LOG, msg .. "\n")
end

-- Fix waypoint Z heights by searching raw tile for containing polygon
-- Searches ALL polygons (not just corridor) since wall avoidance may push waypoints outside corridor
local function fixWaypointHeights(waypoints, owners, polyPath, world, startPos, nq)
    -- Guard against nil waypoints
    if not waypoints or #waypoints == 0 then
        return waypoints
    end

    local prevZ = startPos.z
    local MAX_Z_JUMP = 8.0  -- Maximum allowed Z change per waypoint

    -- Initialize debug log
    core.create_log_file(HEIGHT_DEBUG_LOG)
    logHeight("=== fixWaypointHeights called ===")

    -- Get raw tile manager for accurate height sampling (like wireframe uses)
    local rawTileMgr = nq and nq.rawTileManager or nil
    local mapId = rawTileMgr and core.get_instance_id() or nil

    logHeight(string.format("rawTileMgr=%s, mapId=%s", rawTileMgr and "yes" or "nil", tostring(mapId)))

    -- Get all loaded raw tiles for height queries
    local rawTiles = {}
    if rawTileMgr and mapId then
        local allRawTiles = rawTileMgr:get_all_tiles(mapId)
        if allRawTiles then
            for _, tile in pairs(allRawTiles) do
                rawTiles[#rawTiles + 1] = tile
            end
        end
    end

    -- Debug: log raw tile count and first tile info
    logHeight(string.format("Raw tiles loaded: %d, waypoints: %d", #rawTiles, #waypoints))
    if #rawTiles > 0 then
        local t = rawTiles[1]
        logHeight(string.format("  First tile: bounds=%s, polygons=%d",
            t.boundsWow and "yes" or "no",
            t.polygons and #t.polygons or 0))
        if t.polygons and t.polygons[1] then
            local p = t.polygons[1]
            logHeight(string.format("  First poly: worldVerts=%s, vertCount=%d",
                p.worldVerts and #p.worldVerts or "nil", p.vertCount or 0))
        end
    end

    for idx = 1, #waypoints do
        local wp = waypoints[idx]
        local foundZ = nil
        local searchResult = "no_tiles"

        -- Search ALL raw tiles for the polygon containing this waypoint
        for tileIdx, rawTile in ipairs(rawTiles) do
            -- Check if waypoint is within tile bounds (quick reject)
            if rawTile.boundsWow then
                local b = rawTile.boundsWow
                if wp.x >= b.min.x and wp.x <= b.max.x and
                   wp.y >= b.min.y and wp.y <= b.max.y then
                    -- Within tile bounds - search polygons
                    local hz = find_height_in_raw_tile(rawTile, wp.x, wp.y)
                    if hz then
                        foundZ = hz
                        searchResult = string.format("tile%d_poly", tileIdx)
                        break
                    else
                        searchResult = "in_bounds_no_poly"
                    end
                end
            else
                -- No bounds, just search (slower but works)
                local hz = find_height_in_raw_tile(rawTile, wp.x, wp.y)
                if hz then
                    foundZ = hz
                    searchResult = string.format("tile%d_noBounds", tileIdx)
                    break
                end
            end
        end

        -- Fallback: use SoA tile polygon center if raw tile search failed
        if not foundZ then
            local owner = owners[idx] or 1
            if owner >= 1 and owner <= #polyPath then
                local node = polyPath[owner]
                if node then
                    local tileId, poly = decode_node(node)
                    local tile = world.tilesById[tileId]
                    if tile and tile.pCz and tile.pCz[poly] then
                        foundZ = tile.pCz[poly]
                    end
                end
            end
        end

        -- Apply continuity check
        if foundZ then
            local zDiff = math.abs(foundZ - prevZ)
            if idx > 1 and zDiff > MAX_Z_JUMP then
                -- Large jump - smooth transition
                foundZ = prevZ + (foundZ - prevZ) * 0.3
            end
        end

        -- Apply height with small offset above ground
        if foundZ then
            wp.z = foundZ + 0.5
            prevZ = foundZ
        else
            wp.z = prevZ + 0.5
        end

        -- Debug first few and a sample from middle
        if idx <= 3 or idx == math.floor(#waypoints / 2) or idx == #waypoints then
            logHeight(string.format("  Final WP[%d] (%.1f,%.1f,%.2f) foundZ=%s",
                idx, wp.x, wp.y, wp.z, foundZ and string.format("%.2f", foundZ) or "SoA/prev"))
        end
    end
    logHeight("=== Height fix complete ===")
end

-- =========================
-- Transition Type Annotation
-- =========================

-- Annotate waypoints with transition type based on their owner polygon
-- Waypoints on off-mesh polygons get a transitionType field (WALK, JUMP, TELEPORT, LADDER, ELEVATOR)
-- Regular walkable waypoints do not get a transitionType field (nil = normal walkable)
-- Parameters:
--   waypoints: array of {x, y, z} waypoints to annotate
--   owners: parallel array of polyPath indices (owner polygon for each waypoint)
--   polyPath: array of nodeIds from A* search
--   world: tile world data
local function annotate_waypoint_transitions(waypoints, owners, polyPath, world)
    if not waypoints or not owners or not polyPath or not world then
        return
    end

    for i, wp in ipairs(waypoints) do
        local ownerIdx = owners[i]
        if ownerIdx and ownerIdx > 0 and ownerIdx <= #polyPath then
            local nodeId = polyPath[ownerIdx]
            local tileId, poly = decode_node(nodeId)
            local tile = world.tilesById[tileId]

            if tile and is_offmesh_poly(tile, poly) then
                -- Get the off-mesh connection data
                local conn = get_offmesh_connection(tile, poly)
                if conn then
                    -- Determine transition type from connection's userId
                    local connType = conn.userId or OFFMESH_TYPE.WALK
                    local typeName = OFFMESH_TYPE_NAME[connType]
                    if typeName then
                        wp.transitionType = typeName
                    else
                        -- Unknown type - default to JUMP for off-mesh connections
                        wp.transitionType = "JUMP"
                    end
                end
            end
        end
    end
end

-- =========================
-- Funnel Algorithm
-- =========================

-- Path mode options:
-- "corridor" = Corridor follower with wall avoidance (smooth, human-like paths)
-- "visibility" = Greedy visibility-based straightening
-- "funnel" = Traditional funnel algorithm
-- "portal" = Portal midpoints (most waypoints, guaranteed safe)
local PATH_MODE = "corridor"

-- startPos: {x, y, z}
-- endPos: {x, y, z}
-- Returns: array of {x, y, z, transitionType?} waypoints
-- transitionType is only present for off-mesh connections: "WALK", "JUMP", "TELEPORT", "LADDER", "ELEVATOR"
-- Regular walkable segments have no transitionType field (nil)
function NavQuery:poly_path_to_waypoints(polyPath, startPos, endPos, maxPts)
    local world = self.world
    maxPts = maxPts or 256

    if not polyPath or #polyPath == 0 then
        return {{x = endPos.x, y = endPos.y, z = endPos.z}}
    end

    -- FIX #2c: Clamp start/end to their respective polygons (Detour requirement)
    local ta, pa = decode_node(polyPath[1])
    local tb, pb = decode_node(polyPath[#polyPath])
    local sx, sy = self:clamp_to_poly(ta, pa, startPos.x, startPos.y)
    local ex, ey = self:clamp_to_poly(tb, pb, endPos.x, endPos.y)

    -- CORRIDOR MODE: Smooth, human-like paths with wall avoidance (research-based)
    if PATH_MODE == "corridor" then
        -- Use ACTUAL start/end positions for funnel, not clamped
        -- Clamping is only for Detour's polygon validation, not for player pathfinding
        local actualStart = {x = startPos.x, y = startPos.y, z = startPos.z}
        local actualEnd = {x = endPos.x, y = endPos.y, z = endPos.z}

        -- Generate path using corridor follower (dense waypoints with wall avoidance)
        local out, owners = corridor_follower(polyPath, actualStart, actualEnd, world, self)

        -- Fix Z heights using polygon ownership
        fixWaypointHeights(out, owners, polyPath, world, startPos, self)

        -- Annotate waypoints with transition types for off-mesh connections
        annotate_waypoint_transitions(out, owners, polyPath, world)

        return out
    end

    -- VISIBILITY MODE: Greedy "look ahead as far as possible" with safe distance
    if PATH_MODE == "visibility" then
        -- Use ACTUAL start/end positions, not clamped
        local actualStart = {x = startPos.x, y = startPos.y, z = startPos.z}
        local actualEnd = {x = endPos.x, y = endPos.y, z = endPos.z}

        -- Generate path using visibility-based straightening (returns owners too)
        local out, owners = straightenPathGreedy(polyPath, actualStart, actualEnd, world)

        -- Apply safe distance from walls (may push waypoints slightly)
        out = applySafeDistance(out, polyPath, world)

        -- Fix Z heights using polygon ownership (clamps XY if pushed outside)
        fixWaypointHeights(out, owners, polyPath, world, startPos, self)

        -- Annotate waypoints with transition types for off-mesh connections
        annotate_waypoint_transitions(out, owners, polyPath, world)

        return out
    end

    -- PORTAL MODE: Use portal midpoints (fallback, most waypoints)
    if PATH_MODE == "portal" then
        local out = {}
        local owners = {}

        -- Start waypoint (owner = first polygon)
        out[1] = {x = startPos.x, y = startPos.y, z = startPos.z}
        owners[1] = 1

        -- Add portal midpoints for each polygon transition
        for i = 1, #polyPath - 1 do
            local tA, pA = decode_node(polyPath[i])
            local tB, pB = decode_node(polyPath[i + 1])

            local x0, y0, x1, y1 = self:get_transition_edge(tA, pA, tB, pB)
            if x0 then
                local midX, midY = (x0 + x1) * 0.5, (y0 + y1) * 0.5

                -- Sample height at portal midpoint
                local tileB = world.tilesById[tB]
                local midZ = startPos.z  -- Fallback
                if tileB then
                    midZ = tileB.pCz[pB] or startPos.z
                end

                out[#out + 1] = {x = midX, y = midY, z = midZ}
                owners[#out] = i + 1  -- Portal enters polygon i+1
            end
        end

        -- End waypoint (owner = last polygon)
        out[#out + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
        owners[#out] = #polyPath

        -- Annotate waypoints with transition types for off-mesh connections
        annotate_waypoint_transitions(out, owners, polyPath, world)

        return out
    end

    -- Build portals using adjacency edge data (FIX #2a)
    local portals = {}

    -- HEIGHT FIX: Build portalPolyIndex (tracks which polygon each portal enters)
    -- Portal 1 = start (in polygon 1)
    -- Portal k (k >= 2) = entering polygon k
    -- Portal #portals = end (owner = 0, use endPos.z)
    local portalPolyIndex = {}

    -- Start portal (degenerate)
    portals[1] = {sx, sy, sx, sy}
    portalPolyIndex[1] = 1  -- Start is in polygon 1

    -- Track previous position for local corridor direction (FIX #2b)
    local prevX, prevY = sx, sy

    -- Add portal for each polygon transition
    for i = 1, #polyPath - 1 do
        local a = polyPath[i]
        local b = polyPath[i + 1]
        local tA, pA = decode_node(a)
        local tB, pB = decode_node(b)

        -- FIX #2a: Use get_transition_edge (adjacency-based, deterministic)
        local x0, y0, x1, y1 = self:get_transition_edge(tA, pA, tB, pB)

        if x0 then
            -- FIX #2b: Use LOCAL corridor direction for ordering
            -- (prev position → portal midpoint, not polygon center → polygon center)
            local midX, midY = (x0 + x1) * 0.5, (y0 + y1) * 0.5
            local lx, ly, rx, ry = orderPortalLocal(prevX, prevY, midX, midY, x0, y0, x1, y1)
            portals[#portals + 1] = {lx, ly, rx, ry}
            -- Portal k enters polygon i+1 (the polygon we're transitioning INTO)
            portalPolyIndex[#portals] = i + 1
            prevX, prevY = midX, midY  -- Update for next portal
        end
    end

    -- End portal (degenerate)
    portals[#portals + 1] = {ex, ey, ex, ey}
    portalPolyIndex[#portals] = 0  -- End uses endPos.z (Detour convention: ref=0)

    -- Simple Stupid Funnel Algorithm WITH polygon ownership tracking
    local out = {}
    local owners = {}  -- Parallel array: polygon owner for each waypoint
    local apexX, apexY = portals[1][1], portals[1][2]
    local leftX, leftY = apexX, apexY
    local rightX, rightY = apexX, apexY
    local apexI, leftI, rightI = 1, 1, 1

    -- Start waypoint (owner = 1, first polygon)
    -- Use actual start position, not clamped position (funnel uses clamped internally)
    out[#out + 1] = {x = startPos.x, y = startPos.y}
    owners[#out] = portalPolyIndex[1]

    local eps2 = 1e-12
    local i = 2

    while i <= #portals and #out < maxPts do
        local p = portals[i]
        local pLeftX, pLeftY = p[1], p[2]
        local pRightX, pRightY = p[3], p[4]

        -- Update right vertex (Detour: triArea2D <= 0 means right-side check passes)
        if triArea2D(apexX, apexY, rightX, rightY, pRightX, pRightY) <= 0 then
            if veq2(apexX, apexY, rightX, rightY, eps2) or
               triArea2D(apexX, apexY, leftX, leftY, pRightX, pRightY) > 0 then
                rightX, rightY = pRightX, pRightY
                rightI = i
            else
                -- Right over left, insert left apex WITH owner from leftI
                out[#out + 1] = {x = leftX, y = leftY}
                owners[#out] = portalPolyIndex[leftI]
                apexX, apexY = leftX, leftY
                apexI = leftI
                leftX, leftY = apexX, apexY
                rightX, rightY = apexX, apexY
                leftI, rightI = apexI, apexI
                i = apexI + 1
                goto continue
            end
        end

        -- Update left vertex (Detour: triArea2D >= 0 means left-side check passes)
        if triArea2D(apexX, apexY, leftX, leftY, pLeftX, pLeftY) >= 0 then
            if veq2(apexX, apexY, leftX, leftY, eps2) or
               triArea2D(apexX, apexY, rightX, rightY, pLeftX, pLeftY) < 0 then
                leftX, leftY = pLeftX, pLeftY
                leftI = i
            else
                -- Left over right, insert right apex WITH owner from rightI
                out[#out + 1] = {x = rightX, y = rightY}
                owners[#out] = portalPolyIndex[rightI]
                apexX, apexY = rightX, rightY
                apexI = rightI
                leftX, leftY = apexX, apexY
                rightX, rightY = apexX, apexY
                leftI, rightI = apexI, apexI
                i = apexI + 1
                goto continue
            end
        end

        i = i + 1
        ::continue::
    end

    -- Ensure end point (owner = 0, use endPos.z)
    local last = out[#out]
    if not last or math.abs(last.x - ex) > 1e-6 or math.abs(last.y - ey) > 1e-6 then
        out[#out + 1] = {x = ex, y = ey}
        owners[#out] = 0
    end

    -- EDGE AVOIDANCE: Push waypoints away from dangerous edges (walls/cliffs)
    -- Applied before height sampling so heights are sampled at adjusted positions
    -- Skip first waypoint (idx=1) to preserve actual player start position
    for idx = 2, #out do
        local wp = out[idx]
        local owner = owners[idx] or 0
        if owner > 0 and owner <= #polyPath then
            local tileId, poly = decode_node(polyPath[owner])
            local tile = world.tilesById[tileId]
            if tile then
                wp.x, wp.y = adjust_waypoint_for_safety(tile, poly, wp.x, wp.y, EDGE_MARGIN)
            end
        end
    end

    -- HEIGHT: Use polygon center Z (average of vertex heights)
    for idx = 1, #out do
        local wp = out[idx]
        local owner = owners[idx] or 0

        if owner > 0 and owner <= #polyPath then
            local tileId, poly = decode_node(polyPath[owner])
            local tile = world.tilesById[tileId]
            if tile and tile.pCz[poly] then
                wp.z = tile.pCz[poly] + 0.5
            else
                wp.z = startPos.z + 0.5
            end
        else
            wp.z = startPos.z + 0.5
        end
    end

    -- Annotate waypoints with transition types for off-mesh connections
    annotate_waypoint_transitions(out, owners, polyPath, world)

    return out
end

-- =========================
-- Point-to-Polygon Lookup (BVH)
-- =========================

-- Check if point is inside polygon (2D, using winding/cross product)
function NavQuery:point_in_poly(tile, poly, x, y)
    local base = (poly - 1) * 6
    local nv = tile.pVertCount[poly]

    -- Get vertices
    local verts = {}
    for i = 1, nv do
        local vi = tile.pVerts[base + i]
        verts[i] = {x = tile.vx[vi], y = tile.vy[vi]}
    end

    -- Point-in-polygon test using cross products
    -- triArea2D uses Detour convention (negated): negative = point is LEFT of edge
    local inside = true
    for i = 1, nv do
        local j = (i % nv) + 1
        local cross = triArea2D(verts[i].x, verts[i].y,
                                verts[j].x, verts[j].y,
                                x, y)
        -- With Detour convention: cross > 0 means point is RIGHT of edge (outside for CCW poly)
        if cross > 0 then
            inside = false
            break
        end
    end

    return inside
end

-- Find polygon containing point using BVH
-- Returns: poly index, or nil if not found
-- NOW HEIGHT-AWARE: Collects all candidates and picks the one with Z closest to query
function NavQuery:find_poly_at(tileId, x, y, z)
    local tile = self.world.tilesById[tileId]
    if not tile or not tile.bvNodes or #tile.bvNodes == 0 then
        return nil
    end

    -- Quantize to BVH space
    local qf = tile.bvQuantFactor
    local qx = math.floor((x - tile.bmin[1]) * qf + 0.5)
    local qy = math.floor((y - tile.bmin[2]) * qf + 0.5)
    local qz = math.floor((z - tile.bmin[3]) * qf + 0.5)

    -- Collect ALL matching polygons (multi-level support)
    local candidates = {}

    local idx = 1
    local nodeCount = #tile.bvNodes

    while idx <= nodeCount do
        local node = tile.bvNodes[idx]

        -- Check AABB overlap
        local overlap = qx >= node.bmin[1] and qx <= node.bmax[1] and
                       qy >= node.bmin[2] and qy <= node.bmax[2] and
                       qz >= node.bmin[3] and qz <= node.bmax[3]

        if overlap then
            if node.i >= 0 then
                -- Leaf node - test polygon
                local poly = node.i + 1  -- Convert to 1-based
                if self:point_in_poly(tile, poly, x, y) then
                    -- Store candidate with its Z difference
                    local polyZ = tile.pCz[poly]
                    local zDiff = math.abs(z - polyZ)
                    candidates[#candidates + 1] = {poly = poly, zDiff = zDiff}
                end
            end
            -- Continue to next node
            idx = idx + 1
        else
            -- No overlap
            if node.i < 0 then
                -- Internal node - skip subtree
                idx = idx + (-node.i)
            else
                idx = idx + 1
            end
        end
    end

    -- No candidates found
    if #candidates == 0 then
        return nil
    end

    -- Pick the candidate with smallest Z difference (closest floor)
    local best = candidates[1]
    for i = 2, #candidates do
        if candidates[i].zDiff < best.zDiff then
            best = candidates[i]
        end
    end

    return best.poly
end

-- Maximum Z difference for polygon selection (prevents picking roofs when on ground)
local MAX_POLY_Z_DIFF = 3.0

-- Find nearest polygon to point (fallback if BVH fails)
-- NOW HEIGHT-AWARE: Prefers polygons at similar Z level to prevent roof selection
function NavQuery:find_nearest_poly(tileId, x, y, z, maxDist)
    local tile = self.world.tilesById[tileId]
    if not tile then return nil end

    maxDist = maxDist or 50
    local maxDist2 = maxDist * maxDist

    -- Phase 1: Find best polygon within Z tolerance (same floor)
    local bestPoly = nil
    local bestDist2 = maxDist2

    for p = 1, tile.polyCount do
        local dz = math.abs(z - tile.pCz[p])

        -- Only consider polygons within Z tolerance (same floor)
        if dz <= MAX_POLY_Z_DIFF then
            local dx = x - tile.pCx[p]
            local dy = y - tile.pCy[p]
            local d2 = dx * dx + dy * dy

            if d2 < bestDist2 then
                bestDist2 = d2
                bestPoly = p
            end
        end
    end

    -- Phase 2: If no polygon found on same floor, fall back to 3D distance
    -- (This handles cases where player is on stairs, slopes, or genuinely between floors)
    if not bestPoly then
        local bestDist3D = maxDist2

        for p = 1, tile.polyCount do
            local dx = x - tile.pCx[p]
            local dy = y - tile.pCy[p]
            local dz = z - tile.pCz[p]
            -- Use 3D distance but weight Z more heavily (x4) to discourage different floors
            local d3 = dx * dx + dy * dy + (dz * dz * 4)

            if d3 < bestDist3D then
                bestDist3D = d3
                bestPoly = p
            end
        end
    end

    return bestPoly
end

-- =========================
-- Height Sampling
-- =========================

-- Get height at point - simple polygon center Z
-- The polygon center is the average of vertex heights, which is correct for that polygon
function NavQuery:get_height_at(tile, poly, x, y)
    return tile.pCz[poly]
end

-- =========================
-- High-Level API
-- =========================

-- Path debug log counter (increments for each path request)
local path_debug_counter = 0
local PATH_DEBUG_LOG = "LX_Nav_path_debug.log"

-- Write detailed path debug info
local function write_path_debug(lines)
    local content = table.concat(lines, "\n") .. "\n\n"
    core.write_log_file(PATH_DEBUG_LOG, content)
end

-- Find path between two world positions
-- Returns: {success, path (waypoints), polyPath, stats}
function NavQuery:find_path(startX, startY, startZ, endX, endY, endZ)
    local world = self.world
    local Debug = require("modules/debug")

    -- Increment debug counter
    path_debug_counter = path_debug_counter + 1
    local debugLines = {}
    local function dbg(line)
        debugLines[#debugLines + 1] = line
    end

    -- Performance tracking
    local ticks_per_ms = core.cpu_ticks_per_second() / 1000
    local perf = {}  -- Store timing for each step
    local totalStart = core.cpu_ticks()

    dbg(string.format("=== PATH REQUEST #%d ===", path_debug_counter))
    dbg(string.format("Start: (%.1f, %.1f, %.1f)", startX, startY, startZ))
    dbg(string.format("End: (%.1f, %.1f, %.1f)", endX, endY, endZ))
    dbg(string.format("Distance 2D: %.1f, Distance 3D: %.1f",
        math.sqrt((endX-startX)^2 + (endY-startY)^2),
        math.sqrt((endX-startX)^2 + (endY-startY)^2 + (endZ-startZ)^2)))

    -- Debug: log what tiles we have
    local stx, sty = world:get_tile_coords(startX, startY)
    local etx, ety = world:get_tile_coords(endX, endY)
    dbg(string.format("Start tile: (%d,%d), End tile: (%d,%d)", stx, sty, etx, ety))
    dbg(string.format("NavWorld tiles loaded: %d", world:get_tile_count()))

    -- Find start tile and polygon
    local polyLookupStart = core.cpu_ticks()
    local startTileId = world:get_tile_at(startX, startY)
    if not startTileId then
        dbg(string.format("FAIL: Start tile (%d,%d) NOT LOADED", stx, sty))
        write_path_debug(debugLines)
        return {success = false, error = "start_tile_not_loaded"}
    end
    dbg(string.format("Start tileId: %d", startTileId))

    local startPoly = self:find_poly_at(startTileId, startX, startY, startZ)
    local startPolyMethod = "BVH"
    if not startPoly then
        startPoly = self:find_nearest_poly(startTileId, startX, startY, startZ)
        startPolyMethod = "nearest"
    end
    if not startPoly then
        dbg("FAIL: Could not find start polygon (BVH and nearest both failed)")
        write_path_debug(debugLines)
        return {success = false, error = "start_poly_not_found"}
    end

    local startTile = world.tilesById[startTileId]
    dbg(string.format("Start poly: %d (found via %s)", startPoly, startPolyMethod))
    dbg(string.format("  Poly center: (%.1f, %.1f, %.1f)",
        startTile.pCx[startPoly], startTile.pCy[startPoly], startTile.pCz[startPoly]))
    dbg(string.format("  Z diff (query vs poly center): %.2f", math.abs(startZ - startTile.pCz[startPoly])))

    -- Find end tile and polygon
    local endTileId = world:get_tile_at(endX, endY)
    if not endTileId then
        dbg(string.format("FAIL: End tile (%d,%d) NOT LOADED", etx, ety))
        write_path_debug(debugLines)
        return {success = false, error = "end_tile_not_loaded"}
    end
    dbg(string.format("End tileId: %d", endTileId))

    local endPoly = self:find_poly_at(endTileId, endX, endY, endZ)
    local endPolyMethod = "BVH"
    if not endPoly then
        endPoly = self:find_nearest_poly(endTileId, endX, endY, endZ)
        endPolyMethod = "nearest"
    end
    if not endPoly then
        dbg("FAIL: Could not find end polygon (BVH and nearest both failed)")
        write_path_debug(debugLines)
        return {success = false, error = "end_poly_not_found"}
    end

    local endTile = world.tilesById[endTileId]
    dbg(string.format("End poly: %d (found via %s)", endPoly, endPolyMethod))
    dbg(string.format("  Poly center: (%.1f, %.1f, %.1f)",
        endTile.pCx[endPoly], endTile.pCy[endPoly], endTile.pCz[endPoly]))
    dbg(string.format("  Z diff (query vs poly center): %.2f", math.abs(endZ - endTile.pCz[endPoly])))

    -- Check if start/end on different floors
    local polyZDiff = math.abs(startTile.pCz[startPoly] - endTile.pCz[endPoly])
    dbg(string.format("Start-End poly Z difference: %.2f", polyZDiff))
    if polyZDiff > 2.0 then
        dbg("WARNING: Start and End polygons may be on different floors!")
    end

    perf.polyLookup = (core.cpu_ticks() - polyLookupStart) / ticks_per_ms
    dbg(string.format("[PERF] Polygon lookup: %.2f ms", perf.polyLookup))

    -- A* search
    dbg("--- A* SEARCH ---")
    local startTime = core.cpu_ticks()
    local polyPath, err, expansions = self:find_poly_path(startTileId, startPoly, endTileId, endPoly)
    local astarTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    perf.astar = astarTime
    dbg(string.format("[PERF] A* search: %.2f ms (expansions: %d)",
        astarTime, expansions or 0))

    if not polyPath then
        -- Log failure details
        if err == "expansion_cap" then
            dbg("DIAGNOSIS: Hit 20k expansion cap - likely disconnected graph or start/end on different floors")
        elseif err == "no_path" then
            dbg(string.format("DIAGNOSIS: Exhausted all %d reachable nodes - no connectivity between start and end", expansions or 0))
        end
        write_path_debug(debugLines)
        return {success = false, error = err, expansions = expansions}
    end

    -- Log poly path with connection details
    dbg(string.format("Poly path: %d polygons", #polyPath))
    if #polyPath <= 20 then
        for i, nodeId in ipairs(polyPath) do
            local tid, pid = decode_node(nodeId)
            local t = world.tilesById[tid]
            if t and t.pCz then
                local polyZ = t.pCz[pid] or 0
                dbg(string.format("  [%d] tile=%d poly=%d Z=%.1f", i, tid, pid, polyZ))

                -- Check connection type to next polygon
                if i < #polyPath then
                    local success, errMsg = pcall(function()
                        local nextNodeId = polyPath[i + 1]
                        local nextTid, nextPid = decode_node(nextNodeId)

                        -- Check if it's an off-mesh connection
                        local isOffMesh = is_offmesh_poly(t, pid)
                        local nextTile = world.tilesById[nextTid]
                        local isNextOffMesh = nextTile and is_offmesh_poly(nextTile, nextPid)

                        if isOffMesh or isNextOffMesh then
                            dbg(string.format("      -> [%d] via OFF-MESH CONNECTION", i + 1))
                        else
                            -- Check if they share an edge
                            local x0, y0, x1, y1 = self:get_transition_edge(tid, pid, nextTid, nextPid)
                            if x0 then
                                dbg(string.format("      -> [%d] via shared edge at (%.1f,%.1f)-(%.1f,%.1f)",
                                    i + 1, x0, y0, x1, y1))
                            else
                                -- NO SHARED EDGE - This is a bug! Log detailed info
                                dbg(string.format("      -> [%d] via UNKNOWN CONNECTION (NO SHARED EDGE!)", i + 1))

                                -- Log all neighbors of current polygon to understand the issue
                                local base = (pid - 1) * 6
                                local nv = t.pVertCount[pid]
                                dbg(string.format("         DEBUG: Poly %d has %d vertices, checking ALL edges:", pid, nv))
                                for e = 1, nv do
                                    local nei = t.pNeis[base + e]
                                    if nei == 0 then
                                        dbg(string.format("         Edge %d: NO NEIGHBOR (boundary edge)", e))
                                    elseif nei < 0x8000 then
                                        dbg(string.format("         Edge %d: intra-tile neighbor = %d", e, nei))
                                    else
                                        local extTid = t.extToTile and t.extToTile[base + e] or 0
                                        local extPid = t.extToPoly and t.extToPoly[base + e] or 0
                                        dbg(string.format("         Edge %d: cross-tile neighbor = tile %d, poly %d (nei=0x%X)",
                                            e, extTid, extPid, nei))
                                    end
                                end
                                -- Check for internal links (off-mesh connections)
                                dbg(string.format("         Checking internal links from poly %d:", pid))
                                local internalLinks = get_internal_links(t, pid)
                                if #internalLinks > 0 then
                                    for idx, linkData in ipairs(internalLinks) do
                                        local linkTid = linkData.targetTileId
                                        if linkTid == 0 then linkTid = tid end
                                        dbg(string.format("         Internal link %d: -> tile %d, poly %d",
                                            idx, linkTid, linkData.targetPoly))
                                        if linkData.targetPoly == nextPid then
                                            dbg(string.format("         ^^^ THIS IS THE CONNECTION TO POLY %d! (internal link)", nextPid))
                                        end
                                    end
                                else
                                    dbg(string.format("         No internal links found"))
                                end

                                -- Also check reverse: does poly 546 have a link back?
                                dbg(string.format("         Checking reverse: does poly %d list poly %d as neighbor?", nextPid, pid))
                                local nextBase = (nextPid - 1) * 6
                                local nextNv = nextTile.pVertCount[nextPid]
                                for e = 1, nextNv do
                                    local nei = nextTile.pNeis[nextBase + e]
                                    if nei == pid then
                                        dbg(string.format("         YES! Poly %d edge %d -> poly %d", nextPid, e, pid))
                                    end
                                end
                            end
                        end
                    end)
                    if not success then
                        dbg(string.format("      -> [%d] ERROR checking connection: %s", i + 1, tostring(errMsg)))
                    end
                end
            else
                dbg(string.format("  [%d] tile=%d poly=%d (tile not loaded or invalid)", i, tid, pid))
            end
        end
    end

    -- Funnel smoothing
    dbg("--- FUNNEL ---")
    startTime = core.cpu_ticks()
    local waypoints = self:poly_path_to_waypoints(
        polyPath,
        {x = startX, y = startY, z = startZ},
        {x = endX, y = endY, z = endZ}
    )
    local funnelTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    -- Check if waypoints generation failed (e.g., path too steep)
    if not waypoints then
        dbg("ERROR: poly_path_to_waypoints returned nil (path rejected)")
        write_path_debug(debugLines)
        return {success = false, error = "path_too_steep"}
    end

    perf.funnel = funnelTime
    dbg(string.format("[PERF] Funnel: %.2f ms (%d waypoints)", funnelTime, #waypoints))

    -- NOTE: Height sampling is now done inside poly_path_to_waypoints() via fixWaypointHeights()
    -- which uses raw tile detail mesh data for accurate terrain heights (like wireframe)
    -- The old SoA-based height sampling here was less accurate and is no longer needed

    -- Log first few waypoints for debug (including transitionType if present)
    for i = 1, math.min(5, #waypoints) do
        local wp = waypoints[i]
        if wp.transitionType then
            dbg(string.format("  WP[%d]: (%.1f, %.1f, %.1f) [%s]", i, wp.x, wp.y, wp.z or 0, wp.transitionType))
        else
            dbg(string.format("  WP[%d]: (%.1f, %.1f, %.1f)", i, wp.x, wp.y, wp.z or 0))
        end
    end

    -- Total time and summary
    perf.total = (core.cpu_ticks() - totalStart) / ticks_per_ms
    dbg("=== PERFORMANCE SUMMARY ===")
    dbg(string.format("[PERF] Polygon lookup: %.2f ms", perf.polyLookup))
    dbg(string.format("[PERF] A* search:      %.2f ms", perf.astar))
    dbg(string.format("[PERF] Funnel+Height:  %.2f ms", perf.funnel))
    dbg(string.format("[PERF] TOTAL:          %.2f ms", perf.total))
    dbg("=== SUCCESS ===")
    write_path_debug(debugLines)

    return {
        success = true,
        path = waypoints,
        polyPath = polyPath,
        stats = {
            polys = #polyPath,
            waypoints = #waypoints,
            expansions = expansions,
            astarMs = astarTime,
            funnelMs = funnelTime,
        }
    }
end

-- Export floor snapping functions for main.lua to call
NavQuery.process_floor_snapping = process_floor_snapping
NavQuery.is_floor_snapping_active = is_floor_snapping_active

return NavQuery
