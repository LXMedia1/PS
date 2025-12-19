-- Cross-Tile Edge Resolver
-- Uses edge hashing for O(n) resolution instead of O(n²) brute-force
-- Epsilon-based quantization handles floating-point differences at tile boundaries
--
-- IMPORTANT: Includes Z validation to prevent false links between different floors
-- (ground ↔ roof connections were causing paths to "teleport" between vertical levels)
--
-- NOTE: Layer field now available in tiles for future multi-level support

local EdgeResolver = {}

-- Epsilon for vertex matching (from test_cross_tile_connections results)
-- eps=0.30 gives 98.7% match rate for XY
local EPSILON_XY = 0.30
local INV_EPS_XY = 1.0 / EPSILON_XY

-- Maximum vertical difference allowed for edge connections
-- Uses tile's walkableClimb when available, otherwise this default
local DEFAULT_MAX_CLIMB = 2.0

-- Quantize a coordinate to epsilon grid
local function quantize_xy(v)
    return math.floor(v * INV_EPS_XY + 0.5)
end

-- Create canonical edge key from two 2D endpoints (XY only for hashing)
-- Key is sorted so that AB == BA
local function edge_key_xy(ax, ay, bx, by)
    local axq = quantize_xy(ax)
    local ayq = quantize_xy(ay)
    local bxq = quantize_xy(bx)
    local byq = quantize_xy(by)

    -- Canonical order: smaller point first
    if axq > bxq or (axq == bxq and ayq > byq) then
        axq, ayq, bxq, byq = bxq, byq, axq, ayq
    end

    -- String key (fast in Lua for table indexing)
    return axq .. "," .. ayq .. "|" .. bxq .. "," .. byq
end

-- Check if two edge Z values are compatible (within MAX_CLIMB)
-- Handles both same-order and reversed-order endpoint matching
local function edge_z_compatible(az1, bz1, az2, bz2, maxClimb)
    -- Compare corresponding endpoints; allow reversed ordering
    -- d1: A1↔A2, B1↔B2 (same order)
    -- d2: A1↔B2, B1↔A2 (reversed order)
    local d1 = math.abs(az1 - az2) + math.abs(bz1 - bz2)
    local d2 = math.abs(az1 - bz2) + math.abs(bz1 - az2)
    local avgDiff = math.min(d1, d2) * 0.5
    return avgDiff <= maxClimb, avgDiff
end

