-- SoA (Structure of Arrays) Tile Converter
-- Converts parsed tile data to flat array format for fast A* access
-- Tables-of-tables kill performance at 10k polys/tile. Flat arrays are 5-10x faster.

local TileConverter = {}

-- Create a unique tile ID from map, x, y coordinates
-- Format: mapId * 10000 + tileX * 100 + tileY
function TileConverter.tile_id(mapId, tileX, tileY)
    return mapId * 10000 + tileX * 100 + tileY
end

-- Decode tile ID back to components
function TileConverter.decode_tile_id(tileId)
    local mapId = math.floor(tileId / 10000)
    local rem = tileId - mapId * 10000
    local tileX = math.floor(rem / 100)
    local tileY = rem - tileX * 100
    return mapId, tileX, tileY
end

-- Convert parsed tile to SoA format
-- Input: tile from tile_parser.lua
-- Output: SoA tile optimized for A* access
function TileConverter.convert(tile, mapId)
    local mh = tile.meshHeader
    local polyCount = mh.polyCount
    local vertCount = mh.vertCount

    -- Build flat vertex arrays from the array of {x,y,z} objects
    local vx, vy, vz = {}, {}, {}
    for i = 1, vertCount do
        local v = tile.vertices[i]
        vx[i] = v.x
        vy[i] = v.y
        vz[i] = v.z
    end

    local soa = {
        -- Metadata
        mapId = mapId,
        tileX = tile.tileX,
        tileY = tile.tileY,
        layer = tile.layer or 0,  -- For multi-level (ground vs roof at same X,Y)
        tileId = TileConverter.tile_id(mapId, tile.tileX, tile.tileY),
        polyCount = polyCount,
        vertCount = vertCount,

        -- Navigation parameters (from dtMeshHeader)
        walkableHeight = mh.walkableHeight or 2.0,  -- Agent height
        walkableRadius = mh.walkableRadius or 0.6,  -- Agent radius
        walkableClimb = mh.walkableClimb or 0.6,    -- Max step height
        offMeshBase = mh.offMeshBase or 0,          -- Where off-mesh polys start

        -- Vertex arrays (1-based)
        vx = vx,
        vy = vy,
        vz = vz,

        -- Per-polygon arrays (1-based poly index)
        pVertCount = {},  -- u8: vertex count per poly (3-6)
        pArea = {},       -- u8: area type (0=ground, 1=water, 2=road, 3=danger)
        pFlags = {},      -- u16: flags (WALK, SWIM, etc)
        pPolyType = {},   -- u8: poly type (0=ground, 1=offmesh)
        pFirstLink = {},  -- u32: first link index for each polygon

        -- Packed per-poly edge arrays: index = (poly-1)*6 + edge
        -- This allows O(1) access to any edge of any polygon
        pVerts = {},  -- vertex indices (1-based into vx/vy/vz)
        pNeis = {},   -- neighbor values from file (< 0x8000 = same tile, >= 0x8000 = external)

        -- Precomputed polygon centers (for A* heuristic and cost)
        pCx = {},
        pCy = {},
        pCz = {},

        -- Cross-tile adjacency (filled by edge_resolver)
        -- Index = (poly-1)*6 + edge, same as pVerts/pNeis
        extToTile = {},  -- tileId of neighbor tile, or 0 if not resolved
        extToPoly = {},  -- polygon index in neighbor tile, or 0
        extToEdge = {},  -- edge index in neighbor tile, or 0

        -- Detail meshes for height sampling (keep original format)
        detailMeshes = tile.detailMeshes or {},
        detailVx = {},
        detailVy = {},
        detailVz = {},
        detailTris = {},  -- Will be flattened below

        -- BVH for point-to-polygon lookup
        bvNodes = tile.bvNodes or {},
        bvQuantFactor = mh.bvQuantFactor,
        bmin = {mh.bmin[1], mh.bmin[2], mh.bmin[3]},
        bmax = {mh.bmax[1], mh.bmax[2], mh.bmax[3]},

        -- Off-mesh connections (jumps/teleports)
        offMeshConnections = tile.offMeshConnections or {},

        -- Links for cross-tile adjacency (pre-computed by Detour)
        -- Flat array: [i*5+1..5] = refLo, refHi, next, edge+side*256, bmin+bmax*256
        links = {},
        linkCount = 0,

        -- Liquid data (for water detection and cost)
        liquid = tile.liquid,
    }

    -- Convert polygons to packed format
    for p = 1, polyCount do
        local poly = tile.polygons[p]
        local nv = poly.vertCount

        soa.pVertCount[p] = nv
        soa.pArea[p] = poly.area or 0       -- Area type (0=ground, 1=water, etc) - fixed from poly.areaType
        soa.pFlags[p] = poly.flags or 0     -- Polygon flags (WALK, SWIM, etc)
        soa.pPolyType[p] = poly.polyType or 0  -- Poly type (0=ground, 1=offmesh)
        soa.pFirstLink[p] = poly.firstLink or 0  -- First link index for this polygon

        local base = (p - 1) * 6
        local cx, cy, cz = 0, 0, 0

        for e = 1, 6 do
            -- Vertex indices are 0-based from Detour, convert to 1-based for Lua
            local vi = poly.verts[e]
            if vi then
                vi = vi + 1  -- Convert 0-based Detour index to 1-based Lua index
            else
                vi = 0
            end
            local nei = poly.neis[e] or 0

            soa.pVerts[base + e] = vi
            soa.pNeis[base + e] = nei

            -- Initialize cross-tile adjacency to 0 (unresolved)
            soa.extToTile[base + e] = 0
            soa.extToPoly[base + e] = 0
            soa.extToEdge[base + e] = 0

            -- Accumulate center (only for actual vertices)
            if e <= nv and vi > 0 then
                cx = cx + soa.vx[vi]
                cy = cy + soa.vy[vi]
                cz = cz + soa.vz[vi]
            end
        end

        -- Compute center
        soa.pCx[p] = cx / nv
        soa.pCy[p] = cy / nv
        soa.pCz[p] = cz / nv
    end

    -- Convert detail vertices to flat arrays
    if tile.detailVerts then
        for i, dv in ipairs(tile.detailVerts) do
            soa.detailVx[i] = dv.x
            soa.detailVy[i] = dv.y
            soa.detailVz[i] = dv.z
        end
    end

    -- Flatten detail triangles to flat array format
    -- nav_query expects: detailTris[(triBase + t) * 4 + 1..4] = {v0, v1, v2, flags}
    if tile.detailTris then
        for i, tri in ipairs(tile.detailTris) do
            local base = (i - 1) * 4
            soa.detailTris[base + 1] = tri.v0
            soa.detailTris[base + 2] = tri.v1
            soa.detailTris[base + 3] = tri.v2
            soa.detailTris[base + 4] = tri.flags
        end
    end

    -- Flatten links to flat array format (5 values per link)
    -- NOTE: Links in mmtile are mostly internal. External links exist but aren't
    -- usable for cross-tile resolution (no owner polygon info). We keep them
    -- stored for potential future use but use EdgeResolver for cross-tile matching.
    if tile.links and #tile.links > 0 then
        soa.linkCount = #tile.links
        for i = 1, #tile.links do
            local link = tile.links[i]
            local base = (i - 1) * 5
            soa.links[base + 1] = link.refLo or 0
            soa.links[base + 2] = link.refHi or 0
            soa.links[base + 3] = link.next or 0xFFFFFFFF
            soa.links[base + 4] = (link.edge or 0) + (link.side or 0xFF) * 256
            soa.links[base + 5] = (link.bmin or 0) + (link.bmax or 0) * 256
        end
    end

    -- Index off-mesh connections for O(1) lookup by polygon
    TileConverter.index_offmesh(soa)

    return soa
