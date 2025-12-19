-- LX_Nav mmtile File Parser
-- Parses .mmtile files to extract polygon and vertex data
-- Includes detail mesh data for precise terrain following
-- Supports yieldable incremental parsing with budget:step()

local Binary = require("modules/binary")
local NavConstants = require("modules/nav_constants")

local TileParser = {}

-- Flag to enable/disable yielding (set by parse_incremental)
local yielding_enabled = false
local current_budget = nil

--- Helper to conditionally yield based on budget
local function maybe_yield(stage, i, total)
    if yielding_enabled and current_budget then
        current_budget:step(stage, i, total)
    end
end

-- Debug log state
local offset_log_created = false

-- Constants
local DT_VERTS_PER_POLYGON = 6
local MMAP_MAGIC = 0x4D4D4150

-- Structure sizes
local MMAP_TILE_HEADER_SIZE = 20
local DT_MESH_HEADER_SIZE = 100
local DT_POLY_SIZE = 32
-- Structure sizes (VERIFIED FROM F:\PS_LX\Exemple_Scripts\Lx_Nav\mmap_decode.lua)
local DT_POLY_DETAIL_SIZE = 12  -- vertBase(4) + triBase(4) + vertCount(1) + triCount(1) + padding(2) = 12 bytes
local DT_DETAIL_VERT_SIZE = 12  -- 3 QUANTIZED u32 values (NOT floats!) = 12 bytes
local DT_DETAIL_TRI_SIZE = 4    -- v0(1) + v1(1) + v2(1) + flags(1) = 4 bytes
local DT_BV_NODE_SIZE = 16      -- bmin[3](6) + bmax[3](6) + i(4) = 16 bytes
local DT_OFF_MESH_CON_SIZE = 36 -- pos[6](24) + rad(4) + poly(2) + flags(1) + side(1) + userId(4) = 36 bytes
local DT_LINK_SIZE = 16  -- Links are at END of file, not between polys and detail meshes!

--- Parse MmapTileHeader (20 bytes)
local function parse_mmap_header(data, pos)
    local header = {}
    header.mmapMagic = Binary.read_u32(data, pos); pos = pos + 4
    header.dtVersion = Binary.read_u32(data, pos); pos = pos + 4
    header.mmapVersion = Binary.read_u32(data, pos); pos = pos + 4
    header.size = Binary.read_u32(data, pos); pos = pos + 4
    header.usesLiquids = Binary.read_u8(data, pos); pos = pos + 1
    -- 3 bytes padding
    pos = pos + 3
    return header, pos
end

--- Parse dtMeshHeader (100 bytes)
local function parse_mesh_header(data, pos)
    local header = {}
    header.magic = Binary.read_i32(data, pos); pos = pos + 4
    header.version = Binary.read_i32(data, pos); pos = pos + 4
    header.x = Binary.read_i32(data, pos); pos = pos + 4
    header.y = Binary.read_i32(data, pos); pos = pos + 4
    header.layer = Binary.read_i32(data, pos); pos = pos + 4
    header.userId = Binary.read_u32(data, pos); pos = pos + 4
    header.polyCount = Binary.read_i32(data, pos); pos = pos + 4
    header.vertCount = Binary.read_i32(data, pos); pos = pos + 4
    header.maxLinkCount = Binary.read_i32(data, pos); pos = pos + 4
    header.detailMeshCount = Binary.read_i32(data, pos); pos = pos + 4
    header.detailVertCount = Binary.read_i32(data, pos); pos = pos + 4
    header.detailTriCount = Binary.read_i32(data, pos); pos = pos + 4
    header.bvNodeCount = Binary.read_i32(data, pos); pos = pos + 4
    header.offMeshConCount = Binary.read_i32(data, pos); pos = pos + 4
    header.offMeshBase = Binary.read_i32(data, pos); pos = pos + 4
    header.walkableHeight = Binary.read_f32(data, pos); pos = pos + 4
    header.walkableRadius = Binary.read_f32(data, pos); pos = pos + 4
    header.walkableClimb = Binary.read_f32(data, pos); pos = pos + 4
    header.bmin = {
        Binary.read_f32(data, pos),
        Binary.read_f32(data, pos + 4),
        Binary.read_f32(data, pos + 8)
    }
    pos = pos + 12
    header.bmax = {
        Binary.read_f32(data, pos),
        Binary.read_f32(data, pos + 4),
        Binary.read_f32(data, pos + 8)
    }
    pos = pos + 12
    header.bvQuantFactor = Binary.read_f32(data, pos); pos = pos + 4
    return header, pos