-- Build edge map for a tile's external edges
-- Returns: map[key] = list of {tileId, poly, edge, dir, z1, z2}
-- Note: Multiple edges can have same XY key but different Z (multi-level)
function EdgeResolver.build_edge_map(soa)
    local map = {}
    local count = 0

    for p = 1, soa.polyCount do
        local base = (p - 1) * 6
        local nv = soa.pVertCount[p]

        for e = 1, nv do
            local nei = soa.pNeis[base + e]

            -- Check if external edge (>= 0x8000)
            if nei >= 0x8000 then
                local v1 = soa.pVerts[base + e]
                -- Next vertex wraps around
                local nextEdge = (e % nv) + 1
                local v2 = soa.pVerts[base + nextEdge]

                if v1 > 0 and v2 > 0 then
                    -- Use XY for key (Z is validated separately)
                    local key = edge_key_xy(
                        soa.vx[v1], soa.vy[v1],
                        soa.vx[v2], soa.vy[v2]
                    )

                    local edgeInfo = {
                        tileId = soa.tileId,
                        poly = p,
                        edge = e,
                        dir = nei - 0x8000,  -- Direction code (0,2,4,6)
                        -- Store Z for validation (CRITICAL for multi-level)
                        z1 = soa.vz[v1],
                        z2 = soa.vz[v2],
                        x1 = soa.vx[v1], y1 = soa.vy[v1],  -- Store XY for debug
                        x2 = soa.vx[v2], y2 = soa.vy[v2],
                    }

                    -- Use list instead of single entry (multi-level: same XY, diff Z)
                    if not map[key] then
                        map[key] = {}
                    end
                    map[key][#map[key] + 1] = edgeInfo
                    count = count + 1
                end
            end
        end
    end

    return map, count
end

-- Resolve cross-tile edges between two adjacent SoA tiles
-- Mutates soaA and soaB by filling extToTile/extToPoly/extToEdge
-- Returns: number of resolved edges
-- IMPORTANT: Now validates Z to prevent ground↔roof false links
-- Uses tile's walkableClimb when available
function EdgeResolver.resolve(soaA, soaB)
    local Debug = require("modules/debug")
    local mapA, countA = EdgeResolver.build_edge_map(soaA)
    local mapB, countB = EdgeResolver.build_edge_map(soaB)

    -- Use minimum walkableClimb from both tiles (or default)
    local maxClimb = math.min(
        soaA.walkableClimb or DEFAULT_MAX_CLIMB,
        soaB.walkableClimb or DEFAULT_MAX_CLIMB
    )

    local resolved = 0
    local rejectedZ = 0  -- Count of rejected due to Z difference

    -- Match edges from A to B (now with Z validation)
    for key, listA in pairs(mapA) do
        local listB = mapB[key]

        if listB then
            -- Found XY match - now validate Z for each pair
            for _, infoA in ipairs(listA) do
                local bestB = nil
                local bestZDiff = math.huge

                -- Find best Z-compatible match from B
                for _, infoB in ipairs(listB) do
                    local compatible, avgDiff = edge_z_compatible(
                        infoA.z1, infoA.z2,
                        infoB.z1, infoB.z2,
                        maxClimb
                    )

                    if compatible and avgDiff < bestZDiff then
                        bestB = infoB
                        bestZDiff = avgDiff
                    end
                end

                if bestB then
                    -- Valid Z-compatible match found
                    local baseA = (infoA.poly - 1) * 6 + infoA.edge
                    local baseB = (bestB.poly - 1) * 6 + bestB.edge

                    -- A -> B
                    soaA.extToTile[baseA] = soaB.tileId
                    soaA.extToPoly[baseA] = bestB.poly
                    soaA.extToEdge[baseA] = bestB.edge

                    -- B -> A
                    soaB.extToTile[baseB] = soaA.tileId
                    soaB.extToPoly[baseB] = infoA.poly
                    soaB.extToEdge[baseB] = infoA.edge

                    resolved = resolved + 1
                else
                    -- XY matched but Z rejected (multi-level case!)
                    rejectedZ = rejectedZ + 1
                end
            end
        end
    end

    if rejectedZ > 0 then
        Debug.log(string.format("[EdgeResolver] Rejected %d edges due to Z difference > %.1f (multi-level protection)",
            rejectedZ, maxClimb))
    end

    return resolved
end

-- Resolve all cross-tile edges for a set of tiles
-- tiles: table of SoA tiles indexed by tileId
-- Returns: total resolved edges
function EdgeResolver.resolve_all(tiles)
    local tileList = {}
    for tileId, tile in pairs(tiles) do
        tileList[#tileList + 1] = tile
    end

    local total = 0

    -- Compare each pair of tiles
    for i = 1, #tileList do
        for j = i + 1, #tileList do
            local soaA = tileList[i]
            local soaB = tileList[j]

            -- Only resolve adjacent tiles (Manhattan distance = 1)
            local dx = math.abs(soaA.tileX - soaB.tileX)
            local dy = math.abs(soaA.tileY - soaB.tileY)

            if (dx == 1 and dy == 0) or (dx == 0 and dy == 1) then
                local resolved = EdgeResolver.resolve(soaA, soaB)
                total = total + resolved
            end
        end
    end

    return total
end

-- Get epsilon XY value (for debugging/testing)
function EdgeResolver.get_epsilon_xy()
    return EPSILON_XY
end

-- Set epsilon XY value (for testing different thresholds)
function EdgeResolver.set_epsilon_xy(eps)
    EPSILON_XY = eps
    INV_EPS_XY = 1.0 / eps
end

-- Get max climb threshold
function EdgeResolver.get_max_climb()
    return DEFAULT_MAX_CLIMB
end

-- Set max climb threshold (for testing different values)
function EdgeResolver.set_max_climb(climb)
    DEFAULT_MAX_CLIMB = climb
end

return EdgeResolver
