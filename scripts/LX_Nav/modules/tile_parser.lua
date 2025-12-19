-- LX_Nav mmtile File Parser
-- Parses .mmtile files to extract polygon and vertex data
-- Includes detail mesh data for precise terrain following
-- Supports yieldable incremental parsing with budget:step()

local Binary = require("modules/binary")

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
        poly.vertCount = Binary.read_u8(data, pos); pos = pos + 1
        poly.areaAndtype = Binary.read_u8(data, pos); pos = pos + 1

        -- Extract area and type
        poly.area = poly.areaAndtype % 64  -- & 0x3f
        poly.polyType = math.floor(poly.areaAndtype / 64)  -- >> 6

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
    local polyEnd = polyStart + (tile.meshHeader.polyCount * DT_POLY_SIZE) - 1

    -- Parse vertices
    tile.vertices, pos = parse_vertices(data, vertStart, tile.meshHeader.vertCount)

    -- Parse polygons
    tile.polygons, pos = parse_polygons(data, polyStart, tile.meshHeader.polyCount, tile.vertices)

    -- CORRECT Detour tile-data layout (from research):
    -- dtMeshHeader → verts[] → polys[] → links[] → detailMeshes[] → detailVerts[] → detailTris[] → bvTree[] → offMeshCons[]
    -- Links ARE between polys and detailMeshes (NOT at end!)
    -- TrinityCore uses 64-bit refs, so dtLink = 16 bytes (not 12)

    -- Calculate links block size (with 4-byte alignment)
    -- dtLink (64-bit): ref(8) + next(4) + edge(1) + side(1) + bmin(1) + bmax(1) = 16 bytes
    local linksSize = tile.meshHeader.maxLinkCount * DT_LINK_SIZE
    local linksStart = polyEnd + 1
    local linksEnd = linksStart + linksSize - 1

    -- Calculate detail mesh data offsets (AFTER links!)
    local detailMeshStart = linksEnd + 1
    local detailMeshEnd = detailMeshStart + (tile.meshHeader.detailMeshCount * DT_POLY_DETAIL_SIZE) - 1
    local detailVertStart = detailMeshEnd + 1
    local detailVertEnd = detailVertStart + (tile.meshHeader.detailVertCount * DT_DETAIL_VERT_SIZE) - 1
    local detailTriStart = detailVertEnd + 1
    local detailTriEnd = detailTriStart + (tile.meshHeader.detailTriCount * DT_DETAIL_TRI_SIZE) - 1

    -- DEBUG: Log the calculated offsets to file (append mode)
    local LOG = "parse_log_offsets.log"
    if not offset_log_created then
        core.create_log_file(LOG)
        offset_log_created = true
    end
    core.write_log_file(LOG, string.format("\n=== Tile mesh(%d,%d) polys=%d ===\n",
        tile.meshHeader.x, tile.meshHeader.y, tile.meshHeader.polyCount))
    core.write_log_file(LOG, string.format("File size: %d bytes\n", #data))
    core.write_log_file(LOG, string.format("Vertices: start=%d, count=%d, size=%d\n",
        vertStart, tile.meshHeader.vertCount, tile.meshHeader.vertCount * 12))
    core.write_log_file(LOG, string.format("Polygons: start=%d, end=%d, count=%d, size=%d\n",
        polyStart, polyEnd, tile.meshHeader.polyCount, tile.meshHeader.polyCount * DT_POLY_SIZE))
    core.write_log_file(LOG, string.format("Links: start=%d, end=%d, count=%d, size=%d (dtLink=16B for 64-bit)\n",
        linksStart, linksEnd, tile.meshHeader.maxLinkCount, linksSize))
    core.write_log_file(LOG, string.format("DetailMeshes: start=%d, count=%d, size=%d\n",
        detailMeshStart, tile.meshHeader.detailMeshCount, tile.meshHeader.detailMeshCount * DT_POLY_DETAIL_SIZE))
    core.write_log_file(LOG, string.format("DetailVerts: start=%d, count=%d, size=%d\n",
        detailVertStart, tile.meshHeader.detailVertCount, tile.meshHeader.detailVertCount * DT_DETAIL_VERT_SIZE))
    core.write_log_file(LOG, string.format("DetailTris: start=%d, end=%d, count=%d, size=%d\n",
        detailTriStart, detailTriEnd, tile.meshHeader.detailTriCount, tile.meshHeader.detailTriCount * DT_DETAIL_TRI_SIZE))

    -- Check if calculated end exceeds file size
    if detailTriEnd > #data then
        core.write_log_file(LOG, string.format("!!! ERROR: detailTriEnd=%d exceeds file size=%d!\n", detailTriEnd, #data))
    end

    -- Parse detail meshes
    tile.detailMeshes = {}
    tile.detailVerts = {}
    tile.detailTris = {}

    if tile.meshHeader.detailMeshCount > 0 then
        tile.detailMeshes, pos = parse_detail_meshes(data, detailMeshStart, tile.meshHeader.detailMeshCount)
    end

    if tile.meshHeader.detailVertCount > 0 then
        tile.detailVerts, pos = parse_detail_vertices(data, detailVertStart, tile.meshHeader.detailVertCount)
    end

    if tile.meshHeader.detailTriCount > 0 then
        tile.detailTris, pos = parse_detail_triangles(data, detailTriStart, tile.meshHeader.detailTriCount)
    end

    -- Calculate BVNode and OffMesh offsets
    local bvNodeStart = detailTriEnd + 1
    local bvNodeEnd = bvNodeStart + (tile.meshHeader.bvNodeCount * DT_BV_NODE_SIZE) - 1
    local offMeshStart = bvNodeEnd + 1
    local offMeshEnd = offMeshStart + (tile.meshHeader.offMeshConCount * DT_OFF_MESH_CON_SIZE) - 1

    -- Parse BV nodes (for spatial queries)
    tile.bvNodes = {}
    if tile.meshHeader.bvNodeCount > 0 then
        tile.bvNodes, pos = parse_bv_nodes(data, bvNodeStart, tile.meshHeader.bvNodeCount)
    end

    -- Parse off-mesh connections (jump/teleport links) - CRITICAL for pathfinding!
    tile.offMeshConnections = {}
    if tile.meshHeader.offMeshConCount > 0 then
        tile.offMeshConnections, pos = parse_off_mesh_connections(data, offMeshStart, tile.meshHeader.offMeshConCount)
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
    local polyEnd = polyStart + (tile.meshHeader.polyCount * DT_POLY_SIZE) - 1

    -- Parse vertices (YIELDS periodically)
    tile.vertices, pos = parse_vertices(data, vertStart, tile.meshHeader.vertCount)

    -- Parse polygons (YIELDS periodically)
    tile.polygons, pos = parse_polygons(data, polyStart, tile.meshHeader.polyCount, tile.vertices)

    -- Skip links block (garbage data, but must advance position)
    -- dtLink (64-bit): ref(8) + next(4) + edge(1) + side(1) + bmin(1) + bmax(1) = 16 bytes
    local linksSize = tile.meshHeader.maxLinkCount * DT_LINK_SIZE
    local linksStart = polyEnd + 1
    local linksEnd = linksStart + linksSize - 1
    maybe_yield("links", 1, 1)

    -- Calculate detail mesh data offsets (AFTER links!)
    local detailMeshStart = linksEnd + 1
    local detailMeshEnd = detailMeshStart + (tile.meshHeader.detailMeshCount * DT_POLY_DETAIL_SIZE) - 1
    local detailVertStart = detailMeshEnd + 1
    local detailVertEnd = detailVertStart + (tile.meshHeader.detailVertCount * DT_DETAIL_VERT_SIZE) - 1
    local detailTriStart = detailVertEnd + 1
    local detailTriEnd = detailTriStart + (tile.meshHeader.detailTriCount * DT_DETAIL_TRI_SIZE) - 1

    -- Parse detail meshes (YIELDS periodically)
    tile.detailMeshes = {}
    tile.detailVerts = {}
    tile.detailTris = {}

    if tile.meshHeader.detailMeshCount > 0 then
        tile.detailMeshes, pos = parse_detail_meshes(data, detailMeshStart, tile.meshHeader.detailMeshCount)
    end

    if tile.meshHeader.detailVertCount > 0 then
        tile.detailVerts, pos = parse_detail_vertices(data, detailVertStart, tile.meshHeader.detailVertCount)
    end

    if tile.meshHeader.detailTriCount > 0 then
        tile.detailTris, pos = parse_detail_triangles(data, detailTriStart, tile.meshHeader.detailTriCount)
    end

    -- Calculate BVNode and OffMesh offsets
    local bvNodeStart = detailTriEnd + 1
    local bvNodeEnd = bvNodeStart + (tile.meshHeader.bvNodeCount * DT_BV_NODE_SIZE) - 1
    local offMeshStart = bvNodeEnd + 1

    -- Parse BV nodes (YIELDS periodically)
    tile.bvNodes = {}
    if tile.meshHeader.bvNodeCount > 0 then
        tile.bvNodes, pos = parse_bv_nodes(data, bvNodeStart, tile.meshHeader.bvNodeCount)
    end

    -- Parse off-mesh connections (YIELDS periodically, usually 0 in open terrain)
    tile.offMeshConnections = {}
    if tile.meshHeader.offMeshConCount > 0 then
        tile.offMeshConnections, pos = parse_off_mesh_connections(data, offMeshStart, tile.meshHeader.offMeshConCount)
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