end

--- Parse vertices (3 floats each, Recast coords)
-- Yields every check_every iterations when budget is active
local function parse_vertices(data, pos, count)
    local vertices = {}
    for i = 1, count do
        local rx = Binary.read_f32(data, pos)
        local ry = Binary.read_f32(data, pos + 4)
        local rz = Binary.read_f32(data, pos + 8)
        -- Convert Recast to WoW coordinates
        -- From TileBuilder.cpp: bmax[0]=(32-tileY)*GRID, bmax[2]=(32-tileX)*GRID
        -- Combined with mesh_helper formula: tile = 32 - wow/GRID
        -- Therefore: wowX = recastZ, wowY = recastX, wowZ = recastY
        vertices[i] = {
            x = rz,   -- wowX = recastZ (NO negation!)
            y = rx,   -- wowY = recastX (NO negation!)
            z = ry    -- wowZ = recastY
        }
        pos = pos + 12
        maybe_yield("verts", i, count)
    end
    return vertices, pos
end

--- Parse polygons (32 bytes each)
-- Yields every check_every iterations when budget is active
-- Note: worldVerts and center are computed here for compatibility with existing code
local function parse_polygons(data, pos, count, vertices)
    local polygons = {}
    for i = 1, count do
        local poly = {}
        poly.firstLink = Binary.read_u32(data, pos); pos = pos + 4

        -- Vertex indices (6 x u16)
        poly.verts = {}
        for j = 1, DT_VERTS_PER_POLYGON do
            poly.verts[j] = Binary.read_u16(data, pos)
            pos = pos + 2
        end

        -- Neighbor references (6 x u16)
        poly.neis = {}
        for j = 1, DT_VERTS_PER_POLYGON do
            poly.neis[j] = Binary.read_u16(data, pos)
            pos = pos + 2
        end

        poly.flags = Binary.read_u16(data, pos); pos = pos + 2
        
        -- Decode booleans from flags
        if bit and bit.band then
            poly.isWalkable = bit.band(poly.flags, NavConstants.Flags.WALK) ~= 0
            poly.isSwimmable = bit.band(poly.flags, NavConstants.Flags.SWIM) ~= 0
        else
            -- Fallback if bit library is missing (unlikely in WoW Lua)
            poly.isWalkable = (poly.flags % 2) == 1
            poly.isSwimmable = false -- Cannot easily detect without bitwise
        end

        poly.vertCount = Binary.read_u8(data, pos); pos = pos + 1
        poly.areaAndtype = Binary.read_u8(data, pos); pos = pos + 1

        -- Extract area and type
        poly.area = poly.areaAndtype % 64  -- & 0x3f
        poly.polyType = math.floor(poly.areaAndtype / 64)  -- >> 6
        
        -- Override area based on decoded flags if needed?
        -- For now, keep as is.

        -- Get actual vertex positions for this polygon
        poly.worldVerts = {}
        for j = 1, poly.vertCount do
            local vidx = poly.verts[j] + 1  -- Lua 1-indexed
            if vertices[vidx] then
                poly.worldVerts[j] = vertices[vidx]
            end
        end

        -- Calculate polygon center
        if poly.vertCount > 0 then
            local cx, cy, cz = 0, 0, 0
            for j = 1, poly.vertCount do
                if poly.worldVerts[j] then
                    cx = cx + poly.worldVerts[j].x
                    cy = cy + poly.worldVerts[j].y
                    cz = cz + poly.worldVerts[j].z
                end
            end
            poly.center = {
                x = cx / poly.vertCount,
                y = cy / poly.vertCount,
                z = cz / poly.vertCount
            }
        end

        polygons[i] = poly
        maybe_yield("polys", i, count)
    end
    return polygons, pos
end

