-- Link Resolver
-- Uses Detour's pre-computed links for cross-tile resolution
-- Hybrid approach: links guide target lookup, vertex matching finds edges

local LinkResolver = {}

-- Dedicated log file
local LINK_LOG = "link_resolver.log"
local log_initialized = false

local function link_log(msg)
    if not log_initialized then
        core.create_log_file(LINK_LOG)
        log_initialized = true
    end
    core.write_log_file(LINK_LOG, msg .. "\n")
end

local DT_NULL_LINK = 0xFFFFFFFF
local DT_EXT_LINK = 0x8000  -- neis[] value >= this means external edge

-- Direction offsets for external links (side 0-7)
-- Detour uses Recast coords: side 0=+X, 2=+Z, 4=-X, 6=-Z
-- WoW transform: wowX=recastZ, wowY=recastX
-- Tile coords: tileX = (17066-wowX)/533, tileY = (17066-wowY)/533
-- So higher tileX = lower wowX = West, higher tileY = lower wowY = South
-- Detour side -> tile offset:
--   0 = Recast +X = WoW +Y = lower tileY = {0, -1}
--   2 = Recast +Z = WoW +X = lower tileX = {-1, 0}
--   4 = Recast -X = WoW -Y = higher tileY = {0, 1}
--   6 = Recast -Z = WoW -X = higher tileX = {1, 0}
local SIDE_OFFSETS = {
    [0] = {0, -1},   -- Recast +X = WoW +Y = North (lower tileY)
    [2] = {-1, 0},   -- Recast +Z = WoW +X = East (lower tileX)
    [4] = {0, 1},    -- Recast -X = WoW -Y = South (higher tileY)
    [6] = {1, 0},    -- Recast -Z = WoW -X = West (higher tileX)
}

-- Opposite directions
local OPPOSITE_SIDE = {
    [0] = 4, [2] = 6, [4] = 0, [6] = 2,
}

-- Epsilon for vertex matching
local EPSILON_XY = 0.30
local INV_EPS = 1.0 / EPSILON_XY

-- Quantize coordinate for matching
local function quantize(v)
    return math.floor(v * INV_EPS + 0.5)
end

-- Create edge key from two vertices (XY only, canonical order)
local function edge_key(ax, ay, bx, by)
    local axq, ayq = quantize(ax), quantize(ay)
    local bxq, byq = quantize(bx), quantize(by)
    -- Canonical order: smaller first
    if axq > bxq or (axq == bxq and ayq > byq) then
        axq, ayq, bxq, byq = bxq, byq, axq, ayq
    end
    return axq .. "," .. ayq .. "|" .. bxq .. "," .. byq
end

-- Decode polygon index from 64-bit ref (bits 0-30 in refLo)
local function decode_poly(refLo)
    return refLo % 0x80000000  -- bits 0-30
end

-- Get link data from flat array
local function get_link(soa, linkIdx)
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

-- Build edge map for a tile: edge_key -> list of {poly, edge, z1, z2}
-- Only indexes external edges (neis >= 0x8000) in a specific direction
local function build_edge_map_by_side(soa, targetSide)
    local map = {}

    for p = 1, soa.polyCount do
        local neiBase = (p - 1) * 6
        local vertBase = (p - 1) * 6
        local nv = soa.pVertCount[p]

        for e = 1, nv do
            local nei = soa.pNeis[neiBase + e]
            if nei and nei >= DT_EXT_LINK then
                local side = nei % 256
                if side == targetSide then
                    local v1 = soa.pVerts[vertBase + e]
                    local nextE = (e % nv) + 1
                    local v2 = soa.pVerts[vertBase + nextE]

                    if v1 and v1 > 0 and v2 and v2 > 0 then
                        local key = edge_key(soa.vx[v1], soa.vy[v1], soa.vx[v2], soa.vy[v2])
                        if not map[key] then
                            map[key] = {}
                        end
                        table.insert(map[key], {
                            poly = p, edge = e,
                            z1 = soa.vz[v1], z2 = soa.vz[v2],
                            x1 = soa.vx[v1], y1 = soa.vy[v1],
                            x2 = soa.vx[v2], y2 = soa.vy[v2]
                        })
                    end
                end
            end
        end
    end

    return map
end

-- Build ALL external edges map for a tile (any direction)
local function build_all_external_edges(soa)
    local map = {}

    for p = 1, soa.polyCount do
        local neiBase = (p - 1) * 6
        local vertBase = (p - 1) * 6
        local nv = soa.pVertCount[p]

        for e = 1, nv do
            local nei = soa.pNeis[neiBase + e]
            if nei and nei >= DT_EXT_LINK then
                local v1 = soa.pVerts[vertBase + e]
                local nextE = (e % nv) + 1
                local v2 = soa.pVerts[vertBase + nextE]

                if v1 and v1 > 0 and v2 and v2 > 0 then
                    local key = edge_key(soa.vx[v1], soa.vy[v1], soa.vx[v2], soa.vy[v2])
                    if not map[key] then
                        map[key] = {}
                    end
                    table.insert(map[key], {
                        poly = p, edge = e,
                        side = nei % 256,
                        z1 = soa.vz[v1], z2 = soa.vz[v2]
                    })
                end
            end
        end
    end

    return map
