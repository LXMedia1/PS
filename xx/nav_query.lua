-- Navigation Query Module
-- A* pathfinding, funnel smoothing, BVH lookup, height sampling

local Heap = require("modules/heap")
local TileConverter = require("modules/tile_converter")

local NavQuery = {}
NavQuery.__index = NavQuery

-- TILE_STRIDE must exceed max polys per tile (typically ~15000)
local TILE_STRIDE = 20000

-- Transition filter: max vertical change per polygon transition (yards)
-- STRICT: 1.0 yard = 3 feet max per transition. Most stairs are under this.
-- If paths avoid valid stairs, increase to 1.5 or 2.0
local MAX_CLIMB_Z = 2.0  -- Allow valid stair transitions (was 1.0, too restrictive)

-- Vertical distance penalty multiplier for 3D cost/heuristic
-- Higher = prefer flatter paths. 2.0 means 1 yard vertical = 2 yards horizontal cost.
local WZ = 2.0

-- Reference to Repair module (set via set_repair_module)
local RepairModule = nil

-- Set repair module reference (call from main.lua after loading Repair)
function NavQuery.set_repair_module(repair)
    RepairModule = repair
end

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

-- 3D distance heuristic with vertical penalty (admissible when WZ matches step_cost)
local function dist3D_heuristic(ax, ay, az, bx, by, bz)
    local dx, dy = bx - ax, by - ay
    local dz = bz - az
    return math.sqrt(dx * dx + dy * dy + (WZ * dz) * (WZ * dz))
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
-- =========================
-- Transition Filter
-- =========================

-- Check if a polygon transition is physically possible using EDGE vertices
-- This is more accurate than polygon centers for detecting cliffs
local _traverseLogCount = 0
local function can_traverse_edge(curTile, curPoly, edgeIdx, neiTile, neiPoly)
    if not curTile or not neiTile then return false end

    -- Get the Z values of the edge vertices (the portal between polygons)
    local base = (curPoly - 1) * 6
    local nv = curTile.pVertCount[curPoly]

    -- Edge vertices: edgeIdx and (edgeIdx % nv) + 1
    local v1Idx = curTile.pVerts[base + edgeIdx]
    local v2Idx = curTile.pVerts[base + (edgeIdx % nv) + 1]

    if not v1Idx or not v2Idx or v1Idx == 0 or v2Idx == 0 then
        -- Fallback to polygon center check
        local z0 = curTile.pCz[curPoly]
        local z1 = neiTile.pCz[neiPoly]
        if not z0 or not z1 then return true end
        return math.abs(z1 - z0) <= MAX_CLIMB_Z
    end

    -- Get edge Z values from current polygon
    local edgeZ1 = curTile.vz[v1Idx] or curTile.pCz[curPoly]
    local edgeZ2 = curTile.vz[v2Idx] or curTile.pCz[curPoly]
    local curEdgeMinZ = math.min(edgeZ1, edgeZ2)
    local curEdgeMaxZ = math.max(edgeZ1, edgeZ2)

    -- Get neighbor polygon's Z range (min/max of all vertices)
    local nBase = (neiPoly - 1) * 6
    local nNv = neiTile.pVertCount[neiPoly]
    local nMinZ, nMaxZ = math.huge, -math.huge
    for i = 1, nNv do
        local vIdx = neiTile.pVerts[nBase + i]
        if vIdx and vIdx > 0 then
            local vz = neiTile.vz[vIdx]
            if vz then
                nMinZ = math.min(nMinZ, vz)
                nMaxZ = math.max(nMaxZ, vz)
            end
        end
    end

    if nMinZ == math.huge then
        nMinZ = neiTile.pCz[neiPoly] or 0
        nMaxZ = nMinZ
    end

    -- Check if the edge Z and neighbor Z have reasonable overlap
    -- The gap between current edge Z and neighbor Z range should be small
    local gap = 0
    if curEdgeMaxZ < nMinZ then
        gap = nMinZ - curEdgeMaxZ  -- Current edge is BELOW neighbor
    elseif curEdgeMinZ > nMaxZ then
        gap = curEdgeMinZ - nMaxZ  -- Current edge is ABOVE neighbor
    end

    if gap > MAX_CLIMB_Z then
        if _traverseLogCount < 30 then
            _traverseLogCount = _traverseLogCount + 1
            core.write_log_file("LX_Nav.log", string.format(
                "[TRAVERSE REJECT] poly %d edge(%d) z=[%.1f,%.1f] -> poly %d z=[%.1f,%.1f] gap=%.2f\n",
                curPoly, edgeIdx, curEdgeMinZ, curEdgeMaxZ, neiPoly, nMinZ, nMaxZ, gap))
        end
        return false
    end

    return true
end

-- =========================
-- Step Cost Function
-- =========================

local NavConstants = require("modules/nav_constants")

-- Slope threshold for climbing (must match wireframe.lua)
local MAX_WALKABLE_SLOPE = 0.9

-- Penalty multiplier for polygons near boundaries (walls/cliffs/edges)
local BOUNDARY_PENALTY = 8.0  -- Strong preference for interior polygons

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

    -- Base cost: 3D distance with vertical penalty
    -- This penalizes vertical movement, making paths that "teleport" through floors expensive
    local dz = bz - az
    local c = math.sqrt(dx * dx + dy * dy + (WZ * dz) * (WZ * dz))

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
-- A* Pathfinding
-- =========================