--- Parse links (16 bytes each for 64-bit refs)
-- Yields every check_every iterations when budget is active
local function parse_links(data, pos, count)
    local links = {}
    for i = 1, count do
        local link = {}
        -- dtPolyRef (64-bit): split into two u32
        -- Ref format: salt(12) + tile(21) + poly(31)
        link.refLo = Binary.read_u32(data, pos); pos = pos + 4
        link.refHi = Binary.read_u32(data, pos); pos = pos + 4
        link.next = Binary.read_u32(data, pos); pos = pos + 4
        link.edge = Binary.read_u8(data, pos); pos = pos + 1
        link.side = Binary.read_u8(data, pos); pos = pos + 1
        link.bmin = Binary.read_u8(data, pos); pos = pos + 1
        link.bmax = Binary.read_u8(data, pos); pos = pos + 1
        links[i] = link
        maybe_yield("links", i, count)
    end
    return links, pos
end

-- Debug: log hex dump of bytes
local function hex_dump_bytes(data, pos, count)
    local bytes = {}
    for j = 0, count - 1 do
        local b = string.byte(data, pos + j) or 0
        table.insert(bytes, string.format("%02X", b))
    end
    return table.concat(bytes, " ")
end

--- Parse detail meshes (12 bytes each: dtPolyDetail with padding)
-- Yields every check_every iterations when budget is active
local function parse_detail_meshes(data, pos, count)
    local details = {}

    for i = 1, count do
        local detail = {}
        detail.vertBase = Binary.read_u32(data, pos); pos = pos + 4
        detail.triBase = Binary.read_u32(data, pos); pos = pos + 4
        detail.vertCount = Binary.read_u8(data, pos); pos = pos + 1
        detail.triCount = Binary.read_u8(data, pos); pos = pos + 1
        pos = pos + 2  -- 2 bytes padding to reach 12 bytes total
        details[i] = detail
        maybe_yield("detailMeshes", i, count)
    end
    return details, pos
end

--- Parse detail vertices (12 bytes each: 3 floats in Recast coords)
-- Standard Detour stores detail vertices as floats (same as main vertices)
-- Yields every check_every iterations when budget is active
local function parse_detail_vertices(data, pos, count)
    local vertices = {}

    for i = 1, count do
        -- Read as floats (same as main vertices)
        local rx = Binary.read_f32(data, pos)
        local ry = Binary.read_f32(data, pos + 4)
        local rz = Binary.read_f32(data, pos + 8)
        pos = pos + 12

        -- Convert Recast to WoW coordinates (no negation!)
        vertices[i] = {
            x = rz,   -- wowX = recastZ
            y = rx,   -- wowY = recastX
            z = ry    -- wowZ = recastY
        }
        maybe_yield("detailVerts", i, count)
    end
    return vertices, pos
end

--- Parse detail triangles (4 bytes each: 3 vertex indices + flags)
-- Yields every check_every iterations when budget is active
local function parse_detail_triangles(data, pos, count)
    local triangles = {}
    for i = 1, count do
        local tri = {}
        tri.v0 = Binary.read_u8(data, pos); pos = pos + 1
        tri.v1 = Binary.read_u8(data, pos); pos = pos + 1
        tri.v2 = Binary.read_u8(data, pos); pos = pos + 1
        tri.flags = Binary.read_u8(data, pos); pos = pos + 1
        triangles[i] = tri
        maybe_yield("detailTris", i, count)
    end
    return triangles, pos
end

--- Parse BV nodes (16 bytes each: bounding volume tree for spatial queries)
-- Yields every check_every iterations when budget is active
local function parse_bv_nodes(data, pos, count)
    local nodes = {}
    for i = 1, count do
        local node = {}
        -- bmin[3] as u16
        node.bmin = {
            Binary.read_u16(data, pos),
            Binary.read_u16(data, pos + 2),
            Binary.read_u16(data, pos + 4)
        }
        pos = pos + 6
        -- bmax[3] as u16
        node.bmax = {
            Binary.read_u16(data, pos),
            Binary.read_u16(data, pos + 2),
            Binary.read_u16(data, pos + 4)
        }
        pos = pos + 6
        -- i as i32 (child index or polygon index if negative)
        node.i = Binary.read_i32(data, pos); pos = pos + 4
        nodes[i] = node
        maybe_yield("bvNodes", i, count)
    end
    return nodes, pos
