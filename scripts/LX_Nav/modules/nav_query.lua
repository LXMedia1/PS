-- Navigation Query Module
-- A* pathfinding, funnel smoothing, BVH lookup, height sampling

local Heap = require("modules/heap")
local TileConverter = require("modules/tile_converter")

local NavQuery = {}
NavQuery.__index = NavQuery

-- TILE_STRIDE must exceed max polys per tile (typically ~15000)
local TILE_STRIDE = 20000

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

local function step_cost(tileA, polyA, tileB, polyB)
    -- Base cost: 2D distance between polygon centers
    local c = dist2D(tileA.pCx[polyA], tileA.pCy[polyA],
                     tileB.pCx[polyB], tileB.pCy[polyB])

    -- Area type penalties (customize as needed)
    local areaB = tileB.pArea[polyB]
    if areaB == 2 then  -- Water
        c = c * 1.5
    elseif areaB == 3 then  -- Magma/Slime
        c = c * 10
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
-- Portal / Shared Edge
-- =========================

-- Get shared edge between two adjacent polygons
-- Returns: ax, ay, az, bx, by, bz (edge endpoints in world coords)
function NavQuery:get_shared_edge(tileAId, polyA, tileBId, polyB)
    local world = self.world
    local tileA = world.tilesById[tileAId]
    local tileB = world.tilesById[tileBId]

    if not tileA or not tileB then
        return nil
    end

    -- Intra-tile: find shared vertices
    if tileAId == tileBId then
        local baseA = (polyA - 1) * 6
        local nvA = tileA.pVertCount[polyA]
        local baseB = (polyB - 1) * 6
        local nvB = tileB.pVertCount[polyB]

        -- Build set of A's vertices
        local setA = {}
        for i = 1, nvA do
            setA[tileA.pVerts[baseA + i]] = true
        end

        -- Find shared vertices
        local shared = {}
        for i = 1, nvB do
            local v = tileB.pVerts[baseB + i]
            if setA[v] then
                shared[#shared + 1] = v
            end
        end

        if #shared >= 2 then
            local v1, v2 = shared[1], shared[2]
            return tileA.vx[v1], tileA.vy[v1], tileA.vz[v1],
                   tileA.vx[v2], tileA.vy[v2], tileA.vz[v2]
        end

        return nil
    end

    -- Cross-tile: use resolved ext arrays
    local baseA = (polyA - 1) * 6
    local nvA = tileA.pVertCount[polyA]

    for e = 1, nvA do
        local idx = baseA + e
        if tileA.extToTile[idx] == tileBId and tileA.extToPoly[idx] == polyB then
            local v1 = tileA.pVerts[baseA + e]
            local nextE = (e % nvA) + 1
            local v2 = tileA.pVerts[baseA + nextE]

            return tileA.vx[v1], tileA.vy[v1], tileA.vz[v1],
                   tileA.vx[v2], tileA.vy[v2], tileA.vz[v2]
        end
    end

    return nil
end

-- Order portal endpoints by "leftness" relative to movement direction
-- Uses Detour triArea2D: MORE LEFT = more negative value
-- fromx,fromy = source polygon center, tox,toy = destination polygon center
-- x0,y0,x1,y1 = the two endpoints of the shared edge (portal)
local function orderPortal(fromx, fromy, tox, toy, x0, y0, x1, y1)
    -- Measure "leftness" of each endpoint relative to the movement line
    local s0 = triArea2D(fromx, fromy, tox, toy, x0, y0)
    local s1 = triArea2D(fromx, fromy, tox, toy, x1, y1)

    -- More negative = more left (Detour convention)
    if s0 < s1 then
        return x0, y0, x1, y1  -- p0 is left, p1 is right
    else
        return x1, y1, x0, y0  -- p1 is left, p0 is right
    end
end

-- =========================
-- Funnel Algorithm (String Pulling)
-- =========================

-- Convert polygon path to smooth waypoints
-- polyPath: array of nodeIds from find_poly_path
-- startPos: {x, y, z}
-- endPos: {x, y, z}
-- Returns: array of {x, y, z} waypoints
function NavQuery:poly_path_to_waypoints(polyPath, startPos, endPos, maxPts)
    local world = self.world
    maxPts = maxPts or 256

    if not polyPath or #polyPath == 0 then
        return {{x = endPos.x, y = endPos.y, z = endPos.z}}
    end

    -- Build portals
    local portals = {}
    local sx, sy = startPos.x, startPos.y
    local ex, ey = endPos.x, endPos.y

    -- Start portal (degenerate)
    portals[1] = {sx, sy, sx, sy}

    -- Add portal for each polygon transition
    for i = 1, #polyPath - 1 do
        local a = polyPath[i]
        local b = polyPath[i + 1]
        local ta, pa = decode_node(a)
        local tb, pb = decode_node(b)

        local ax, ay, az, bx, by, bz = self:get_shared_edge(ta, pa, tb, pb)

        if ax then
            -- Order portal endpoints relative to movement direction
            local tileA = world.tilesById[ta]
            local tileB = world.tilesById[tb]
            if tileA and tileB then
                -- Use polygon centers as from/to positions for ordering
                local fromx, fromy = tileA.pCx[pa], tileA.pCy[pa]
                local tox, toy = tileB.pCx[pb], tileB.pCy[pb]
                local lx, ly, rx, ry = orderPortal(fromx, fromy, tox, toy, ax, ay, bx, by)
                portals[#portals + 1] = {lx, ly, rx, ry}
            end
        end
    end

    -- End portal (degenerate)
    portals[#portals + 1] = {ex, ey, ex, ey}

    -- Simple Stupid Funnel Algorithm
    local out = {}
    local apexX, apexY = portals[1][1], portals[1][2]
    local leftX, leftY = apexX, apexY
    local rightX, rightY = apexX, apexY
    local apexI, leftI, rightI = 1, 1, 1

    out[#out + 1] = {x = apexX, y = apexY, z = startPos.z}

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
                -- Right over left, insert left apex
                out[#out + 1] = {x = leftX, y = leftY}
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
                -- Left over right, insert right apex
                out[#out + 1] = {x = rightX, y = rightY}
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

    -- Ensure end point
    local last = out[#out]
    if not last or math.abs(last.x - ex) > 1e-6 or math.abs(last.y - ey) > 1e-6 then
        out[#out + 1] = {x = ex, y = ey, z = endPos.z}
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
    local inside = true
    for i = 1, nv do
        local j = (i % nv) + 1
        local cross = triarea2(verts[i].x, verts[i].y,
                               verts[j].x, verts[j].y,
                               x, y)
        if cross < 0 then
            inside = false
            break
        end
    end

    return inside
end

-- Find polygon containing point using BVH
-- Returns: poly index, or nil if not found
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
                    return poly
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

    return nil
end

-- Find nearest polygon to point (fallback if BVH fails)
function NavQuery:find_nearest_poly(tileId, x, y, z, maxDist)
    local tile = self.world.tilesById[tileId]
    if not tile then return nil end

    maxDist = maxDist or 50

    local bestPoly = nil
    local bestDist = maxDist * maxDist

    for p = 1, tile.polyCount do
        local dx = x - tile.pCx[p]
        local dy = y - tile.pCy[p]
        local d2 = dx * dx + dy * dy

        if d2 < bestDist then
            bestDist = d2
            bestPoly = p
        end
    end

    return bestPoly
end

-- =========================
-- Height Sampling
-- =========================

-- Get height at point from detail triangles
-- Returns: z height, or nil if not found
function NavQuery:get_height_at(tile, poly, x, y)
    local dm = tile.detailMeshes[poly]
    if not dm then return nil end

    local pv = tile.pVertCount[poly]
    local base = (poly - 1) * 6

    -- Helper: get vertex by detail triangle index
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

    -- Check each detail triangle
    for t = 0, dm.triCount - 1 do
        local ti = (dm.triBase + t) * 4
        local i0 = tile.detailTris[ti + 1]
        local i1 = tile.detailTris[ti + 2]
        local i2 = tile.detailTris[ti + 3]

        local ax, ay, az = getv(i0)
        local bx, by, bz = getv(i1)
        local cx, cy, cz = getv(i2)

        -- Barycentric point-in-triangle test
        local v0x, v0y = bx - ax, by - ay
        local v1x, v1y = cx - ax, cy - ay
        local v2x, v2y = x - ax, y - ay

        local den = v0x * v1y - v1x * v0y
        if den ~= 0 then
            local u = (v2x * v1y - v1x * v2y) / den
            local v = (v0x * v2y - v2x * v0y) / den

            if u >= -1e-6 and v >= -1e-6 and (u + v) <= 1.000001 then
                -- Interpolate height
                return az + u * (bz - az) + v * (cz - az)
            end
        end
    end

    return nil
end

-- =========================
-- High-Level API
-- =========================

-- Find path between two world positions
-- Returns: {success, path (waypoints), polyPath, stats}
function NavQuery:find_path(startX, startY, startZ, endX, endY, endZ)
    local world = self.world
    local Debug = require("modules/debug")

    -- Debug: log what tiles we have
    local stx, sty = world:get_tile_coords(startX, startY)
    local etx, ety = world:get_tile_coords(endX, endY)
    Debug.log(string.format("[Path] Start tile coords: (%d,%d), End tile coords: (%d,%d)",
        stx, sty, etx, ety))
    Debug.log(string.format("[Path] NavWorld has %d tiles loaded", world:get_tile_count()))

    -- Find start tile and polygon
    local startTileId = world:get_tile_at(startX, startY)
    if not startTileId then
        Debug.log(string.format("[Path] Start tile (%d,%d) NOT LOADED in NavWorld", stx, sty))
        return {success = false, error = "start_tile_not_loaded"}
    end

    local startPoly = self:find_poly_at(startTileId, startX, startY, startZ)
    if not startPoly then
        startPoly = self:find_nearest_poly(startTileId, startX, startY, startZ)
    end
    if not startPoly then
        return {success = false, error = "start_poly_not_found"}
    end

    -- Find end tile and polygon
    local endTileId = world:get_tile_at(endX, endY)
    if not endTileId then
        Debug.log(string.format("[Path] End tile (%d,%d) NOT LOADED in NavWorld", etx, ety))
        return {success = false, error = "end_tile_not_loaded"}
    end

    local endPoly = self:find_poly_at(endTileId, endX, endY, endZ)
    if not endPoly then
        endPoly = self:find_nearest_poly(endTileId, endX, endY, endZ)
    end
    if not endPoly then
        return {success = false, error = "end_poly_not_found"}
    end

    -- A* search
    local startTime = core.cpu_ticks()
    local polyPath, err, expansions = self:find_poly_path(startTileId, startPoly, endTileId, endPoly)
    local astarTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    if not polyPath then
        return {success = false, error = err, expansions = expansions}
    end

    -- Funnel smoothing
    startTime = core.cpu_ticks()
    local waypoints = self:poly_path_to_waypoints(
        polyPath,
        {x = startX, y = startY, z = startZ},
        {x = endX, y = endY, z = endZ}
    )
    local funnelTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    -- Sample heights for waypoints
    for _, wp in ipairs(waypoints) do
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
    end

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