end

-- Build off-mesh connection lookup table (poly -> connection index)
-- Enables fast detection of jump/teleport polygons during pathfinding
function TileConverter.index_offmesh(soa)
    soa.offMeshByPoly = {}
    if soa.offMeshConnections then
        for i = 1, #soa.offMeshConnections do
            local c = soa.offMeshConnections[i]
            -- dtOffMeshConnection.poly is the polygon index that represents this connection
            -- In Detour, off-mesh connections become special polygons
            local poly = c.poly
            if poly and poly > 0 then
                -- Convert from 0-based to 1-based if needed
                if poly >= 1 and poly <= soa.polyCount then
                    soa.offMeshByPoly[poly] = i
                end
            end
        end
    end
end

-- Get the edge vertices for a polygon edge (returns world coords)
-- edge is 1-based (1 to pVertCount[poly])
function TileConverter.get_edge_verts(soa, poly, edge)
    local nv = soa.pVertCount[poly]
    local base = (poly - 1) * 6

    local v1 = soa.pVerts[base + edge]
    -- Next vertex wraps around
    local nextEdge = (edge % nv) + 1
    local v2 = soa.pVerts[base + nextEdge]

    if v1 == 0 or v2 == 0 then
        return nil
    end

    return soa.vx[v1], soa.vy[v1], soa.vz[v1],
           soa.vx[v2], soa.vy[v2], soa.vz[v2]