end

--- Parse off-mesh connections (36 bytes each: jump/teleport links)
-- Structure: pos[6 floats] + rad[float] + poly[u16] + flags[u8] + side[u8] + userId[u32]
-- Yields every check_every iterations when budget is active
local function parse_off_mesh_connections(data, pos, count)
    local connections = {}
    for i = 1, count do
        local conn = {}
        -- Start position (3 floats in Recast coords)
        local sx = Binary.read_f32(data, pos)
        local sy = Binary.read_f32(data, pos + 4)
        local sz = Binary.read_f32(data, pos + 8)
        pos = pos + 12
        -- End position (3 floats in Recast coords)
        local ex = Binary.read_f32(data, pos)
        local ey = Binary.read_f32(data, pos + 4)
        local ez = Binary.read_f32(data, pos + 8)
        pos = pos + 12

        -- Convert Recast to WoW coordinates
        conn.startPos = { x = sz, y = sx, z = sy }
        conn.endPos = { x = ez, y = ex, z = ey }

        conn.radius = Binary.read_f32(data, pos); pos = pos + 4
        conn.poly = Binary.read_u16(data, pos); pos = pos + 2
        conn.flags = Binary.read_u8(data, pos); pos = pos + 1
        conn.side = Binary.read_u8(data, pos); pos = pos + 1
        conn.userId = Binary.read_u32(data, pos); pos = pos + 4

        -- Determine connection type from flags
        -- DT_OFFMESH_CON_BIDIR = 1 (bidirectional)
        conn.bidirectional = (conn.flags % 2) == 1

        connections[i] = conn
        maybe_yield("offMesh", i, count)
    end
    return connections, pos
end

--- Parse liquid data (appended to end of tile)
-- Yields every check_every iterations when budget is active
local function parse_liquid(data, pos)
    -- Safety check: header is 36 bytes (9 * u32)
    if pos + 36 > #data + 1 then return nil, pos end

    local liquid = {}
    liquid.version = Binary.read_u32(data, pos); pos = pos + 4
    liquid.tileX = Binary.read_u32(data, pos); pos = pos + 4
    liquid.tileY = Binary.read_u32(data, pos); pos = pos + 4
    liquid.layer = Binary.read_u32(data, pos); pos = pos + 4
    liquid.x = Binary.read_u32(data, pos); pos = pos + 4
    liquid.y = Binary.read_u32(data, pos); pos = pos + 4
    liquid.width = Binary.read_u32(data, pos); pos = pos + 4
    liquid.height = Binary.read_u32(data, pos); pos = pos + 4
    liquid.type = Binary.read_u32(data, pos); pos = pos + 4
    
    -- Parse Liquid Data (height map/flow)
    -- TrinityCore format: count * 5 bytes (4 byte float + 1 byte flag)
    local count = liquid.width * liquid.height
    local dataSize = count * 5
    
    if pos + dataSize <= #data + 1 then
        -- Read data into a simple table for now (skipping complex parsing)
        -- We just need to advance position mostly, but storing raw data might be useful later.
        -- For now, just skip to save memory/time as we only need the Type (water/slime) for cost.
        pos = pos + dataSize
        liquid.hasData = true
    else
        -- Warning: truncated data
        pos = #data + 1
        liquid.hasData = false
    end

    maybe_yield("liquid", 1, 1)
    return liquid, pos
end

