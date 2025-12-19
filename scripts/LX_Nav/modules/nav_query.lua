-- Navigation Query Module
-- A* pathfinding, funnel smoothing, BVH lookup, height sampling

local Heap = require("modules/heap")
local TileConverter = require("modules/tile_converter")

local NavQuery = {}
NavQuery.__index = NavQuery

-- TILE_STRIDE must exceed max polys per tile (typically ~15000)
local TILE_STRIDE = 20000

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

-- Detour-compatible signed area (NEGATED cross product)
-- With this convention: triArea2D < 0 means C is LEFT of line AB
-- This is critical for the funnel algorithm to work correctly
local function triArea2D(ax, ay, bx, by, cx, cy)
    local abx, aby = bx - ax, by - ay
    local acx, acy = cx - ax, cy - ay
    return acx * aby - abx * acy
end

-- Check if two 2D points are equal within epsilon
local function veq2(ax, ay, bx, by, eps2)
    eps2 = eps2 or 1e-12
    local dx, dy = bx - ax, by - ay
    return (dx * dx + dy * dy) <= eps2
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
-- Edge Avoidance Helper
-- =========================

local EDGE_MARGIN = 10.0  -- 10 yards from dangerous edges

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
-- NavQuery Constructor
-- =========================

function NavQuery.new(world)
    local self = setmetatable({}, NavQuery)

    -- World reference (has tilesById: tileId -> SoA tile)
    self.world = world

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

-- =========================
-- Step Cost Function
-- =========================

local NavConstants = require("modules/nav_constants")

-- Slope threshold for climbing (must match wireframe.lua)
local MAX_WALKABLE_SLOPE = 0.9

local function step_cost(tileA, polyA, tileB, polyB)
    -- Get polygon centers
    local ax, ay, az = tileA.pCx[polyA], tileA.pCy[polyA], tileA.pCz[polyA]
    local bx, by, bz = tileB.pCx[polyB], tileB.pCy[polyB], tileB.pCz[polyB]

    -- Calculate 2D distance
    local dx, dy = bx - ax, by - ay
    local xyDist = math.sqrt(dx * dx + dy * dy)

    -- Calculate slope (height change per XY distance)
    if xyDist > 0.1 then
        local heightDiff = bz - az  -- Positive = going UP
        local slope = heightDiff / xyDist

        -- If slope is too steep going UP, block this path
        if slope > MAX_WALKABLE_SLOPE then
            return 1e30  -- Can't climb this steep
        end
        -- Going DOWN steep slopes is OK (gravity helps)
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

    return c
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

    maxExpansions = maxExpansions or 20000
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
-- Funnel Algorithm
-- =========================

-- startPos: {x, y, z}
-- endPos: {x, y, z}
-- Returns: array of {x, y, z} waypoints
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
    out[#out + 1] = {x = apexX, y = apexY}
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
    for idx = 1, #out do
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

    -- HEIGHT FIX: Apply heights to all waypoints by sampling from owner polygon
    local prevZ = startPos.z
    for idx = 1, #out do
        local wp = out[idx]
        local owner = owners[idx] or 0

        if owner == 0 then
            -- End waypoint: use endPos.z
            wp.z = endPos.z
        else
            -- Sample height from owner polygon's detail mesh
            local h = sample_wp_height(self, polyPath, owner, wp.x, wp.y, prevZ)
            if h then
                wp.z = h
            else
                -- Fallback: maintain Z continuity (prevents spikes)
                wp.z = prevZ
            end
            prevZ = wp.z
        end
    end

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

-- Get height at point from detail triangles
-- NEW: Clamps point to polygon boundary before sampling (fixes underground waypoints)
-- Returns: z height, or nil if not found
function NavQuery:get_height_at(tile, poly, x, y)
    local dm = tile.detailMeshes[poly]
    if not dm then return nil end

    local pv = tile.pVertCount[poly]
    local base = (poly - 1) * 6

    -- Build poly verts arrays for clamp/inside tests (max 6 verts)
    local vx, vy = {}, {}
    for i = 1, pv do
        local vi = tile.pVerts[base + i]
        vx[i] = tile.vx[vi]
        vy[i] = tile.vy[vi]
    end

    -- CLAMP: If point is outside polygon, clamp to closest point on boundary
    if not point_in_poly_xy(x, y, vx, vy, pv) then
        x, y = closest_point_on_poly_xy(x, y, vx, vy, pv)
    end

    -- Helper: get vertex by detail triangle index (0-based index from Detour)
    local function getv(idx)
        if idx < pv then
            -- Main polygon vertex
            local vi = tile.pVerts[base + idx + 1]
            return tile.vx[vi], tile.vy[vi], tile.vz[vi]
        else
            -- Detail vertex
            local dv = dm.vertBase + (idx - pv) + 1
            return tile.detailVx[dv], tile.detailVy[dv], tile.detailVz[dv]
        end
    end

    -- Check each detail triangle with robust barycentric test
    for t = 0, dm.triCount - 1 do
        local ti = (dm.triBase + t) * 4
        local i0 = tile.detailTris[ti + 1]
        local i1 = tile.detailTris[ti + 2]
        local i2 = tile.detailTris[ti + 3]

        local ax, ay, az = getv(i0)
        local bx, by, bz = getv(i1)
        local cx, cy, cz = getv(i2)

        -- Use robust tri_height_xy with relaxed tolerance
        local hz = tri_height_xy(x, y, ax, ay, az, bx, by, bz, cx, cy, cz)
        if hz then return hz end
    end

    -- Fallback: return polygon center Z if no triangle hit
    -- This happens rarely but prevents nil values
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

    -- A* search
    dbg("--- A* SEARCH ---")
    local startTime = core.cpu_ticks()
    local polyPath, err, expansions = self:find_poly_path(startTileId, startPoly, endTileId, endPoly)
    local astarTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    dbg(string.format("A* result: %s, expansions: %d, time: %.2f ms",
        polyPath and "SUCCESS" or ("FAILED:" .. (err or "unknown")),
        expansions or 0, astarTime))

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

    -- Log poly path
    dbg(string.format("Poly path: %d polygons", #polyPath))
    if #polyPath <= 20 then
        for i, nodeId in ipairs(polyPath) do
            local tid = math.floor(nodeId / 20000)
            local pid = nodeId - tid * 20000
            local t = world.tilesById[tid]
            if t then
                dbg(string.format("  [%d] tile=%d poly=%d Z=%.1f", i, tid, pid, t.pCz[pid] or 0))
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

    dbg(string.format("Funnel: %d waypoints, time: %.2f ms", #waypoints, funnelTime))

    -- Sample heights for waypoints
    for i, wp in ipairs(waypoints) do
        local tileId = world:get_tile_at(wp.x, wp.y)
        if tileId then
            local tile = world.tilesById[tileId]
            if tile then
                -- Try BVH lookup first (needs approximate Z for bounds check)
                local poly = self:find_poly_at(tileId, wp.x, wp.y, wp.z or startZ)

                -- Fallback to nearest polygon if BVH fails
                if not poly then
                    poly = self:find_nearest_poly(tileId, wp.x, wp.y, wp.z or startZ)
                end

                if poly then
                    local h = self:get_height_at(tile, poly, wp.x, wp.y)
                    if h then
                        wp.z = h
                    else
                        -- Fallback: use polygon center Z
                        wp.z = tile.pCz[poly]
                    end
                end
            end
        end
        dbg(string.format("  WP[%d]: (%.1f, %.1f, %.1f)", i, wp.x, wp.y, wp.z or 0))
    end

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

return NavQuery
