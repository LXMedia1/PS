-- Cross-Tile Edge Resolver
-- Uses edge hashing for O(n) resolution instead of O(n²) brute-force
-- Epsilon-based quantization handles floating-point differences at tile boundaries

local EdgeResolver = {}

-- Epsilon for vertex matching (from test_cross_tile_connections results)
-- eps=0.30 gives 98.7% match rate
local EPSILON = 0.30
local INV_EPS = 1.0 / EPSILON

-- Quantize a coordinate to epsilon grid
local function quantize(v)
    return math.floor(v * INV_EPS + 0.5)
end

-- Create canonical edge key from two 2D endpoints
-- Key is sorted so that AB == BA
local function edge_key(ax, ay, bx, by)
    local axq = quantize(ax)
    local ayq = quantize(ay)
    local bxq = quantize(bx)
    local byq = quantize(by)

    -- Canonical order: smaller point first
    if axq > bxq or (axq == bxq and ayq > byq) then
        axq, ayq, bxq, byq = bxq, byq, axq, ayq
    end

    -- String key (fast in Lua for table indexing)
    return axq .. "," .. ayq .. "|" .. bxq .. "," .. byq
end

-- Build edge map for a tile's external edges
-- Returns: map[key] = {tileId, poly, edge, dir}
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
                    -- Use XY for key (Z is height, less reliable for matching)
                    local key = edge_key(
                        soa.vx[v1], soa.vy[v1],
                        soa.vx[v2], soa.vy[v2]
                    )

                    map[key] = {
                        tileId = soa.tileId,
                        poly = p,
                        edge = e,
                        dir = nei - 0x8000,  -- Direction code (0,2,4,6)
                        -- Store Z for validation
                        z1 = soa.vz[v1],
                        z2 = soa.vz[v2],
                    }
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
function EdgeResolver.resolve(soaA, soaB)
    local Debug = require("modules/debug")
    local mapA, countA = EdgeResolver.build_edge_map(soaA)
    local mapB, countB = EdgeResolver.build_edge_map(soaB)

    Debug.log(string.format("[EdgeResolver] Tile A(%d,%d) has %d external edges, Tile B(%d,%d) has %d external edges",
        soaA.tileX, soaA.tileY, countA, soaB.tileX, soaB.tileY, countB))

    local resolved = 0

    -- Match edges from A to B
    for key, infoA in pairs(mapA) do
        local infoB = mapB[key]

        if infoB then
            -- Found matching edge - link both directions
            local baseA = (infoA.poly - 1) * 6 + infoA.edge
            local baseB = (infoB.poly - 1) * 6 + infoB.edge

            -- A -> B
            soaA.extToTile[baseA] = soaB.tileId
            soaA.extToPoly[baseA] = infoB.poly
            soaA.extToEdge[baseA] = infoB.edge

            -- B -> A
            soaB.extToTile[baseB] = soaA.tileId
            soaB.extToPoly[baseB] = infoA.poly
            soaB.extToEdge[baseB] = infoA.edge

            resolved = resolved + 1
        end
    end

    -- Log some unmatched keys for debugging
    if resolved == 0 and countA > 0 and countB > 0 then
        local samplesA = {}
        local samplesB = {}
        local n = 0
        for key, _ in pairs(mapA) do
            n = n + 1
            if n <= 3 then samplesA[n] = key end
        end
        n = 0
        for key, _ in pairs(mapB) do
            n = n + 1
            if n <= 3 then samplesB[n] = key end
        end
        Debug.log(string.format("[EdgeResolver] No matches! Sample A keys: %s", table.concat(samplesA, "; ")))
        Debug.log(string.format("[EdgeResolver] No matches! Sample B keys: %s", table.concat(samplesB, "; ")))
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

-- Get epsilon value (for debugging/testing)
function EdgeResolver.get_epsilon()
    return EPSILON
end

-- Set epsilon value (for testing different thresholds)
function EdgeResolver.set_epsilon(eps)
    EPSILON = eps
    INV_EPS = 1.0 / eps
end

return EdgeResolver