--- Parse full mmtile file
-- @param data string Binary data
-- @return table|nil tile Parsed tile data
-- @return string|nil error Error message
function TileParser.parse(data)
    if not data or #data < MMAP_TILE_HEADER_SIZE + DT_MESH_HEADER_SIZE then
        return nil, string.format("Data too short: %d bytes (need at least %d)",
            data and #data or 0, MMAP_TILE_HEADER_SIZE + DT_MESH_HEADER_SIZE)
    end

    local tile = {}
    local pos = 1

    -- Parse MmapTileHeader
    tile.mmapHeader, pos = parse_mmap_header(data, pos)

    -- Validate magic
    if tile.mmapHeader.mmapMagic ~= MMAP_MAGIC then
        return nil, string.format("Invalid magic: 0x%08X (expected 0x4D4D4150)",
            tile.mmapHeader.mmapMagic)
    end

    -- Parse dtMeshHeader
    tile.meshHeader, pos = parse_mesh_header(data, pos)

    -- Calculate data offsets
    local vertStart = pos
    local vertEnd = vertStart + (tile.meshHeader.vertCount * 12) - 1
    local polyStart = vertEnd + 1
    -- local polyEnd = polyStart + (tile.meshHeader.polyCount * DT_POLY_SIZE) - 1

    -- Parse vertices
    tile.vertices, pos = parse_vertices(data, vertStart, tile.meshHeader.vertCount)

    -- Parse polygons
    tile.polygons, pos = parse_polygons(data, polyStart, tile.meshHeader.polyCount, tile.vertices)

    -- Parse Links
    tile.links = {}
    if tile.meshHeader.maxLinkCount > 0 then
        tile.links, pos = parse_links(data, pos, tile.meshHeader.maxLinkCount)
    end

    -- Parse detail meshes
    tile.detailMeshes = {}
    if tile.meshHeader.detailMeshCount > 0 then
        tile.detailMeshes, pos = parse_detail_meshes(data, pos, tile.meshHeader.detailMeshCount)
    end

    -- Parse detail verts
    tile.detailVerts = {}
    if tile.meshHeader.detailVertCount > 0 then
        tile.detailVerts, pos = parse_detail_vertices(data, pos, tile.meshHeader.detailVertCount)
    end

    -- Parse detail tris
    tile.detailTris = {}
    if tile.meshHeader.detailTriCount > 0 then
        tile.detailTris, pos = parse_detail_triangles(data, pos, tile.meshHeader.detailTriCount)
    end

    -- Parse BV nodes (for spatial queries)
    tile.bvNodes = {}
    if tile.meshHeader.bvNodeCount > 0 then
        tile.bvNodes, pos = parse_bv_nodes(data, pos, tile.meshHeader.bvNodeCount)
    end

    -- Parse off-mesh connections (jump/teleport links) - CRITICAL for pathfinding!
    tile.offMeshConnections = {}
    if tile.meshHeader.offMeshConCount > 0 then
        tile.offMeshConnections, pos = parse_off_mesh_connections(data, pos, tile.meshHeader.offMeshConCount)
    end
    
    -- Parse Liquid (At the very end)
    tile.liquid = nil
    if tile.mmapHeader.usesLiquids == 1 then
        tile.liquid, pos = parse_liquid(data, pos)
    end

    -- Store tile coordinates and navigation parameters
    tile.tileX = tile.meshHeader.x
    tile.tileY = tile.meshHeader.y
    tile.layer = tile.meshHeader.layer  -- For multi-level (ground vs roof)
    tile.walkableClimb = tile.meshHeader.walkableClimb  -- Max step height

    -- Calculate bounds in WoW coords
    -- Conversion: wowX = recastZ, wowY = recastX, wowZ = recastY
    local bmin = tile.meshHeader.bmin
    local bmax = tile.meshHeader.bmax
    tile.boundsWow = {
        min = { x = bmin[3], y = bmin[1], z = bmin[2] },
        max = { x = bmax[3], y = bmax[1], z = bmax[2] }
    }

    return tile, nil
end

--- Parse mmtile file from path
-- @param filename string Path relative to scripts_data
-- @return table|nil tile
-- @return string|nil error
function TileParser.parse_file(filename)
    local data = core.read_data_file(filename)
    if not data or #data == 0 then
        return nil, "Failed to read file: " .. tostring(filename)
    end
    return TileParser.parse(data)
end

--- Parse mmtile file incrementally with coroutine yielding
-- This function is designed to be called from within a coroutine
-- It will yield periodically based on the budget to prevent frame freezes
-- @param data string Binary data
-- @param budget Budget object from budget.lua
-- @return table|nil tile Parsed tile data
-- @return string|nil error Error message
function TileParser.parse_incremental(data, budget)
    if not data or #data < MMAP_TILE_HEADER_SIZE + DT_MESH_HEADER_SIZE then
        return nil, string.format("Data too short: %d bytes (need at least %d)",
            data and #data or 0, MMAP_TILE_HEADER_SIZE + DT_MESH_HEADER_SIZE)
    end

    -- Enable yielding for this parse
    yielding_enabled = true
    current_budget = budget

    local tile = {}
    local pos = 1

    -- Parse MmapTileHeader (fast, no yield needed)
    tile.mmapHeader, pos = parse_mmap_header(data, pos)

    -- Validate magic
    if tile.mmapHeader.mmapMagic ~= MMAP_MAGIC then
        yielding_enabled = false
        current_budget = nil
        return nil, string.format("Invalid magic: 0x%08X (expected 0x4D4D4150)",
            tile.mmapHeader.mmapMagic)
    end

    -- Parse dtMeshHeader (fast, no yield needed)
    tile.meshHeader, pos = parse_mesh_header(data, pos)

    -- Calculate data offsets
    local vertStart = pos
    local vertEnd = vertStart + (tile.meshHeader.vertCount * 12) - 1
    local polyStart = vertEnd + 1
    -- local polyEnd = polyStart + (tile.meshHeader.polyCount * DT_POLY_SIZE) - 1

    -- Parse vertices (YIELDS periodically)
    tile.vertices, pos = parse_vertices(data, vertStart, tile.meshHeader.vertCount)

    -- Parse polygons (YIELDS periodically)
    tile.polygons, pos = parse_polygons(data, polyStart, tile.meshHeader.polyCount, tile.vertices)

    -- Parse Links (YIELDS periodically)
    -- NOTE: Links in mmtile are mostly internal (side=0xFF). External links (side<8)
    -- exist in the array but aren't connected via pFirstLink chains - they are
    -- placeholder entries that Detour would fill at runtime via connectExtLinks().
    tile.links = {}
    if tile.meshHeader.maxLinkCount > 0 then
        tile.links, pos = parse_links(data, pos, tile.meshHeader.maxLinkCount)
    end

    -- Parse detail meshes (YIELDS periodically)
    tile.detailMeshes = {}
    if tile.meshHeader.detailMeshCount > 0 then
        tile.detailMeshes, pos = parse_detail_meshes(data, pos, tile.meshHeader.detailMeshCount)
    end

    -- Parse detail verts
    tile.detailVerts = {}
    if tile.meshHeader.detailVertCount > 0 then
        tile.detailVerts, pos = parse_detail_vertices(data, pos, tile.meshHeader.detailVertCount)
    end

    -- Parse detail tris
    tile.detailTris = {}
    if tile.meshHeader.detailTriCount > 0 then
        tile.detailTris, pos = parse_detail_triangles(data, pos, tile.meshHeader.detailTriCount)
    end

    -- Parse BV nodes (YIELDS periodically)
    tile.bvNodes = {}
    if tile.meshHeader.bvNodeCount > 0 then
        tile.bvNodes, pos = parse_bv_nodes(data, pos, tile.meshHeader.bvNodeCount)
    end

    -- Parse off-mesh connections (YIELDS periodically, usually 0 in open terrain)
    tile.offMeshConnections = {}
    if tile.meshHeader.offMeshConCount > 0 then
        tile.offMeshConnections, pos = parse_off_mesh_connections(data, pos, tile.meshHeader.offMeshConCount)
    end
    
    -- Parse Liquid (At the very end)
    tile.liquid = nil
    if tile.mmapHeader.usesLiquids == 1 then
        tile.liquid, pos = parse_liquid(data, pos)
    end

    -- Store tile coordinates and navigation parameters
    tile.tileX = tile.meshHeader.x
    tile.tileY = tile.meshHeader.y
    tile.layer = tile.meshHeader.layer  -- For multi-level (ground vs roof)
    tile.walkableClimb = tile.meshHeader.walkableClimb  -- Max step height

    -- Calculate bounds in WoW coords
    local bmin = tile.meshHeader.bmin
    local bmax = tile.meshHeader.bmax
    tile.boundsWow = {
        min = { x = bmin[3], y = bmin[1], z = bmin[2] },
        max = { x = bmax[3], y = bmax[1], z = bmax[2] }
    }

    -- Disable yielding
    yielding_enabled = false
    current_budget = nil

    return tile, nil
end

return TileParser