end

-- Z validation for edge matching
local function edge_z_compatible(z1a, z2a, z1b, z2b, maxClimb)
    local d1 = math.abs(z1a - z1b) + math.abs(z2a - z2b)
    local d2 = math.abs(z1a - z2b) + math.abs(z2a - z1b)
    local avgDiff = math.min(d1, d2) * 0.5
    return avgDiff <= maxClimb
end

-- Resolve using vertex matching guided by link directions
-- For each direction, match edges between tiles using vertex positions
function LinkResolver.resolve_tile(soa, get_neighbor_fn)
    local Debug = require("modules/debug")
    local resolved = 0
    local failed = 0
    local noNeighbor = 0

    local maxClimb = soa.walkableClimb or 2.0

    -- Process each cardinal direction (0, 2, 4, 6 only in Detour)
    for _, side in ipairs({0, 2, 4, 6}) do
        local offset = SIDE_OFFSETS[side]
        if offset then
            local nx = soa.tileX + offset[1]
            local ny = soa.tileY + offset[2]
            local neiTile = get_neighbor_fn(soa.mapId, nx, ny)

            if neiTile then
                -- Build edge maps for both tiles
                -- Our tile: edges facing direction 'side'
                -- Neighbor tile: edges facing opposite direction
                local oppSide = OPPOSITE_SIDE[side]
                local ourEdges = build_edge_map_by_side(soa, side)
                local theirEdges = build_edge_map_by_side(neiTile, oppSide)

                -- Match edges by vertex key
                for key, ourList in pairs(ourEdges) do
                    local theirList = theirEdges[key]
                    if theirList then
                        -- Found XY match, now validate Z
                        for _, ourEdge in ipairs(ourList) do
                            local bestMatch = nil
                            local bestZDiff = math.huge

                            for _, theirEdge in ipairs(theirList) do
                                if edge_z_compatible(ourEdge.z1, ourEdge.z2, theirEdge.z1, theirEdge.z2, maxClimb) then
                                    local zDiff = math.abs(ourEdge.z1 - theirEdge.z1) + math.abs(ourEdge.z2 - theirEdge.z2)
                                    if zDiff < bestZDiff then
                                        bestMatch = theirEdge
                                        bestZDiff = zDiff
                                    end
                                end
                            end

                            if bestMatch then
                                -- Set cross-tile connection
                                local base = (ourEdge.poly - 1) * 6 + ourEdge.edge
                                soa.extToTile[base] = neiTile.tileId
                                soa.extToPoly[base] = bestMatch.poly
                                resolved = resolved + 1
                            else
                                failed = failed + 1
                                hasFailures = true
                            end
                        end
                    else
                        -- No XY match for this edge
                        failed = failed + #ourList
                        hasFailures = true
                    end
                end
            else
                -- Count edges facing this direction as "no neighbor"
                local ourEdges = build_edge_map_by_side(soa, side)
                for _, list in pairs(ourEdges) do
                    noNeighbor = noNeighbor + #list
                end
            end
        end
    end

    if resolved > 0 or failed > 0 or noNeighbor > 0 then
        Debug.log(string.format("[LinkResolver] Tile (%d,%d): %d resolved, %d failed, %d no neighbor",
            soa.tileX, soa.tileY, resolved, failed, noNeighbor))
    end

    return resolved, failed, noNeighbor
end

-- Resolve all tiles in a collection
function LinkResolver.resolve_all(tiles, get_neighbor_fn)
    local totalResolved = 0
    local totalFailed = 0
    local totalNoNeighbor = 0

    for _, tile in pairs(tiles) do
        local resolved, failed, noNeighbor = LinkResolver.resolve_tile(tile, get_neighbor_fn)
        totalResolved = totalResolved + resolved
        totalFailed = totalFailed + failed
        totalNoNeighbor = totalNoNeighbor + noNeighbor
    end

    return totalResolved, totalFailed, totalNoNeighbor
end

-- Debug: count external vs internal links by scanning all
function LinkResolver.count_links(soa)
    local external = 0
    local internal = 0

    if not soa.links or soa.linkCount == 0 then
        return 0, 0
    end

    for i = 0, soa.linkCount - 1 do
        local link = get_link(soa, i)
        if not link then break end

        if link.side < 8 then
            external = external + 1
        elseif link.side == 0xFF then
            internal = internal + 1
        end
    end

    return external, internal
end

return LinkResolver