-- Find polygon path from start to goal
-- Returns: array of nodeIds, bridgeTransitions table, or nil + error message
function NavQuery:find_poly_path(startTileId, startPoly, endTileId, endPoly, maxExpansions, dbgFunc)
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

    -- Track expanded nodes for debug output
    local expanded_list = {}

    -- Track which transitions used bridges: bridgeEdge[childNode] = {fromX, fromY, fromZ, toX, toY, toZ}
    local bridgeEdge = {}

    -- Get tiles
    local startTile = world.tilesById[startTileId]
    local goalTile = world.tilesById[endTileId]

    if not startTile or not goalTile then
        return nil, "tiles_not_loaded"
    end

    -- TRY BRIDGES FIRST: If a bridge connects near start to near goal, use it
    -- Use a flag to prevent infinite recursion (bridge check calls find_poly_path)
    if RepairModule and not self._skipBridgeCheck then
        self._skipBridgeCheck = true  -- Prevent recursion

        local bridges = RepairModule.get_bridges()
        local staged = RepairModule.get_staged_bridges and RepairModule.get_staged_bridges() or {}
        local all_bridges = {}
        for _, b in ipairs(bridges) do all_bridges[#all_bridges + 1] = b end
        for _, b in ipairs(staged) do all_bridges[#all_bridges + 1] = b end

        for _, bridge in ipairs(all_bridges) do
            local wps = bridge.waypoints
            if wps and #wps >= 2 then
                local first = wps[1]
                local last = wps[#wps]

                -- Check both directions
                for _, dir in ipairs({"forward", "reverse"}) do
                    local entryWp, exitWp, bridgeWaypoints
                    if dir == "forward" then
                        entryWp, exitWp, bridgeWaypoints = first, last, wps
                    else
                        entryWp, exitWp = last, first
                        bridgeWaypoints = {}
                        for i = #wps, 1, -1 do bridgeWaypoints[#bridgeWaypoints + 1] = wps[i] end
                    end

                    if entryWp.tileId and entryWp.polyIdx and exitWp.tileId and exitWp.polyIdx then
                        -- Try: start -> bridge entry, bridge exit -> goal
                        local path1, err1 = self:find_poly_path(startTileId, startPoly,
                            entryWp.tileId, entryWp.polyIdx, 3000)
                        if path1 and #path1 > 0 then
                            local path2, err2 = self:find_poly_path(exitWp.tileId, exitWp.polyIdx,
                                endTileId, endPoly, 3000)
                            if path2 and #path2 > 0 then
                                -- SUCCESS! Bridge provides a valid path
                                self._skipBridgeCheck = false
                                -- Return the bridge path directly
                                local bridgePath = {}
                                for _, n in ipairs(path1) do bridgePath[#bridgePath + 1] = n end
                                -- Add bridge waypoints as special markers
                                bridgePath._bridgeWaypoints = bridgeWaypoints
                                bridgePath._bridgeExitPoly = path2[1]
                                for i = 2, #path2 do bridgePath[#bridgePath + 1] = path2[i] end
                                return bridgePath
                            end
                        end
                    end
                end
            end
        end

        self._skipBridgeCheck = false
    end

    -- Initialize start node
    g[startNode] = 0
    local h0 = dist3D_heuristic(
        startTile.pCx[startPoly], startTile.pCy[startPoly], startTile.pCz[startPoly],
        goalTile.pCx[endPoly], goalTile.pCy[endPoly], goalTile.pCz[endPoly])
    f[startNode] = h0
    parent[startNode] = 0
    seen[startNode] = sid

    heap:push(startNode, f[startNode])

    -- Debug: Log start/goal info
    local startZ = startTile.pCz[startPoly] or 0
    local goalZ = goalTile.pCz[endPoly] or 0
    core.write_log_file("LX_Nav.log", string.format(
        "[A* START] start=(%d,%d) z=%.1f goal=(%d,%d) z=%.1f\n",
        startTileId, startPoly, startZ, endTileId, endPoly, goalZ))

    local expansions = 0
    local _logged2032 = false

    while heap:size() > 0 do
        local cur = heap:pop()
        local curTileId, curPoly = decode_node(cur)

        -- Debug: Log when we reach bridge entry polygon 2032
        if curPoly == 2032 and not _logged2032 then
            _logged2032 = true
            core.write_log_file("LX_Nav.log", string.format(
                "[A*] REACHED bridge entry poly 2032! tile=%d\n", curTileId))
        end

        -- Goal check
        if cur == goalNode then
            -- Reconstruct path and bridge transitions
            local path = {}
            local bridgeTransitions = {}  -- bridgeTransitions[pathIndex] = {from={x,y,z}, to={x,y,z}}
            local n = cur
            while n ~= 0 do
                path[#path + 1] = n
                -- Check if this node was reached via bridge
                if bridgeEdge[n] then
                    bridgeTransitions[#path] = bridgeEdge[n]
                end
                n = parent[n] or 0
            end
            -- Reverse path
            for i = 1, math.floor(#path / 2) do
                path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
            end
            -- Fix bridge transition indices after reversal
            local fixedBridgeTransitions = {}
            for oldIdx, bridge in pairs(bridgeTransitions) do
                local newIdx = #path - oldIdx + 1
                fixedBridgeTransitions[newIdx] = bridge
            end

            -- Debug: log path with Z values to verify no floor-clipping
            local logLines = {"[PATH DEBUG] Found path with " .. #path .. " nodes:"}
            local prevZ = nil
            for i = 1, math.min(#path, 15) do
                local tid, pid = decode_node(path[i])
                local t = world.tilesById[tid]
                if t then
                    local z = t.pCz[pid] or 0
                    local zDelta = prevZ and string.format(" (dZ=%.1f)", z - prevZ) or ""
                    local bridgeMarker = fixedBridgeTransitions[i] and " [BRIDGE]" or ""
                    logLines[#logLines + 1] = string.format("  %d: tile=%d poly=%d z=%.1f%s%s",
                        i, tid, pid, z, zDelta, bridgeMarker)
                    prevZ = z
                end
            end
            if #path > 15 then
                logLines[#logLines + 1] = "  ... (" .. (#path - 15) .. " more nodes)"
            end
            core.write_log_file("LX_Nav.log", table.concat(logLines, "\n") .. "\n")

            return path, nil, expansions, fixedBridgeTransitions
        end

        -- Mark as closed
        closed[cur] = sid
        expansions = expansions + 1
        expanded_list[#expanded_list + 1] = cur

        if expansions > maxExpansions then
            return nil, "expansion_cap", expansions
        end

        -- curTileId, curPoly already decoded at start of loop
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

                        -- Skip if transition is physically impossible (large Z gap at edge)
                        if nTile and not can_traverse_edge(curTile, curPoly, e, nTile, nPoly) then
                            goto skip_neighbor
                        end

                        -- Skip if blacklisted (from Repair module - triangle level)
                        if RepairModule and RepairModule.is_polygon_partially_blacklisted(nTileId, nPoly) then
                            goto skip_neighbor
                        end

                        if nTile then
                            -- Also skip if polygon center is in a blacklist point radius
                            if RepairModule and RepairModule.is_position_blacklisted(
                                    nTile.pCx[nPoly], nTile.pCy[nPoly], nTile.pCz[nPoly]) then
                                goto skip_neighbor
                            end
                            local tentative = (g[cur] or 1e30) + step_cost(curTile, curPoly, nTile, nPoly)

                            if seen[nb] ~= sid or tentative < (g[nb] or 1e30) then
                                parent[nb] = cur
                                g[nb] = tentative

                                local hx = dist3D_heuristic(
                                    nTile.pCx[nPoly], nTile.pCy[nPoly], nTile.pCz[nPoly],
                                    goalTile.pCx[endPoly], goalTile.pCy[endPoly], goalTile.pCz[endPoly])
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
                        ::skip_neighbor::
                    end
                end
            end
        end

        -- Expand bridge neighbors (from Repair module)
        -- Bridges are STRONGLY preferred - give them a massive cost bonus
        if RepairModule then
            local bridge_neighbors = RepairModule.get_bridge_neighbors(curTileId, curPoly)
            if #bridge_neighbors > 0 then
                core.write_log_file("LX_Nav.log", string.format(
                    "[A*] Found %d bridge neighbors at poly %d\n", #bridge_neighbors, curPoly))
            end
            for _, bn in ipairs(bridge_neighbors) do
                local nTileId = bn.tileId
                local nPoly = bn.polyIdx
                local nb = node_id(nTileId, nPoly)

                if closed[nb] ~= sid then
                    local nTile = world.tilesById[nTileId]
                    if nTile then
                        -- Bridge cost = actual traversal distance through all waypoints
                        local bridgeCost = 0
                        local wps = bn.bridgeWaypoints
                        if wps and #wps >= 2 then
                            for i = 1, #wps - 1 do
                                local w1, w2 = wps[i], wps[i + 1]
                                local dx = w2.x - w1.x
                                local dy = w2.y - w1.y
                                local dz = w2.z - w1.z
                                bridgeCost = bridgeCost + math.sqrt(dx*dx + dy*dy + dz*dz)
                            end
                        else
                            -- Fallback: straight-line 3D distance
                            local dx = bn.x - bn.entryX
                            local dy = bn.y - bn.entryY
                            local dz = bn.z - bn.entryZ
                            bridgeCost = math.sqrt(dx*dx + dy*dy + dz*dz)
                        end
                        local tentative = (g[cur] or 1e30) + bridgeCost

                        if seen[nb] ~= sid or tentative < (g[nb] or 1e30) then
                            parent[nb] = cur
                            g[nb] = tentative

                            -- Store bridge transition info (entry point on cur poly, exit point on neighbor poly)
                            bridgeEdge[nb] = {
                                from = {x = bn.entryX, y = bn.entryY, z = bn.entryZ},
                                to = {x = bn.x, y = bn.y, z = bn.z}
                            }

                            local hx = dist3D_heuristic(bn.x, bn.y, bn.z,
                                goalTile.pCx[endPoly], goalTile.pCy[endPoly], goalTile.pCz[endPoly])
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

    -- Debug output for failed path searches
    if dbgFunc then
        dbgFunc("\n=== A* FAILURE DEBUG ===")
        dbgFunc(string.format("Goal node: %d (tile=%d poly=%d)", goalNode, endTileId, endPoly))

        if goalTile then
            dbgFunc(string.format("Goal poly center: (%.1f, %.1f, %.1f)",
                goalTile.pCx[endPoly], goalTile.pCy[endPoly], goalTile.pCz[endPoly]))
        end

        dbgFunc(string.format("Total expanded: %d", #expanded_list))

        -- Show last 10 expanded polygons with their neighbor info
        dbgFunc("\nLast 10 expanded nodes:")
        local startIdx = math.max(1, #expanded_list - 9)
        for i = startIdx, #expanded_list do
            local nodeId = expanded_list[i]
            local tileId, poly = decode_node(nodeId)
            local tile = world.tilesById[tileId]
            if tile then
                local base = (poly - 1) * 6
                local nv = tile.pVertCount[poly]
                local neiInfo = {}
                for e = 1, nv do
                    local nei = tile.pNeis[base + e]
                    if nei == 0 then
                        neiInfo[#neiInfo + 1] = "WALL"
                    elseif nei < 0x8000 then
                        neiInfo[#neiInfo + 1] = string.format("int:%d", nei)
                    else
                        local extT = tile.extToTile[base + e] or 0
                        local extP = tile.extToPoly[base + e] or 0
                        if extT == 0 or extP == 0 then
                            neiInfo[#neiInfo + 1] = "EXT:UNRESOLVED"
                        else
                            neiInfo[#neiInfo + 1] = string.format("ext:%d/%d", extT, extP)
                        end
                    end
                end
                dbgFunc(string.format("  [%d] tile=%d poly=%d Z=%.1f neis=[%s]",
                    i, tileId, poly, tile.pCz[poly] or 0, table.concat(neiInfo, ", ")))
            end
        end

        -- Check goal polygon connectivity
        dbgFunc("\nGoal polygon neighbors:")
        if goalTile then
            local base = (endPoly - 1) * 6
            local nv = goalTile.pVertCount[endPoly]
            for e = 1, nv do
                local nei = goalTile.pNeis[base + e]
                if nei == 0 then
                    dbgFunc(string.format("  edge %d: WALL", e))
                elseif nei < 0x8000 then
                    dbgFunc(string.format("  edge %d: internal poly %d", e, nei))
                else
                    local extT = goalTile.extToTile[base + e] or 0
                    local extP = goalTile.extToPoly[base + e] or 0
                    dbgFunc(string.format("  edge %d: external tile=%d poly=%d", e, extT, extP))
                end
            end
        end

        -- Check for off-mesh connections in the tile
        if startTile and startTile.offMeshConnections and #startTile.offMeshConnections > 0 then
            dbgFunc(string.format("\nOff-mesh connections in start tile: %d", #startTile.offMeshConnections))
            for i, conn in ipairs(startTile.offMeshConnections) do
                if conn then
                    dbgFunc(string.format("  [%d] poly=%d start=(%.1f,%.1f,%.1f) end=(%.1f,%.1f,%.1f) rad=%.1f bidir=%s",
                        i, conn.poly or 0,
                        conn.startX or 0, conn.startY or 0, conn.startZ or 0,
                        conn.endX or 0, conn.endY or 0, conn.endZ or 0,
                        conn.rad or 0, tostring(conn.flags == 1)))
                end
            end
        else
            dbgFunc("\nNo off-mesh connections in start tile")
        end
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
-- Returns: portalA {x,y}, portalB {x,y} or nil, nil if not found
local function getPortalEndpoints(polyPath, fromIdx, toIdx, world)
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
    local x0, y0, x1, y1

    if tileAId == tileBId then
        -- Intra-tile: find edge where neis[e] == polyB
        for e = 1, nvA do
            if tileA.pNeis[baseA + e] == polyB then
                local v0 = tileA.pVerts[baseA + e]
                local v1 = tileA.pVerts[baseA + (e % nvA) + 1]
                x0, y0 = tileA.vx[v0], tileA.vy[v0]
                x1, y1 = tileA.vx[v1], tileA.vy[v1]
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
                x0, y0 = tileA.vx[v0], tileA.vy[v0]
                x1, y1 = tileA.vx[v1], tileA.vy[v1]
                break
            end
        end
    end

    if not x0 then
        return nil, nil
    end

    return {x = x0, y = y0}, {x = x1, y = y1}
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
        logPathDebug("Empty polyPath - no valid path found")
        return nil  -- Return nil to indicate failure, NOT a straight line
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
    if not detail or detail.triCount == 0 then
        return nil
    end

    -- Loop through detail triangles for this polygon
    for t = 0, detail.triCount - 1 do
        local triIdx = (detail.triBase + t) * 4  -- Flattened array: each tri = 4 values
        local v0i = tile.detailTris[triIdx + 1]
        local v1i = tile.detailTris[triIdx + 2]
        local v2i = tile.detailTris[triIdx + 3]

        if v0i and v1i and v2i then
            local ax, ay, az = get_detail_vert(tile, poly, v0i)
            local bx, by, bz = get_detail_vert(tile, poly, v1i)
            local cx, cy, cz = get_detail_vert(tile, poly, v2i)

            if ax and bx and cx then
                local inside, wa, wb, wc = point_in_triangle_2d(x, y, ax, ay, bx, by, cx, cy)
                if inside then
                    -- Barycentric interpolation for Z
                    return wa * az + wb * bz + wc * cz
                end
            end
        end
    end

    return nil  -- Point not in any detail triangle
end

-- Fix waypoint Z heights using polygon ownership
-- First repairs ownership if waypoint was pushed into adjacent corridor poly,
-- then samples height from detail mesh triangles (not just pCz)
local function fixWaypointHeights(waypoints, owners, polyPath, world, startPos, nq)
    local prevZ = startPos.z

    for idx = 1, #waypoints do
        local wp = waypoints[idx]
        local owner = owners[idx] or 1

        if owner > 0 and owner <= #polyPath then
            -- Repair ownership if safe distance pushed waypoint into adjacent corridor poly
            owner = repairOwnerInCorridor(world, polyPath, owner, wp.x, wp.y, nq)
            owners[idx] = owner  -- Update for debug logging

            local tileId, poly = decode_node(polyPath[owner])
            local tile = world.tilesById[tileId]

            if tile then
                -- Clamp waypoint XY to polygon boundary if still outside
                local cx, cy = nq:clamp_to_poly(tileId, poly, wp.x, wp.y)
                wp.x, wp.y = cx, cy

                -- Sample height from detail mesh triangles (accurate for slopes)
                local hz = sample_detail_height(tile, poly, wp.x, wp.y)

                -- Fallback to polygon center Z if detail sampling fails
                if not hz then
                    hz = tile.pCz[poly]
                end

                if hz then
                    wp.z = hz + 0.5  -- Small offset above ground
                else
                    wp.z = prevZ
                end
            else
                wp.z = prevZ
            end
        else
            -- End waypoint or unknown owner - use previous Z
            wp.z = prevZ
        end

        prevZ = wp.z
    end
end

-- =========================
-- Bridge-aware Path Generation
-- =========================

-- Generate waypoints for a path that uses bridges
-- For each segment: pathfind from current position TO the bridge entry, then jump to bridge exit
function NavQuery:poly_path_to_waypoints_with_bridges(polyPath, startPos, endPos, bridgeTransitions)
    local world = self.world
    local finalPath = {}

    -- Debug log
    logPathDebug("=== BRIDGE-AWARE PATH GENERATION ===")
    logPathDebug(string.format("polyPath length: %d", #polyPath))
    logPathDebug(string.format("startPos: (%.1f, %.1f, %.1f)", startPos.x, startPos.y, startPos.z))
    logPathDebug(string.format("endPos: (%.1f, %.1f, %.1f)", endPos.x, endPos.y, endPos.z))

    -- Add start position
    finalPath[#finalPath + 1] = {x = startPos.x, y = startPos.y, z = startPos.z}

    -- Find bridge indices and sort them
    local bridgeIndices = {}
    for idx, _ in pairs(bridgeTransitions) do
        bridgeIndices[#bridgeIndices + 1] = idx
        local b = bridgeTransitions[idx]
        logPathDebug(string.format("Bridge at polyPath[%d]: from=(%.1f,%.1f,%.1f) to=(%.1f,%.1f,%.1f)",
            idx, b.from.x, b.from.y, b.from.z, b.to.x, b.to.y, b.to.z))
    end
    table.sort(bridgeIndices)

    -- Process path segments between bridges
    local segmentStart = 1
    local currentPos = startPos

    for _, bridgeIdx in ipairs(bridgeIndices) do
        local bridge = bridgeTransitions[bridgeIdx]
        if not bridge then goto continue_bridge end

        logPathDebug(string.format("\n--- Processing bridge at index %d ---", bridgeIdx))

        -- Segment is from segmentStart to bridgeIdx-1 (polygons before the bridge)
        local segmentEnd = bridgeIdx - 1
        logPathDebug(string.format("Segment: polyPath[%d..%d]", segmentStart, segmentEnd))

        -- The destination for this segment is the BRIDGE ENTRY POINT (not polygon center!)
        local bridgeEntry = {x = bridge.from.x, y = bridge.from.y, z = bridge.from.z}

        if segmentEnd >= segmentStart then
            -- Extract segment of polyPath
            local segment = {}
            for i = segmentStart, segmentEnd do
                segment[#segment + 1] = polyPath[i]
            end
            logPathDebug(string.format("Segment has %d polygons", #segment))

            -- Generate waypoints for this segment - destination is bridge entry!
            if #segment >= 1 then
                local clampedStart = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
                logPathDebug(string.format("Calling straightenPathGreedy: start=(%.1f,%.1f) end=(%.1f,%.1f)",
                    clampedStart.x, clampedStart.y, bridgeEntry.x, bridgeEntry.y))

                local segWaypoints, owners = straightenPathGreedy(segment, clampedStart, bridgeEntry, world)

                logPathDebug(string.format("straightenPathGreedy returned %d waypoints", segWaypoints and #segWaypoints or 0))
                if segWaypoints then
                    for wi, wp in ipairs(segWaypoints) do
                        logPathDebug(string.format("  wp[%d]: (%.1f, %.1f, %.1f)", wi, wp.x, wp.y, wp.z))
                    end
                end

                -- Add segment waypoints (skip first if it duplicates current position)
                for i = 2, #segWaypoints do
                    finalPath[#finalPath + 1] = segWaypoints[i]
                end
            end
        else
            logPathDebug("Segment is empty (segmentEnd < segmentStart)")
        end

        -- Add bridge entry point (in case segment smoothing didn't reach it exactly)
        -- Only add if significantly different from last waypoint
        local lastWp = finalPath[#finalPath]
        local distToEntry = dist2D(lastWp.x, lastWp.y, bridgeEntry.x, bridgeEntry.y)
        logPathDebug(string.format("Distance from last waypoint to bridge entry: %.1f", distToEntry))
        if distToEntry > 1.0 then
            finalPath[#finalPath + 1] = bridgeEntry
            logPathDebug("Added bridge entry waypoint")
        end

        -- Add bridge exit (where we land after crossing)
        finalPath[#finalPath + 1] = {
            x = bridge.to.x,
            y = bridge.to.y,
            z = bridge.to.z
        }
        logPathDebug(string.format("Added bridge exit: (%.1f, %.1f, %.1f)", bridge.to.x, bridge.to.y, bridge.to.z))
        currentPos = bridge.to

        -- Next segment starts at the polygon we entered via bridge
        segmentStart = bridgeIdx

        ::continue_bridge::
    end

    -- Process final segment (from last bridge to end destination)
    if segmentStart <= #polyPath then
        local segment = {}
        for i = segmentStart, #polyPath do
            segment[#segment + 1] = polyPath[i]
        end

        if #segment >= 1 then
            local clampedStart = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
            local segWaypoints, owners = straightenPathGreedy(segment, clampedStart, endPos, world)

            -- Add segment waypoints (skip first if it duplicates current position)
            for i = 2, #segWaypoints do
                finalPath[#finalPath + 1] = segWaypoints[i]
            end
        end

        -- Ensure we reach the end position
        local lastWp = finalPath[#finalPath]
        local distToEnd = dist2D(lastWp.x, lastWp.y, endPos.x, endPos.y)
        if distToEnd > 1.0 then
            finalPath[#finalPath + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
        end
    else
        -- No remaining segment, just add end
        finalPath[#finalPath + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}
    end

    return finalPath
end

-- =========================
-- Funnel Algorithm
-- =========================

-- Path mode options:
-- "visibility" = Greedy visibility-based straightening (recommended)
-- "funnel" = Traditional funnel algorithm
-- "portal" = Portal midpoints (most waypoints, guaranteed safe)
local PATH_MODE = "visibility"

-- startPos: {x, y, z}
-- endPos: {x, y, z}
-- bridgeTransitions: table mapping polyPath index to {from={x,y,z}, to={x,y,z}} for bridge crossings
-- Returns: array of {x, y, z} waypoints
function NavQuery:poly_path_to_waypoints(polyPath, startPos, endPos, maxPts, bridgeTransitions)
    local world = self.world
    maxPts = maxPts or 256
    bridgeTransitions = bridgeTransitions or {}

    if not polyPath or #polyPath == 0 then
        return {{x = endPos.x, y = endPos.y, z = endPos.z}}
    end

    -- Check if path uses any bridges
    local hasBridges = next(bridgeTransitions) ~= nil

    -- If path uses bridges, use a simpler segment-by-segment approach
    if hasBridges then
        return self:poly_path_to_waypoints_with_bridges(polyPath, startPos, endPos, bridgeTransitions)
    end

    -- FIX #2c: Clamp start/end to their respective polygons (Detour requirement)
    local ta, pa = decode_node(polyPath[1])
    local tb, pb = decode_node(polyPath[#polyPath])
    local sx, sy = self:clamp_to_poly(ta, pa, startPos.x, startPos.y)
    local ex, ey = self:clamp_to_poly(tb, pb, endPos.x, endPos.y)

    -- VISIBILITY MODE: Greedy "look ahead as far as possible" with safe distance
    if PATH_MODE == "visibility" then
        local clampedStart = {x = sx, y = sy, z = startPos.z}
        local clampedEnd = {x = ex, y = ey, z = endPos.z}

        -- Generate path using visibility-based straightening (returns owners too)
        local out, owners = straightenPathGreedy(polyPath, clampedStart, clampedEnd, world)

        -- Apply safe distance from walls (may push waypoints slightly)
        out = applySafeDistance(out, polyPath, world)

        -- Fix Z heights using polygon ownership (clamps XY if pushed outside)
        fixWaypointHeights(out, owners, polyPath, world, startPos, self)

        return out
    end

    -- PORTAL MODE: Use portal midpoints (fallback, most waypoints)
    if PATH_MODE == "portal" then
        local out = {}

        -- Start waypoint
        out[1] = {x = startPos.x, y = startPos.y, z = startPos.z}

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
            end
        end

        -- End waypoint
        out[#out + 1] = {x = endPos.x, y = endPos.y, z = endPos.z}

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
    local polyPath, err, expansions, bridgeTransitions = self:find_poly_path(startTileId, startPoly, endTileId, endPoly, nil, dbg)
    local astarTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    -- Log bridge transitions if any
    if bridgeTransitions and next(bridgeTransitions) then
        dbg(string.format("Bridge transitions found: %d", table.maxn and table.maxn(bridgeTransitions) or 0))
        for idx, bridge in pairs(bridgeTransitions) do
            dbg(string.format("  [%d] from=(%.1f,%.1f,%.1f) to=(%.1f,%.1f,%.1f)",
                idx, bridge.from.x, bridge.from.y, bridge.from.z,
                bridge.to.x, bridge.to.y, bridge.to.z))
        end
    end

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

        -- Try Repair bridge fallback: explicitly path TO bridge, then FROM bridge
        dbg("--- REPAIR BRIDGE FALLBACK ---")
        if RepairModule then
            local bridges = RepairModule.get_bridges()
            dbg(string.format("Checking %d saved Repair bridges", bridges and #bridges or 0))

            for i, bridge in ipairs(bridges or {}) do
                -- New multi-waypoint format: bridge.waypoints = [{tileId, polyIdx, x, y, z, isTri}, ...]
                local wps = bridge.waypoints
                if not wps or #wps < 2 then
                    dbg(string.format("Bridge #%d: INVALID (no waypoints or <2)", i))
                    goto continue_bridge
                end

                local firstWp = wps[1]
                local lastWp = wps[#wps]

                dbg(string.format("Bridge #%d: %d waypoints, from (%.1f,%.1f,%.1f) -> to (%.1f,%.1f,%.1f)",
                    i, #wps, firstWp.x, firstWp.y, firstWp.z, lastWp.x, lastWp.y, lastWp.z))

                -- Try both directions
                for _, dir in ipairs({"forward", "reverse"}) do
                    local entryWp, exitWp, bridgeWaypoints
                    if dir == "forward" then
                        entryWp = firstWp
                        exitWp = lastWp
                        bridgeWaypoints = wps
                    else
                        entryWp = lastWp
                        exitWp = firstWp
                        -- Reverse waypoints for path
                        bridgeWaypoints = {}
                        for j = #wps, 1, -1 do
                            bridgeWaypoints[#bridgeWaypoints + 1] = wps[j]
                        end
                    end

                    local entryTile = entryWp.tileId
                    local entryPoly = entryWp.polyIdx
                    local entryPos = {x = entryWp.x, y = entryWp.y, z = entryWp.z}
                    local exitTile = exitWp.tileId
                    local exitPoly = exitWp.polyIdx
                    local exitPos = {x = exitWp.x, y = exitWp.y, z = exitWp.z}

                    dbg(string.format("  Trying %s direction...", dir))

                    -- Path from start to bridge entry
                    local path1, err1 = self:find_poly_path(startTileId, startPoly, entryTile, entryPoly, 5000)
                    if path1 and #path1 > 0 then
                        dbg(string.format("    Start -> Bridge entry: SUCCESS (%d polys)", #path1))

                        -- Path from bridge exit to end
                        local path2, err2 = self:find_poly_path(exitTile, exitPoly, endTileId, endPoly, 5000)
                        if path2 and #path2 > 0 then
                            dbg(string.format("    Bridge exit -> End: SUCCESS (%d polys)", #path2))

                            -- Build multi-segment path!
                            local finalPath = {}

                            -- Segment 1: Start to bridge entry
                            local wp1 = self:poly_path_to_waypoints(path1,
                                {x = startX, y = startY, z = startZ}, entryPos)
                            for _, wp in ipairs(wp1) do
                                finalPath[#finalPath + 1] = wp
                            end

                            -- Add ALL bridge waypoints (including intermediate ones)
                            for j = 2, #bridgeWaypoints do  -- Skip first (already at entry)
                                local bwp = bridgeWaypoints[j]
                                finalPath[#finalPath + 1] = {x = bwp.x, y = bwp.y, z = bwp.z}
                            end

                            -- Segment 2: Bridge exit to end
                            local wp2 = self:poly_path_to_waypoints(path2,
                                exitPos, {x = endX, y = endY, z = endZ})
                            -- Skip first point (duplicate of exit)
                            for j = 2, #wp2 do
                                finalPath[#finalPath + 1] = wp2[j]
                            end

                            dbg(string.format("REPAIR BRIDGE SUCCESS: %d total waypoints (bridge had %d pts)", #finalPath, #wps))
                            write_path_debug(debugLines)

                            return {
                                success = true,
                                path = finalPath,
                                polyPath = nil,
                                fallback = true,
                                stats = {
                                    polys = #path1 + #path2,
                                    waypoints = #finalPath,
                                    expansions = expansions,
                                    astarMs = perf.astar,
                                    fallbackType = "repair_bridge_" .. dir,
                                }
                            }
                        else
                            dbg(string.format("    Bridge exit -> End: FAILED (%s)", err2 or "unknown"))
                        end
                    else
                        dbg(string.format("    Start -> Bridge entry: FAILED (%s)", err1 or "unknown"))
                    end
                end
                ::continue_bridge::
            end
            dbg("No Repair bridge could connect start to end")
        else
            dbg("RepairModule not available")
        end

        -- DISABLED: Old gap-bridge system replaced by Repair module bridges
        -- dbg("--- GAP BRIDGE FALLBACK ---")
        -- local mapId = core.get_instance_id()
        -- local bridgePath, bridgeDir = NavQuery.find_gap_bridge(mapId, startX, startY, startZ, endX, endY, endZ)
        dbg("--- GAP BRIDGE FALLBACK (DISABLED) ---")

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
        {x = endX, y = endY, z = endZ},
        nil,  -- maxPts
        bridgeTransitions
    )
    local funnelTime = (core.cpu_ticks() - startTime) / (core.cpu_ticks_per_second() / 1000)

    perf.funnel = funnelTime
    dbg(string.format("[PERF] Funnel: %.2f ms (%d waypoints)", funnelTime, #waypoints))

    -- Sample heights for waypoints
    local heightStart = core.cpu_ticks()
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
    perf.heightSample = (core.cpu_ticks() - heightStart) / ticks_per_ms
    dbg(string.format("[PERF] Height sampling: %.2f ms", perf.heightSample))

    -- Start async floor snapping (non-blocking, processes over multiple frames)
    start_floor_snapping(waypoints, startZ)

    -- Total time and summary
    perf.total = (core.cpu_ticks() - totalStart) / ticks_per_ms
    dbg("=== PERFORMANCE SUMMARY ===")
    dbg(string.format("[PERF] Polygon lookup: %.2f ms", perf.polyLookup))
    dbg(string.format("[PERF] A* search:      %.2f ms", perf.astar))
    dbg(string.format("[PERF] Funnel:         %.2f ms", perf.funnel))
    dbg(string.format("[PERF] Height sample:  %.2f ms", perf.heightSample))
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

-- =========================
-- Recorded Path Fallback System
-- =========================
-- When A* fails due to navmesh gaps, use manually recorded paths as fallback

local RecordedPaths = {
    paths = {},  -- Array of {mapId, startX, startY, startZ, endX, endY, endZ, waypoints}
    match_radius = 5.0,  -- Match within 5 yards of start/end
}

-- Add a recorded path to the fallback system
function NavQuery.add_recorded_path(mapId, waypoints)
    if not waypoints or #waypoints < 2 then
        return false, "Need at least 2 waypoints"
    end

    local first = waypoints[1]
    local last = waypoints[#waypoints]

    local path = {
        mapId = mapId,
        startX = first.x,
        startY = first.y,
        startZ = first.z,
        endX = last.x,
        endY = last.y,
        endZ = last.z,
        waypoints = waypoints,
    }

    -- Check if we already have a similar path
    for i, existing in ipairs(RecordedPaths.paths) do
        if existing.mapId == mapId then
            local sd = dist3D(existing.startX, existing.startY, existing.startZ,
                              path.startX, path.startY, path.startZ)
            local ed = dist3D(existing.endX, existing.endY, existing.endZ,
                              path.endX, path.endY, path.endZ)
            if sd < RecordedPaths.match_radius and ed < RecordedPaths.match_radius then
                -- Replace existing similar path
                RecordedPaths.paths[i] = path
                return true, "Replaced existing path"
            end
        end
    end

    table.insert(RecordedPaths.paths, path)
    return true, string.format("Added path #%d (%d waypoints)", #RecordedPaths.paths, #waypoints)
end

-- Find a gap bridge based on Z-levels AND proximity
-- Only use a bridge if start is near entry OR end is near exit
function NavQuery.find_gap_bridge(mapId, startX, startY, startZ, endX, endY, endZ)
    local query_z_diff = math.abs(startZ - endZ)
    local PROXIMITY_RADIUS = 50  -- Must be within 50 yards of bridge entry/exit

    for _, path in ipairs(RecordedPaths.paths) do
        if path.mapId == mapId then
            -- Check Z difference requirement
            if query_z_diff > 10 then
                -- Get bridge entry/exit
                local entry = path.waypoints[1]
                local exit = path.waypoints[#path.waypoints]

                -- Check proximity: start near entry AND end near exit (forward)
                local start_to_entry = dist2D(startX, startY, entry.x, entry.y)
                local end_to_exit = dist2D(endX, endY, exit.x, exit.y)

                -- Check proximity: start near exit AND end near entry (reverse)
                local start_to_exit = dist2D(startX, startY, exit.x, exit.y)
                local end_to_entry = dist2D(endX, endY, entry.x, entry.y)

                local forward_ok = start_to_entry < PROXIMITY_RADIUS and end_to_exit < PROXIMITY_RADIUS
                local reverse_ok = start_to_exit < PROXIMITY_RADIUS and end_to_entry < PROXIMITY_RADIUS

                if forward_ok then
                    return {waypoints = path.waypoints}, "forward"
                elseif reverse_ok then
                    local reversed = {}
                    for i = #path.waypoints, 1, -1 do
                        reversed[#reversed + 1] = path.waypoints[i]
                    end
                    return {waypoints = reversed}, "reverse"
                end
                -- Not close enough to this bridge, try next
            end
        end
    end

    return nil, "no_match"
end

-- Find a recorded path that connects start to end (or end to start, reversed)
-- Uses Z-level matching: if start/end are on different floors, use recorded path to bridge
function NavQuery.find_recorded_path(mapId, startX, startY, startZ, endX, endY, endZ)
    local radius = RecordedPaths.match_radius
    local z_tolerance = 10.0  -- Z must be within 10 yards of recorded path endpoint Z

    for _, path in ipairs(RecordedPaths.paths) do
        if path.mapId == mapId then
            -- Check if start is near recorded start (2D) AND on same floor (Z)
            local sd_2d = dist2D(path.startX, path.startY, startX, startY)
            local sd_z = math.abs(path.startZ - startZ)

            -- Check if end is on same floor as recorded end (Z)
            local ed_z = math.abs(path.endZ - endZ)

            -- Forward match: start near recorded start, end on same floor level as recorded end
            if sd_2d < radius and sd_z < z_tolerance and ed_z < z_tolerance then
                -- Forward match - return copy of waypoints
                local result = {}
                for i, wp in ipairs(path.waypoints) do
                    result[i] = {x = wp.x, y = wp.y, z = wp.z}
                end
                return result, "forward"
            end

            -- Check reverse direction
            local rs_2d = dist2D(path.endX, path.endY, startX, startY)
            local rs_z = math.abs(path.endZ - startZ)
            local re_z = math.abs(path.startZ - endZ)

            -- Reverse match: start near recorded end, end on same floor level as recorded start
            if rs_2d < radius and rs_z < z_tolerance and re_z < z_tolerance then
                -- Reverse match - return reversed copy
                local result = {}
                for i = #path.waypoints, 1, -1 do
                    local wp = path.waypoints[i]
                    result[#result + 1] = {x = wp.x, y = wp.y, z = wp.z}
                end
                return result, "reverse"
            end

            -- Floor bridge match: if query crosses floors and recorded path bridges those floors
            -- Check if query goes from high Z to low Z (or vice versa)
            local query_z_diff = math.abs(startZ - endZ)
            local path_z_diff = math.abs(path.startZ - path.endZ)

            -- Both have significant Z difference (multi-floor)
            if query_z_diff > 20 and path_z_diff > 20 then
                -- Check if floors match (high->low or low->high)
                local query_goes_down = startZ > endZ
                local path_goes_down = path.startZ > path.endZ

                if query_goes_down == path_goes_down then
                    -- Same direction - use forward
                    -- Just need start to be on same floor level
                    if sd_z < z_tolerance then
                        local result = {}
                        for i, wp in ipairs(path.waypoints) do
                            result[i] = {x = wp.x, y = wp.y, z = wp.z}
                        end
                        return result, "floor_bridge_forward"
                    end
                else
                    -- Opposite direction - use reverse
                    if rs_z < z_tolerance then
                        local result = {}
                        for i = #path.waypoints, 1, -1 do
                            local wp = path.waypoints[i]
                            result[#result + 1] = {x = wp.x, y = wp.y, z = wp.z}
                        end
                        return result, "floor_bridge_reverse"
                    end
                end
            end
        end
    end

    return nil, "no_match"
end

-- Get count of stored recorded paths
function NavQuery.get_recorded_path_count()
    return #RecordedPaths.paths
end

-- Clear all recorded paths
function NavQuery.clear_recorded_paths()
    RecordedPaths.paths = {}
end

-- Load the hardcoded gap bridge path (short path that connects the navmesh gap)
function NavQuery.load_spiral_ramp_path()
    -- This is the small gap in the spiral ramp where the navmesh is broken
    -- Z goes from ~21.81 (upper edge) to ~20.16 (lower edge)
    local gap_path = {
        {x=1372.82, y=-4916.68, z=21.81},
        {x=1372.26, y=-4915.52, z=21.46},
        {x=1371.98, y=-4914.22, z=20.16},
    }

    local mapId = 1  -- Kalimdor
    local ok, msg = NavQuery.add_recorded_path(mapId, gap_path)
    return ok, msg
end

return NavQuery