end

-- Get the neighbor for a polygon edge
-- Returns: neiTileId, neiPoly, neiEdge (or 0,0,0 if no neighbor)
function TileConverter.get_neighbor(soa, poly, edge)
    local base = (poly - 1) * 6
    local nei = soa.pNeis[base + edge]

    if nei == 0 then
        -- No neighbor (wall/boundary)
        return 0, 0, 0
    elseif nei < 0x8000 then
        -- Intra-tile neighbor
        return soa.tileId, nei, 0  -- Edge unknown for intra-tile
    else
        -- External neighbor (cross-tile)
        return soa.extToTile[base + edge],
               soa.extToPoly[base + edge],
               soa.extToEdge[base + edge]
    end
end

-- Count external edges (for debugging)
function TileConverter.count_external_edges(soa)
    local count = 0
    for p = 1, soa.polyCount do
        local base = (p - 1) * 6
        local nv = soa.pVertCount[p]
        for e = 1, nv do
            if soa.pNeis[base + e] >= 0x8000 then
                count = count + 1
            end
        end
    end
    return count
end

-- Count resolved cross-tile edges
function TileConverter.count_resolved_edges(soa)
    local count = 0
    for p = 1, soa.polyCount do
        local base = (p - 1) * 6
        local nv = soa.pVertCount[p]
        for e = 1, nv do
            if soa.extToTile[base + e] ~= 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- Build index of external edges per side for slab overlap resolution
-- Called after convert(), stores edges by direction for fast neighbor lookup
-- side = nei % 256 (0=N, 2=E, 4=S, 6=W from neis[] high bits)
local DT_EXT_LINK = 0x8000

function TileConverter.build_ext_edge_index(soa)
    soa.extEdges = {}  -- [side] = array of {poly, edge, ax,ay,az, bx,by,bz}

    for side = 0, 7 do
        soa.extEdges[side] = {}
    end

    for p = 1, soa.polyCount do
        local nv = soa.pVertCount[p]
        local base = (p - 1) * 6

        for e = 1, nv do
            local nei = soa.pNeis[base + e]
            if nei >= DT_EXT_LINK then
                local side = nei % 256  -- Low byte is direction
                local i0 = soa.pVerts[base + e]
                local i1 = soa.pVerts[base + (e % nv) + 1]

                if i0 > 0 and i1 > 0 then
                    soa.extEdges[side][#soa.extEdges[side] + 1] = {
                        poly = p,
                        edge = e,
                        ax = soa.vx[i0], ay = soa.vy[i0], az = soa.vz[i0],
                        bx = soa.vx[i1], by = soa.vy[i1], bz = soa.vz[i1]
                    }
                end
            end
        end
    end
end

return TileConverter
