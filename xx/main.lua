-- LX_Nav - Navigation System
-- Step-by-step implementation with verification

-- Load modules
local Debug = require("modules/debug")
local Binary = require("modules/binary")
local MMapParser = require("modules/mmap_parser")
local TileParser = require("modules/tile_parser")
local Wireframe = require("modules/wireframe")
local NavWorld = require("modules/nav_world")
local NavQuery = require("modules/nav_query")
local Repair = require("modules/repair")

-- Graphics
local color = require("common/color")
local vec3 = require("common/geometry/vector_3")

-- Menu elements (created upfront)
local menu_elements = {
    main_tree = core.menu.tree_node(),
    enabled = core.menu.checkbox(true, "lx_nav_enabled"),
    show_debug = core.menu.checkbox(true, "lx_nav_show_debug"),
    -- Wireframe controls
    wireframe_tree = core.menu.tree_node(),
    wireframe_enabled = core.menu.checkbox(false, "lx_nav_wireframe"),  -- Default OFF for production
    wireframe_range = core.menu.slider_int(10, 100, 50, "lx_nav_wireframe_range"),
    wireframe_bvnodes = core.menu.checkbox(false, "lx_nav_bvnodes"),
    wireframe_cross_tile = core.menu.checkbox(false, "lx_nav_cross_tile"),  -- Show cross-tile connections
    -- Pathfinding controls
    path_tree = core.menu.tree_node(),
    path_enabled = core.menu.checkbox(false, "lx_nav_path_enabled"),
    path_to_target = core.menu.button("lx_nav_path_to_target"),
    path_to_click = core.menu.button("lx_nav_path_to_click"),
    save_safe_pos = core.menu.button("lx_nav_save_safe_pos"),
    path_to_safe_pos = core.menu.button("lx_nav_path_to_safe_pos"),
    path_clear = core.menu.button("lx_nav_path_clear"),
    -- Test controls
    test_tree = core.menu.tree_node(),
    run_crosstile_test = core.menu.button("lx_nav_crosstile_btn"),
    -- Path recorder
    recorder_tree = core.menu.tree_node(),
    recorder_toggle = core.menu.button("lx_nav_recorder_toggle"),
    recorder_clear = core.menu.button("lx_nav_recorder_clear"),
    recorder_save = core.menu.button("lx_nav_recorder_save"),
    -- Repair tools
    repair_tree = core.menu.tree_node(),
    repair_enabled = core.menu.checkbox(false, "lx_nav_repair_enabled"),
    repair_mode_connect = core.menu.button("lx_nav_repair_connect"),
    repair_mode_blacklist_poly = core.menu.button("lx_nav_repair_bl_poly"),
    repair_mode_blacklist_point = core.menu.button("lx_nav_repair_bl_point"),
    repair_point_radius = core.menu.slider_int(1, 20, 5, "lx_nav_repair_radius"),
    repair_blacklist_selected = core.menu.button("lx_nav_repair_blacklist"),
    repair_clear_selection = core.menu.button("lx_nav_repair_clear_sel"),
    repair_save_bridges = core.menu.button("lx_nav_repair_save_bridges"),
    repair_cancel_staged = core.menu.button("lx_nav_repair_cancel_staged"),
    repair_remove_last_staged = core.menu.button("lx_nav_repair_remove_last"),
    repair_bridges_tree = core.menu.tree_node(),
    repair_delete_bridge = core.menu.button("lx_nav_repair_del_bridge"),
    -- New v3 elements
    repair_cancel_recording = core.menu.button("lx_nav_repair_cancel_rec"),
    repair_undo = core.menu.button("lx_nav_repair_undo"),
    repair_tris_tree = core.menu.tree_node(),
    repair_points_tree = core.menu.tree_node(),
    repair_delete_tri = core.menu.button("lx_nav_repair_del_tri"),
    repair_delete_point = core.menu.button("lx_nav_repair_del_point"),
    repair_clear_bridges = core.menu.button("lx_nav_repair_clear_bridges"),
    repair_clear_tris = core.menu.button("lx_nav_repair_clear_tris"),
    repair_clear_points = core.menu.button("lx_nav_repair_clear_points"),
}

-- State
local State = {
    initialized = false,
    enabled = true,
    crosstile_test_done = false,  -- Reset to re-run test
}

-- Pathfinding state
local PathState = {
    world = nil,      -- NavWorld instance
    query = nil,      -- NavQuery instance
    path = nil,       -- Current path (array of {x,y,z})
    polyPath = nil,   -- Current polygon path
    stats = nil,      -- Path stats
    targetPos = nil,  -- Target position {x,y,z}
}

-- Click-to-path and safe position state
local click_to_path_mode = false
local saved_safe_pos = nil  -- {x, y, z, map_id}
local prev_mouse_down = false  -- For click edge detection
local repair_prev_mouse = false  -- For repair click edge detection

-- Path recorder state
local PathRecorder = {
    is_recording = false,
    points = {},           -- Array of {x, y, z, time}
    start_time = 0,
    last_record_time = 0,
    record_interval = 0.2, -- Record every 0.2 seconds
    min_distance = 1.0,    -- Minimum distance between points (yards)
}

-- Test binary reading helpers
local function test_binary_helpers()
    Debug.log("")
    Debug.log("=== Testing Binary Helpers ===")
    Debug.log("Starting binary test...")

    -- Try to read an mmtile file
    local filename = "mmaps/0001_30_30.mmtile"
    local data = core.read_data_file(filename)

    if not data or #data == 0 then
        Debug.log_error("Failed to read test file: " .. filename)
        return
    end

    Debug.log(string.format("Read file: %s (%d bytes)", filename, #data))

    -- Test u32 read - should be MMAP magic 0x4D4D4150
    local magic = Binary.read_u32(data, 1)
    Debug.log(string.format("Magic u32: 0x%08X (expected 0x4D4D4150)", magic))

    if magic == 0x4D4D4150 then
        Debug.log("Binary u32 test: PASS")
    else
        Debug.log_error("Binary u32 test: FAIL")
    end

    -- Test hex dump of first 20 bytes (MmapTileHeader)
    Debug.log("First 20 bytes: " .. Binary.to_hex(data, 1, 20))

    -- Test float reading - bmin/bmax values at offset 92 (72 + 20 header)
    -- dtMeshHeader.bmin is at offset 72 from start of dtMeshHeader (offset 20 in file)
    local bmin_x = Binary.read_f32(data, 93)  -- 20 + 72 + 1 (1-indexed)
    local bmin_y = Binary.read_f32(data, 97)
    local bmin_z = Binary.read_f32(data, 101)
    Debug.log(string.format("bmin (Recast): (%.2f, %.2f, %.2f)", bmin_x, bmin_y, bmin_z))

    Debug.log("=== Binary Tests Complete ===")
end

-- Test mmap parser with performance tracking - writes to separate log file
local function test_mmap_parser()
    local LOG_FILE = "parse_log_mmap.log"
    core.create_log_file(LOG_FILE)

    local function log(msg)
        core.write_log_file(LOG_FILE, msg .. "\n")
    end

    local ticks_per_ms = core.cpu_ticks_per_second() / 1000

    log("==============================================")
    log("       MMAP FILE PARSER - FULL LOG")
    log("==============================================")
    log("")

    -- Test with map 0001
    local filename = "mmaps/0001.mmap"

    -- Measure file read time
    local start_ticks = core.cpu_ticks()
    local data = core.read_data_file(filename)
    local read_time_ms = (core.cpu_ticks() - start_ticks) / ticks_per_ms

    if not data or #data == 0 then
        log("[ERROR] Failed to read: " .. filename)
        return
    end

    log("--- FILE INFO ---")
    log("Filename: " .. filename)
    log("File size: " .. #data .. " bytes")
    log("Read time: " .. string.format("%.3f ms", read_time_ms))
    log("")

    -- Log ALL raw bytes
    log("--- RAW BYTES (hex dump) ---")
    for i = 1, #data, 16 do
        local hex_line = string.format("%04d: ", i - 1)
        local ascii_line = ""
        for j = 0, 15 do
            if i + j <= #data then
                local byte = string.byte(data, i + j)
                hex_line = hex_line .. string.format("%02X ", byte)
                if byte >= 32 and byte < 127 then
                    ascii_line = ascii_line .. string.char(byte)
                else
                    ascii_line = ascii_line .. "."
                end
            else
                hex_line = hex_line .. "   "
            end
        end
        log(hex_line .. "| " .. ascii_line)
    end
    log("")

    -- Parse byte by byte according to MmapNavMeshHeader structure
    log("--- BYTE-BY-BYTE PARSING ---")
    log("Structure: MmapNavMeshHeader (40 bytes)")
    log("")

    local pos = 1

    -- Magic (4 bytes)
    local magic = Binary.read_u32(data, pos)
    log(string.format("Offset %02d-%02d: mmapMagic", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (u32): 0x%08X", magic))
    log(string.format("  Expected: 0x4D4D4150 ('MMAP')")  )
    log(string.format("  Valid: %s", magic == 0x4D4D4150 and "YES" or "NO"))
    pos = pos + 4
    log("")

    -- Version (4 bytes)
    local version = Binary.read_u32(data, pos)
    log(string.format("Offset %02d-%02d: mmapVersion", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (u32): %d", version))
    log(string.format("  Expected: 16"))
    pos = pos + 4
    log("")

    -- dtNavMeshParams.orig[3] (12 bytes)
    log("--- dtNavMeshParams structure (28 bytes) ---")
    log("")

    local orig_x = Binary.read_f32(data, pos)
    log(string.format("Offset %02d-%02d: params.orig[0] (x)", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (f32): %.6f", orig_x))
    pos = pos + 4
    log("")

    local orig_y = Binary.read_f32(data, pos)
    log(string.format("Offset %02d-%02d: params.orig[1] (y)", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (f32): %.6f", orig_y))
    pos = pos + 4
    log("")

    local orig_z = Binary.read_f32(data, pos)
    log(string.format("Offset %02d-%02d: params.orig[2] (z)", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (f32): %.6f", orig_z))
    pos = pos + 4
    log("")

    -- tileWidth (4 bytes)
    local tileWidth = Binary.read_f32(data, pos)
    log(string.format("Offset %02d-%02d: params.tileWidth", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (f32): %.6f", tileWidth))
    log(string.format("  Expected: ~533.333 (WoW tile size)"))
    pos = pos + 4
    log("")

    -- tileHeight (4 bytes)
    local tileHeight = Binary.read_f32(data, pos)
    log(string.format("Offset %02d-%02d: params.tileHeight", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (f32): %.6f", tileHeight))
    log(string.format("  Expected: ~533.333 (WoW tile size)"))
    pos = pos + 4
    log("")

    -- maxTiles (4 bytes)
    local maxTiles = Binary.read_u32(data, pos)
    log(string.format("Offset %02d-%02d: params.maxTiles", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (u32): %d", maxTiles))
    log(string.format("  Value (hex): 0x%08X", maxTiles))
    pos = pos + 4
    log("")

    -- maxPolys (4 bytes)
    local maxPolys = Binary.read_u32(data, pos)
    log(string.format("Offset %02d-%02d: params.maxPolys", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (u32): %d", maxPolys))
    log(string.format("  Value (hex): 0x%08X", maxPolys))
    if maxPolys == 0x80000000 then
        log("  Mode: 64-bit poly refs (DT_POLYREF64)")
        log("  Meaning: polyBits=31, tileBits=21, saltBits=12 (static)")
    else
        log(string.format("  Mode: 32-bit poly refs (dynamic allocation)"))
        log(string.format("  Valid range: 1-1000000 (typical: 4096-65536)"))
    end
    pos = pos + 4
    log("")

    -- offmeshConnectionCount (4 bytes)
    local offmeshCount = Binary.read_u32(data, pos)
    log(string.format("Offset %02d-%02d: offmeshConnectionCount", pos-1, pos+2))
    log(string.format("  Raw bytes: %s", Binary.to_hex(data, pos, 4)))
    log(string.format("  Value (u32): %d", offmeshCount))
    pos = pos + 4
    log("")

    -- Now run the actual parser
    log("--- PARSER OUTPUT ---")
    local parse_start = core.cpu_ticks()
    local params, err = MMapParser.parse(data)
    local parse_time_ms = (core.cpu_ticks() - parse_start) / ticks_per_ms

    if not params then
        log("[ERROR] Parse failed: " .. tostring(err))
        return
    end

    log(string.format("Parse time: %.3f ms", parse_time_ms))
    log("")
    log("Parsed values:")
    log(string.format("  magic: 0x%08X", params.magic))
    log(string.format("  version: %d", params.version))
    log(string.format("  orig.x: %.6f", params.orig.x))
    log(string.format("  orig.y: %.6f", params.orig.y))
    log(string.format("  orig.z: %.6f", params.orig.z))
    log(string.format("  tileWidth: %.6f", params.tileWidth))
    log(string.format("  tileHeight: %.6f", params.tileHeight))
    log(string.format("  maxTiles: %d", params.maxTiles))
    log(string.format("  maxPolys: %d (0x%08X)", params.maxPolys, params.maxPolys))
    log(string.format("  use64BitRefs: %s", params.use64BitRefs and "YES" or "NO"))
    log(string.format("  tileBits: %d", params.tileBits))
    log(string.format("  polyBits: %d", params.polyBits))
    log(string.format("  saltBits: %d", params.saltBits))
    log(string.format("  Total bits: %d (%s)", params.tileBits + params.polyBits + params.saltBits,
        params.use64BitRefs and "64-bit refs" or "32-bit refs"))
    log("")

    log("--- PERFORMANCE ---")
    log(string.format("File read: %.3f ms", read_time_ms))
    log(string.format("Parse: %.3f ms", parse_time_ms))
    log(string.format("Total: %.3f ms", read_time_ms + parse_time_ms))
    log("")

    log("==============================================")
    log("              END OF LOG")
    log("==============================================")

    Debug.log("mmap parser log written to: " .. LOG_FILE)
end

-- ==========================================
-- COROUTINE-BASED FULL DATA EXTRACTION
-- ==========================================
-- Extracts all mmtile data using frame-budgeted coroutines to avoid freezing

local ExtractState = {
    coroutine = nil,
    running = false,
    start_time = 0,
    items_written = 0,
    total_items = 0,
    current_section = "",
    data = nil,  -- Cached file data
    counts = {},  -- Header counts
    offsets = {},  -- Section offsets
}

local FRAME_BUDGET_MS = 5.0  -- Max ms per frame for extraction
local YIELD_BUDGET_MS = 1.0  -- Yield after this much time in coroutine
local WRITE_BATCH_SIZE = 50  -- Write to file every N items

-- Log files
local LOG_MAIN = "parse_log_mmtile.log"
local LOG_VERTICES = "parse_log_vertices.log"
local LOG_POLYGONS = "parse_log_polygons.log"
local LOG_DETAIL = "parse_log_detail.log"
local LOG_LINKS = "parse_log_links.log"

-- Buffered log writers (batch writes to reduce I/O)
local LogBuffers = {
    main = {},
    vert = {},
    poly = {},
    detail = {},
    links = {},
}

local function flush_buffer(buffer, filename)
    if #buffer > 0 then
        core.write_log_file(filename, table.concat(buffer, "\n") .. "\n")
        for i = 1, #buffer do buffer[i] = nil end
    end
end

local function log_main(msg)
    table.insert(LogBuffers.main, msg)
    if #LogBuffers.main >= WRITE_BATCH_SIZE then
        flush_buffer(LogBuffers.main, LOG_MAIN)
    end
end

local function log_vert(msg)
    table.insert(LogBuffers.vert, msg)
    if #LogBuffers.vert >= WRITE_BATCH_SIZE then
        flush_buffer(LogBuffers.vert, LOG_VERTICES)
    end
end

local function log_poly(msg)
    table.insert(LogBuffers.poly, msg)
    if #LogBuffers.poly >= WRITE_BATCH_SIZE then
        flush_buffer(LogBuffers.poly, LOG_POLYGONS)
    end
end

local function log_detail(msg)
    table.insert(LogBuffers.detail, msg)
    if #LogBuffers.detail >= WRITE_BATCH_SIZE then
        flush_buffer(LogBuffers.detail, LOG_DETAIL)
    end
end

local function log_links(msg)
    table.insert(LogBuffers.links, msg)
    if #LogBuffers.links >= WRITE_BATCH_SIZE then
        flush_buffer(LogBuffers.links, LOG_LINKS)
    end
end

local function flush_all_buffers()
    flush_buffer(LogBuffers.main, LOG_MAIN)
    flush_buffer(LogBuffers.vert, LOG_VERTICES)
    flush_buffer(LogBuffers.poly, LOG_POLYGONS)
    flush_buffer(LogBuffers.detail, LOG_DETAIL)
    flush_buffer(LogBuffers.links, LOG_LINKS)
end

-- Main extraction coroutine
local function extraction_coroutine()
    local data = ExtractState.data
    local counts = ExtractState.counts
    local offsets = ExtractState.offsets
    local ticks_per_ms = core.cpu_ticks_per_second() / 1000
    local yield_budget_ticks = YIELD_BUDGET_MS * ticks_per_ms

    -- Time-based yield helper
    local last_yield_time = core.cpu_ticks()
    local function check_yield()
        local now = core.cpu_ticks()
        if (now - last_yield_time) >= yield_budget_ticks then
            coroutine.yield()
            last_yield_time = core.cpu_ticks()
            return true
        end
        return false
    end

    -- ========== VERTICES ==========
    ExtractState.current_section = "Vertices"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.vertCount

    log_vert("==============================================")
    log_vert("        ALL VERTICES - FULL EXTRACTION")
    log_vert("==============================================")
    log_vert(string.format("File: mmaps/0001_30_30.mmtile"))
    log_vert(string.format("Total vertices: %d", counts.vertCount))
    log_vert("")
    log_vert("Format: [index] recast(x,y,z) -> wow(x,y,z)")
    log_vert("")

    local pos = offsets.vertStart + 1
    for i = 1, counts.vertCount do
        local rx = Binary.read_f32(data, pos)
        local ry = Binary.read_f32(data, pos + 4)
        local rz = Binary.read_f32(data, pos + 8)
        local wx, wy, wz = -rz, -rx, ry
        log_vert(string.format("[%5d] recast(%.4f, %.4f, %.4f) -> wow(%.4f, %.4f, %.4f)",
            i, rx, ry, rz, wx, wy, wz))
        pos = pos + 12
        ExtractState.items_written = i
        check_yield()
    end
    coroutine.yield()

    -- ========== POLYGONS ==========
    ExtractState.current_section = "Polygons"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.polyCount

    log_poly("==============================================")
    log_poly("        ALL POLYGONS - FULL EXTRACTION")
    log_poly("==============================================")
    log_poly(string.format("File: mmaps/0001_30_30.mmtile"))
    log_poly(string.format("Total polygons: %d", counts.polyCount))
    log_poly("")
    log_poly("Format: [index] firstLink | verts[6] | neis[6] | flags | vertCount | area | type")
    log_poly("")

    pos = offsets.polyStart + 1
    for i = 1, counts.polyCount do
        local firstLink = Binary.read_u32(data, pos); pos = pos + 4
        local verts = {}
        for j = 1, 6 do verts[j] = Binary.read_u16(data, pos); pos = pos + 2 end
        local neis = {}
        for j = 1, 6 do neis[j] = Binary.read_u16(data, pos); pos = pos + 2 end
        local flags = Binary.read_u16(data, pos); pos = pos + 2
        local pVertCount = Binary.read_u8(data, pos); pos = pos + 1
        local areaAndtype = Binary.read_u8(data, pos); pos = pos + 1
        local area = areaAndtype % 64
        local ptype = math.floor(areaAndtype / 64)

        local vertStr = ""
        for j = 1, 6 do vertStr = vertStr .. string.format("%5d ", verts[j]) end
        local neiStr = ""
        for j = 1, 6 do neiStr = neiStr .. string.format("%5d ", neis[j]) end

        log_poly(string.format("[%5d] firstLink=%8d | verts=[%s] | neis=[%s] | flags=0x%04X | vertCount=%d | area=%2d | type=%d",
            i, firstLink, vertStr, neiStr, flags, pVertCount, area, ptype))
        ExtractState.items_written = i
        check_yield()
    end
    coroutine.yield()

    -- ========== DETAIL MESHES ==========
    ExtractState.current_section = "DetailMeshes"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.detailMeshCount

    log_detail("==============================================")
    log_detail("     DETAIL MESHES, VERTS, TRIS, BV - FULL")
    log_detail("==============================================")
    log_detail(string.format("File: mmaps/0001_30_30.mmtile"))
    log_detail("")
    log_detail(string.format("=== DETAIL MESHES (%d) ===", counts.detailMeshCount))
    log_detail("Format: [index] vertBase | triBase | vertCount | triCount")
    log_detail("")

    pos = offsets.detailMeshStart + 1
    for i = 1, counts.detailMeshCount do
        local vertBase = Binary.read_u32(data, pos); pos = pos + 4
        local triBase = Binary.read_u32(data, pos); pos = pos + 4
        local dmVertCount = Binary.read_u8(data, pos); pos = pos + 1
        local triCount = Binary.read_u8(data, pos); pos = pos + 1
        pos = pos + 2
        log_detail(string.format("[%5d] vertBase=%6d | triBase=%6d | vertCount=%3d | triCount=%3d",
            i, vertBase, triBase, dmVertCount, triCount))
        ExtractState.items_written = i
        check_yield()
    end
    log_detail("")
    coroutine.yield()

    -- ========== DETAIL VERTICES ==========
    ExtractState.current_section = "DetailVerts"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.detailVertCount

    log_detail(string.format("=== DETAIL VERTICES (%d) ===", counts.detailVertCount))
    log_detail("Format: [index] x, y, z")
    log_detail("")

    pos = offsets.detailVertStart + 1
    for i = 1, counts.detailVertCount do
        local dx = Binary.read_f32(data, pos)
        local dy = Binary.read_f32(data, pos + 4)
        local dz = Binary.read_f32(data, pos + 8)
        log_detail(string.format("[%5d] (%.4f, %.4f, %.4f)", i, dx, dy, dz))
        pos = pos + 12
        ExtractState.items_written = i
        check_yield()
    end
    log_detail("")
    coroutine.yield()

    -- ========== DETAIL TRIANGLES ==========
    ExtractState.current_section = "DetailTris"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.detailTriCount

    log_detail(string.format("=== DETAIL TRIANGLES (%d) ===", counts.detailTriCount))
    log_detail("Format: [index] v0, v1, v2, flags")
    log_detail("")

    pos = offsets.detailTriStart + 1
    for i = 1, counts.detailTriCount do
        local b0 = Binary.read_u8(data, pos)
        local b1 = Binary.read_u8(data, pos + 1)
        local b2 = Binary.read_u8(data, pos + 2)
        local b3 = Binary.read_u8(data, pos + 3)
        log_detail(string.format("[%5d] v0=%3d, v1=%3d, v2=%3d, flags=%3d", i, b0, b1, b2, b3))
        pos = pos + 4
        ExtractState.items_written = i
        check_yield()
    end
    log_detail("")
    coroutine.yield()

    -- ========== BV NODES ==========
    ExtractState.current_section = "BVNodes"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.bvNodeCount

    log_detail(string.format("=== BV NODES (%d) ===", counts.bvNodeCount))
    log_detail("Format: [index] bmin(x,y,z) bmax(x,y,z) i")
    log_detail("")

    pos = offsets.bvNodeStart + 1
    for i = 1, counts.bvNodeCount do
        local bvmin = {Binary.read_u16(data, pos), Binary.read_u16(data, pos+2), Binary.read_u16(data, pos+4)}
        local bvmax = {Binary.read_u16(data, pos+6), Binary.read_u16(data, pos+8), Binary.read_u16(data, pos+10)}
        local bvi = Binary.read_i32(data, pos + 12)
        log_detail(string.format("[%5d] bmin(%5d,%5d,%5d) bmax(%5d,%5d,%5d) i=%d",
            i, bvmin[1], bvmin[2], bvmin[3], bvmax[1], bvmax[2], bvmax[3], bvi))
        pos = pos + 16
        ExtractState.items_written = i
        check_yield()
    end
    coroutine.yield()

    -- ========== LINKS ==========
    ExtractState.current_section = "Links"
    ExtractState.items_written = 0
    ExtractState.total_items = counts.maxLinkCount

    log_links("==============================================")
    log_links("          ALL LINKS - FULL EXTRACTION")
    log_links("==============================================")
    log_links(string.format("File: mmaps/0001_30_30.mmtile"))
    log_links(string.format("Total links: %d", counts.maxLinkCount))
    log_links("")
    log_links("Format: [index] ref (64-bit) | next | edge | side | bmin | bmax")
    log_links("Note: side 0-7 = direction, 0xFF = internal")
    log_links("")

    pos = offsets.linkStart + 1
    for i = 1, counts.maxLinkCount do
        local refLo = Binary.read_u32(data, pos)
        local refHi = Binary.read_u32(data, pos + 4)
        local next = Binary.read_u32(data, pos + 8)
        local edge = Binary.read_u8(data, pos + 12)
        local side = Binary.read_u8(data, pos + 13)
        local lbmin = Binary.read_u8(data, pos + 14)
        local lbmax = Binary.read_u8(data, pos + 15)

        local sideStr = side == 0xFF and "internal" or string.format("dir=%d", side)
        log_links(string.format("[%5d] ref=0x%08X%08X | next=%8d | edge=%d | side=%s | bmin=%3d | bmax=%3d",
            i, refHi, refLo, next, edge, sideStr, lbmin, lbmax))
        pos = pos + 16
        ExtractState.items_written = i
        check_yield()
    end

    -- Done
    ExtractState.current_section = "COMPLETE"
    local elapsed = (core.cpu_ticks() - ExtractState.start_time) / ticks_per_ms
    log_main("")
    log_main("=== EXTRACTION COMPLETE ===")
    log_main(string.format("Total time: %.1f ms (%.1f seconds)", elapsed, elapsed / 1000))
    log_main(string.format("Vertices: %d", counts.vertCount))
    log_main(string.format("Polygons: %d", counts.polyCount))
    log_main(string.format("DetailMeshes: %d", counts.detailMeshCount))
    log_main(string.format("DetailVerts: %d", counts.detailVertCount))
    log_main(string.format("DetailTris: %d", counts.detailTriCount))
    log_main(string.format("BVNodes: %d", counts.bvNodeCount))
    log_main(string.format("Links: %d", counts.maxLinkCount))
    log_main("==============================================")

    -- Flush all remaining buffered data
    flush_all_buffers()

    Debug.log("Extraction COMPLETE! See parse_log_*.log files")
end

-- Start the extraction
local function start_extraction()
    local filename = "mmaps/0001_30_30.mmtile"
    local ticks_per_ms = core.cpu_ticks_per_second() / 1000
    local t0 = core.cpu_ticks()

    -- Create log files
    core.create_log_file(LOG_MAIN)
    core.create_log_file(LOG_VERTICES)
    core.create_log_file(LOG_POLYGONS)
    core.create_log_file(LOG_DETAIL)
    core.create_log_file(LOG_LINKS)
    Debug.log(string.format("Log files created: %.2f ms", (core.cpu_ticks() - t0) / ticks_per_ms))

    -- Read file
    local start_ticks = core.cpu_ticks()
    local data = core.read_data_file(filename)
    local read_time_ms = (core.cpu_ticks() - start_ticks) / ticks_per_ms
    Debug.log(string.format("File read: %.2f ms", read_time_ms))

    if not data or #data == 0 then
        Debug.log_error("Failed to read: " .. filename)
        return false
    end

    ExtractState.data = data
    ExtractState.start_time = core.cpu_ticks()

    -- Parse headers
    local pos = 1

    -- MmapTileHeader (20 bytes)
    local mmapMagic = Binary.read_u32(data, pos); pos = pos + 4
    local dtVersion = Binary.read_u32(data, pos); pos = pos + 4
    local mmapVersion = Binary.read_u32(data, pos); pos = pos + 4
    local dataSize = Binary.read_u32(data, pos); pos = pos + 4
    local usesLiquids = Binary.read_u8(data, pos); pos = pos + 4

    -- dtMeshHeader (100 bytes)
    local meshMagic = Binary.read_i32(data, pos); pos = pos + 4
    local meshVersion = Binary.read_i32(data, pos); pos = pos + 4
    local tileX = Binary.read_i32(data, pos); pos = pos + 4
    local tileY = Binary.read_i32(data, pos); pos = pos + 4
    local layer = Binary.read_i32(data, pos); pos = pos + 4
    local userId = Binary.read_u32(data, pos); pos = pos + 4
    local polyCount = Binary.read_i32(data, pos); pos = pos + 4
    local vertCount = Binary.read_i32(data, pos); pos = pos + 4
    local maxLinkCount = Binary.read_i32(data, pos); pos = pos + 4
    local detailMeshCount = Binary.read_i32(data, pos); pos = pos + 4
    local detailVertCount = Binary.read_i32(data, pos); pos = pos + 4
    local detailTriCount = Binary.read_i32(data, pos); pos = pos + 4
    local bvNodeCount = Binary.read_i32(data, pos); pos = pos + 4
    local offMeshConCount = Binary.read_i32(data, pos); pos = pos + 4
    local offMeshBase = Binary.read_i32(data, pos); pos = pos + 4
    local walkableHeight = Binary.read_f32(data, pos); pos = pos + 4
    local walkableRadius = Binary.read_f32(data, pos); pos = pos + 4
    local walkableClimb = Binary.read_f32(data, pos); pos = pos + 4
    local bmin = {Binary.read_f32(data, pos), Binary.read_f32(data, pos+4), Binary.read_f32(data, pos+8)}; pos = pos + 12
    local bmax = {Binary.read_f32(data, pos), Binary.read_f32(data, pos+4), Binary.read_f32(data, pos+8)}; pos = pos + 12
    local bvQuantFactor = Binary.read_f32(data, pos); pos = pos + 4

    -- Store counts
    ExtractState.counts = {
        polyCount = polyCount,
        vertCount = vertCount,
        maxLinkCount = maxLinkCount,
        detailMeshCount = detailMeshCount,
        detailVertCount = detailVertCount,
        detailTriCount = detailTriCount,
        bvNodeCount = bvNodeCount,
        offMeshConCount = offMeshConCount,
    }

    -- Calculate offsets
    local HEADER_SIZE = 120
    local vertStart = HEADER_SIZE
    local vertSize = vertCount * 12
    local polyStart = vertStart + vertSize
    local polySize = polyCount * 32
    local detailMeshStart = polyStart + polySize
    local detailMeshSize = detailMeshCount * 12
    local detailVertStart = detailMeshStart + detailMeshSize
    local detailVertSize = detailVertCount * 12
    local detailTriStart = detailVertStart + detailVertSize
    local detailTriSize = detailTriCount * 4
    local bvNodeStart = detailTriStart + detailTriSize
    local bvNodeSize = bvNodeCount * 16
    local offMeshStart = bvNodeStart + bvNodeSize
    local offMeshSize = offMeshConCount * 36
    local linkStart = offMeshStart + offMeshSize

    ExtractState.offsets = {
        vertStart = vertStart,
        polyStart = polyStart,
        detailMeshStart = detailMeshStart,
        detailVertStart = detailVertStart,
        detailTriStart = detailTriStart,
        bvNodeStart = bvNodeStart,
        offMeshStart = offMeshStart,
        linkStart = linkStart,
    }

    -- Write main log header
    log_main("==============================================")
    log_main("      MMTILE FILE PARSER - COROUTINE EXTRACT")
    log_main("==============================================")
    log_main("")
    log_main(string.format("File: %s (%d bytes)", filename, #data))
    log_main(string.format("Read time: %.3f ms", read_time_ms))
    log_main("")
    log_main("=== MmapTileHeader ===")
    log_main(string.format("  mmapMagic: 0x%08X (%s)", mmapMagic, mmapMagic == 0x4D4D4150 and "VALID" or "INVALID"))
    log_main(string.format("  dtVersion: %d, mmapVersion: %d", dtVersion, mmapVersion))
    log_main(string.format("  dataSize: %d, usesLiquids: %d", dataSize, usesLiquids))
    log_main("")
    log_main("=== dtMeshHeader ===")
    log_main(string.format("  tileX: %d, tileY: %d, layer: %d", tileX, tileY, layer))
    log_main(string.format("  polyCount: %d, vertCount: %d", polyCount, vertCount))
    log_main(string.format("  maxLinkCount: %d", maxLinkCount))
    log_main(string.format("  detailMeshCount: %d, detailVertCount: %d, detailTriCount: %d",
        detailMeshCount, detailVertCount, detailTriCount))
    log_main(string.format("  bvNodeCount: %d, offMeshConCount: %d", bvNodeCount, offMeshConCount))
    log_main(string.format("  walkable: height=%.2f, radius=%.2f, climb=%.2f",
        walkableHeight, walkableRadius, walkableClimb))
    log_main(string.format("  bmin (WoW): (%.2f, %.2f, %.2f)", -bmin[3], -bmin[1], bmin[2]))
    log_main(string.format("  bmax (WoW): (%.2f, %.2f, %.2f)", -bmax[3], -bmax[1], bmax[2]))
    log_main("")
    log_main("=== DATA LAYOUT ===")
    log_main(string.format("  Vertices:      offset %6d, count %5d", vertStart, vertCount))
    log_main(string.format("  Polygons:      offset %6d, count %5d", polyStart, polyCount))
    log_main(string.format("  DetailMeshes:  offset %6d, count %5d", detailMeshStart, detailMeshCount))
    log_main(string.format("  DetailVerts:   offset %6d, count %5d", detailVertStart, detailVertCount))
    log_main(string.format("  DetailTris:    offset %6d, count %5d", detailTriStart, detailTriCount))
    log_main(string.format("  BVNodes:       offset %6d, count %5d", bvNodeStart, bvNodeCount))
    log_main(string.format("  Links:         offset %6d, count %5d", linkStart, maxLinkCount))
    log_main("")
    log_main("Starting coroutine extraction...")

    -- Flush header info before starting coroutine
    flush_all_buffers()

    local setup_time_ms = (core.cpu_ticks() - t0) / ticks_per_ms
    Debug.log(string.format("Setup complete: %.2f ms total", setup_time_ms))

    -- Create coroutine
    ExtractState.coroutine = coroutine.create(extraction_coroutine)
    ExtractState.running = true

    Debug.log("Extraction started - processing in background...")
    return true
end

-- Process extraction each frame
local function process_extraction()
    if not ExtractState.running or not ExtractState.coroutine then return end
    if coroutine.status(ExtractState.coroutine) == "dead" then
        ExtractState.running = false
        ExtractState.data = nil  -- Free memory
        return
    end

    local ticks_per_ms = core.cpu_ticks_per_second() / 1000
    local budget_ticks = FRAME_BUDGET_MS * ticks_per_ms
    local frame_start = core.cpu_ticks()

    -- Process while within budget
    while coroutine.status(ExtractState.coroutine) ~= "dead" do
        local ok, err = coroutine.resume(ExtractState.coroutine)
        if not ok then
            Debug.log_error("Extraction error: " .. tostring(err))
            ExtractState.running = false
            return
        end

        if (core.cpu_ticks() - frame_start) > budget_ticks then
            break
        end
    end
end

-- Get extraction status for display
local function get_extraction_status()
    if not ExtractState.running then return nil end
    return {
        section = ExtractState.current_section,
        progress = ExtractState.items_written,
        total = ExtractState.total_items,
    }
end

-- Extract remaining data (detail meshes, verts, tris, BV nodes, links)
local function extract_detail_and_links()
    local LOG_DETAIL = "parse_log_detail.log"
    local LOG_LINKS = "parse_log_links.log"

    core.create_log_file(LOG_DETAIL)
    core.create_log_file(LOG_LINKS)

    local function log_detail(msg) core.write_log_file(LOG_DETAIL, msg .. "\n") end
    local function log_links(msg) core.write_log_file(LOG_LINKS, msg .. "\n") end

    local filename = "mmaps/0001_30_30.mmtile"
    local data = core.read_data_file(filename)
    if not data or #data == 0 then
        Debug.log_error("Failed to read: " .. filename)
        return
    end

    -- Parse header values we need
    local pos = 1
    pos = pos + 20  -- Skip MmapTileHeader (20 bytes)

    -- Read dtMeshHeader fields we need
    pos = pos + 24  -- Skip magic, version, x, y, layer, userId
    local polyCount = Binary.read_i32(data, pos); pos = pos + 4
    local vertCount = Binary.read_i32(data, pos); pos = pos + 4
    local maxLinkCount = Binary.read_i32(data, pos); pos = pos + 4
    local detailMeshCount = Binary.read_i32(data, pos); pos = pos + 4
    local detailVertCount = Binary.read_i32(data, pos); pos = pos + 4
    local detailTriCount = Binary.read_i32(data, pos); pos = pos + 4
    local bvNodeCount = Binary.read_i32(data, pos); pos = pos + 4

    -- Calculate offsets
    local HEADER_SIZE = 120
    local vertStart = HEADER_SIZE
    local vertSize = vertCount * 12
    local polyStart = vertStart + vertSize
    local polySize = polyCount * 32
    local detailMeshStart = polyStart + polySize
    local detailMeshSize = detailMeshCount * 12
    local detailVertStart = detailMeshStart + detailMeshSize
    local detailVertSize = detailVertCount * 12
    local detailTriStart = detailVertStart + detailVertSize
    local detailTriSize = detailTriCount * 4
    local bvNodeStart = detailTriStart + detailTriSize
    local bvNodeSize = bvNodeCount * 16
    local offMeshStart = bvNodeStart + bvNodeSize
    local linkStart = offMeshStart  -- offMeshConCount is 0

    -- ========== EXTRACT DETAIL DATA ==========
    log_detail("==============================================")
    log_detail("     DETAIL MESHES, VERTS, TRIS, BV - FULL")
    log_detail("==============================================")
    log_detail(string.format("File: %s", filename))
    log_detail("")

    -- Detail Meshes
    log_detail(string.format("=== DETAIL MESHES (%d) ===", detailMeshCount))
    log_detail("Format: [index] vertBase | triBase | vertCount | triCount")
    log_detail("")
    pos = detailMeshStart + 1
    for i = 1, detailMeshCount do
        local vertBase = Binary.read_u32(data, pos); pos = pos + 4
        local triBase = Binary.read_u32(data, pos); pos = pos + 4
        local dmVertCount = Binary.read_u8(data, pos); pos = pos + 1
        local triCount = Binary.read_u8(data, pos); pos = pos + 1
        pos = pos + 2  -- padding
        log_detail(string.format("[%5d] vertBase=%6d | triBase=%6d | vertCount=%3d | triCount=%3d",
            i, vertBase, triBase, dmVertCount, triCount))
    end
    log_detail("")

    -- Detail Vertices
    log_detail(string.format("=== DETAIL VERTICES (%d) ===", detailVertCount))
    log_detail("Format: [index] x, y, z")
    log_detail("")
    pos = detailVertStart + 1
    for i = 1, detailVertCount do
        local dx = Binary.read_f32(data, pos)
        local dy = Binary.read_f32(data, pos + 4)
        local dz = Binary.read_f32(data, pos + 8)
        log_detail(string.format("[%5d] (%.4f, %.4f, %.4f)", i, dx, dy, dz))
        pos = pos + 12
    end
    log_detail("")

    -- Detail Triangles
    log_detail(string.format("=== DETAIL TRIANGLES (%d) ===", detailTriCount))
    log_detail("Format: [index] v0, v1, v2, flags")
    log_detail("")
    pos = detailTriStart + 1
    for i = 1, detailTriCount do
        local b0 = Binary.read_u8(data, pos)
        local b1 = Binary.read_u8(data, pos + 1)
        local b2 = Binary.read_u8(data, pos + 2)
        local b3 = Binary.read_u8(data, pos + 3)
        log_detail(string.format("[%5d] v0=%3d, v1=%3d, v2=%3d, flags=%3d", i, b0, b1, b2, b3))
        pos = pos + 4
    end
    log_detail("")

    -- BV Nodes
    log_detail(string.format("=== BV NODES (%d) ===", bvNodeCount))
    log_detail("Format: [index] bmin(x,y,z) bmax(x,y,z) i")
    log_detail("")
    pos = bvNodeStart + 1
    for i = 1, bvNodeCount do
        local bvmin = {Binary.read_u16(data, pos), Binary.read_u16(data, pos+2), Binary.read_u16(data, pos+4)}
        local bvmax = {Binary.read_u16(data, pos+6), Binary.read_u16(data, pos+8), Binary.read_u16(data, pos+10)}
        local bvi = Binary.read_i32(data, pos + 12)
        log_detail(string.format("[%5d] bmin(%5d,%5d,%5d) bmax(%5d,%5d,%5d) i=%d",
            i, bvmin[1], bvmin[2], bvmin[3], bvmax[1], bvmax[2], bvmax[3], bvi))
        pos = pos + 16
    end

    Debug.log("Detail data written to: " .. LOG_DETAIL)

    -- ========== EXTRACT LINKS ==========
    log_links("==============================================")
    log_links("          ALL LINKS - FULL EXTRACTION")
    log_links("==============================================")
    log_links(string.format("File: %s", filename))
    log_links(string.format("Total links (maxLinkCount): %d", maxLinkCount))
    log_links("")
    log_links("Format: [index] ref (64-bit) | next | edge | side | bmin | bmax")
    log_links("Note: side 0-7 = direction (0=West,1=North,...), 0xFF = internal link")
    log_links("")

    pos = linkStart + 1
    for i = 1, maxLinkCount do
        local refLo = Binary.read_u32(data, pos)
        local refHi = Binary.read_u32(data, pos + 4)
        local next = Binary.read_u32(data, pos + 8)
        local edge = Binary.read_u8(data, pos + 12)
        local side = Binary.read_u8(data, pos + 13)
        local lbmin = Binary.read_u8(data, pos + 14)
        local lbmax = Binary.read_u8(data, pos + 15)

        local sideStr = side == 0xFF and "internal" or string.format("dir=%d", side)
        log_links(string.format("[%5d] ref=0x%08X%08X | next=%8d | edge=%d | side=%s | bmin=%3d | bmax=%3d",
            i, refHi, refLo, next, edge, sideStr, lbmin, lbmax))
        pos = pos + 16
    end

    Debug.log("Links written to: " .. LOG_LINKS)
    Debug.log("Detail and Links extraction complete!")
end

-- ==========================================
-- CROSS-TILE CONNECTION VERIFICATION
-- ==========================================

-- DISABLED: Raw vertex comparison test (caused game freeze)
-- The Detour source confirms:
--   XY tolerance: 0.01 units
--   Z tolerance: walkableClimb (from tile header, typically 0.3-0.6)
-- So using epsilon tolerance IS the correct approach.
local function test_raw_vertex_comparison()
    Debug.log("[RAW] Skipped - Detour uses 0.01 XY epsilon + walkableClimb for Z")
end

-- Cross-tile connection test using CACHED tiles from TileManager (no freeze)
-- Requires: Enable wireframe first, wait for tiles to load, then run test
local function test_cross_tile_connections()
    local LOG_FILE = "parse_log_crosstile.log"
    core.create_log_file(LOG_FILE)
    local function log(msg) core.write_log_file(LOG_FILE, msg .. "\n") end

    local ticks_per_ms = core.cpu_ticks_per_second() / 1000
    local start_time = core.cpu_ticks()

    log("==============================================")
    log("    CROSS-TILE EPSILON ANALYSIS (CACHED)")
    log("==============================================")
    log("")

    -- We'll find the MINIMUM epsilon needed for 100% match
    -- by measuring actual distances between edge pairs
    local EPSILON_XY = 1.0    -- Start with large epsilon to find ALL potential matches
    local EPSILON_Z = 1.0

    local function verts_match(v1, v2)
        local dx = math.abs(v1.x - v2.x)
        local dy = math.abs(v1.y - v2.y)
        local dz = math.abs(v1.z - v2.z)
        return dx < EPSILON_XY and dy < EPSILON_XY and dz < EPSILON_Z
    end

    local function edges_match(e1, e2)
        return (verts_match(e1.v1, e2.v1) and verts_match(e1.v2, e2.v2)) or
               (verts_match(e1.v1, e2.v2) and verts_match(e1.v2, e2.v1))
    end

    -- Get tiles from TileManager (already loaded by wireframe)
    local tile_manager = Wireframe.get_tile_manager()
    if not tile_manager then
        log("ERROR: TileManager not initialized. Enable wireframe first!")
        Debug.log("[CrossTile] ERROR: Enable wireframe first to load tiles")
        return
    end

    local map_id = core.get_instance_id()
    local cached_tiles = tile_manager:get_all_tiles(map_id)

    -- Count tiles (get_all_tiles returns table with string keys, not array)
    local tile_count = 0
    for _ in pairs(cached_tiles) do
        tile_count = tile_count + 1
    end

    if tile_count < 4 then
        log(string.format("ERROR: Need at least 4 tiles for adjacency test, got %d", tile_count))
        log("Enable wireframe and wait for tiles to load.")
        Debug.log(string.format("[CrossTile] ERROR: Only %d tiles cached, need 4+", tile_count))
        return
    end

    -- Build tile lookup by file coordinates
    local tiles = {}
    log(string.format("Using %d cached tiles from TileManager:", tile_count))
    for key, tile in pairs(cached_tiles) do
        local name = string.format("%d_%d", tile.tileX, tile.tileY)
        tile.name = name
        tiles[name] = tile
        log(string.format("  %s: Detour(%d,%d), %d polys, %d verts",
            name, tile.tileX, tile.tileY, #tile.polygons, #tile.vertices))
    end
    log("")

    -- Extract external edges by direction for each tile
    local EXT_DIRS = {
        [32768] = {name = "dir0", dir = 0},
        [32770] = {name = "dir2", dir = 2},
        [32772] = {name = "dir4", dir = 4},
        [32774] = {name = "dir6", dir = 6},
    }

    local function get_external_edges(tile)
        local by_dir = {}
        for dir_val, info in pairs(EXT_DIRS) do
            by_dir[dir_val] = {edges = {}, min_x = 999999, max_x = -999999, min_y = 999999, max_y = -999999}
        end

        for poly_idx, poly in ipairs(tile.polygons) do
            for edge_idx = 1, poly.vertCount do
                local nei = poly.neis[edge_idx]
                if by_dir[nei] then
                    local v1_idx = poly.verts[edge_idx]
                    local v2_idx = poly.verts[(edge_idx % poly.vertCount) + 1]
                    local v1 = tile.vertices[v1_idx + 1]
                    local v2 = tile.vertices[v2_idx + 1]

                    if v1 and v2 then
                        local d = by_dir[nei]
                        table.insert(d.edges, {v1=v1, v2=v2, poly_idx=poly_idx, edge_idx=edge_idx})
                        d.min_x = math.min(d.min_x, v1.x, v2.x)
                        d.max_x = math.max(d.max_x, v1.x, v2.x)
                        d.min_y = math.min(d.min_y, v1.y, v2.y)
                        d.max_y = math.max(d.max_y, v1.y, v2.y)
                    end
                end
            end
        end
        return by_dir
    end

    -- Get external edges for all tiles
    local tile_edges = {}
    for name, tile in pairs(tiles) do
        tile_edges[name] = get_external_edges(tile)
    end

    -- Log edge counts per direction
    log("=== External edges per tile/direction ===")
    for name, edges in pairs(tile_edges) do
        log(string.format("%s:", name))
        for dir_val, info in pairs(EXT_DIRS) do
            local d = edges[dir_val]
            if #d.edges > 0 then
                log(string.format("  %s: %d edges, X[%.1f,%.1f] Y[%.1f,%.1f]",
                    info.name, #d.edges, d.min_x, d.max_x, d.min_y, d.max_y))
            end
        end
    end
    log("")

    -- Define tile adjacencies to test based on actual coordinate analysis
    -- Direction meanings based on boundary analysis:
    -- dir0 (0x8000): Y boundary (north/south)
    -- dir2 (0x8002): X boundary (east/west) at X=-1066.67
    -- dir4 (0x8004): Y boundary (north/south)
    -- dir6 (0x8006): X boundary (east/west) at X=-533.33 or X=0

    -- First, let's find actual shared boundaries by comparing coordinate ranges
    log("=== Analyzing actual tile boundaries ===")
    log("")

    -- For each pair of tiles, find which boundaries actually match
    local function ranges_overlap(min1, max1, min2, max2)
        return not (max1 < min2 - 1.0 or max2 < min1 - 1.0)
    end

    local function find_matching_boundary(t1_name, t2_name)
        local e1 = tile_edges[t1_name]
        local e2 = tile_edges[t2_name]
        if not e1 or not e2 then return nil end

        -- Check all direction pairs for matching boundaries
        for dir1, _ in pairs(EXT_DIRS) do
            for dir2, _ in pairs(EXT_DIRS) do
                local d1, d2 = e1[dir1], e2[dir2]
                if #d1.edges > 0 and #d2.edges > 0 then
                    -- Check if X boundaries match (constant X, edges run along Y)
                    local x_const_1 = math.abs(d1.min_x - d1.max_x) < 1.0
                    local x_const_2 = math.abs(d2.min_x - d2.max_x) < 1.0
                    local x_values_match = math.abs(d1.min_x - d2.min_x) < 1.0
                    local y_ranges_overlap = ranges_overlap(d1.min_y, d1.max_y, d2.min_y, d2.max_y)
                    local x_boundary = x_const_1 and x_const_2 and x_values_match and y_ranges_overlap

                    -- Check if Y boundaries match (constant Y, edges run along X)
                    local y_const_1 = math.abs(d1.min_y - d1.max_y) < 1.0
                    local y_const_2 = math.abs(d2.min_y - d2.max_y) < 1.0
                    local y_values_match = math.abs(d1.min_y - d2.min_y) < 1.0
                    local x_ranges_overlap = ranges_overlap(d1.min_x, d1.max_x, d2.min_x, d2.max_x)
                    local y_boundary = y_const_1 and y_const_2 and y_values_match and x_ranges_overlap

                    if x_boundary then
                        return {dir1 = dir1, dir2 = dir2, x_match = true, y_match = false,
                                boundary = d1.min_x}
                    elseif y_boundary then
                        return {dir1 = dir1, dir2 = dir2, x_match = false, y_match = true,
                                boundary = d1.min_y}
                    end
                end
            end
        end
        return nil
    end

    -- Dynamically find adjacent tile pairs from loaded tiles
    local tile_pairs = {}
    local tile_coords = {}
    for name, _ in pairs(tiles) do
        local tx, ty = name:match("(%d+)_(%d+)")
        if tx and ty then
            table.insert(tile_coords, {x = tonumber(tx), y = tonumber(ty), name = name})
        end
    end

    -- Find all adjacent pairs with direction info
    -- Tile coords: X increases going WEST, Y increases going SOUTH
    -- So tile (29,40) and (29,41): Y+1 means tile2 is SOUTH of tile1
    -- Direction meanings:
    --   dir0 (32768): NORTH edge (lower Y)
    --   dir2 (32770): EAST edge (lower X)
    --   dir4 (32772): SOUTH edge (higher Y)
    --   dir6 (32774): WEST edge (higher X)
    for i, t1 in ipairs(tile_coords) do
        for j, t2 in ipairs(tile_coords) do
            if i < j then  -- Avoid duplicates
                local dx = t2.x - t1.x
                local dy = t2.y - t1.y
                -- Adjacent if exactly 1 apart in one axis, 0 in the other
                if dx == 0 and dy == 1 then
                    -- t2 is SOUTH of t1: t1's dir4 (south) matches t2's dir0 (north)
                    table.insert(tile_pairs, {t1.name, t2.name, 32772, 32768, "Y"})
                elseif dx == 0 and dy == -1 then
                    -- t2 is NORTH of t1: t1's dir0 (north) matches t2's dir4 (south)
                    table.insert(tile_pairs, {t1.name, t2.name, 32768, 32772, "Y"})
                elseif dx == 1 and dy == 0 then
                    -- t2 is WEST of t1: t1's dir6 (west) matches t2's dir2 (east)
                    table.insert(tile_pairs, {t1.name, t2.name, 32774, 32770, "X"})
                elseif dx == -1 and dy == 0 then
                    -- t2 is EAST of t1: t1's dir2 (east) matches t2's dir6 (west)
                    table.insert(tile_pairs, {t1.name, t2.name, 32770, 32774, "X"})
                end
            end
        end
    end
    log(string.format("Found %d adjacent tile pairs", #tile_pairs))

    -- Build adjacencies directly from tile_pairs (skip find_matching_boundary)
    local adjacencies = {}
    for _, pair in ipairs(tile_pairs) do
        local t1, t2, dir1, dir2, axis = pair[1], pair[2], pair[3], pair[4], pair[5]
        if tile_edges[t1] and tile_edges[t2] then
            local d1 = tile_edges[t1][dir1]
            local d2 = tile_edges[t2][dir2]
            if #d1.edges > 0 and #d2.edges > 0 then
                local boundary = axis == "X" and d1.min_x or d1.min_y
                local desc = string.format("%s ↔ %s (%s=%.1f)", t1, t2, axis, boundary)
                table.insert(adjacencies, {t1, t2, dir1, dir2, desc})
                log(string.format("Adjacency: %s dir%d ↔ %s dir%d at %s=%.1f",
                    t1, (dir1 - 32768), t2, (dir2 - 32768), axis, boundary))
            end
        end
    end
    log("")

    log("=== Testing tile adjacencies ===")
    log(string.format("(XY epsilon=%.3f, Z epsilon=%.3f)", EPSILON_XY, EPSILON_Z))
    log("")

    local total_matches = 0
    local results = {}

    -- Collect ALL distances for epsilon analysis
    local all_match_distances = {xy = {}, z = {}}   -- Distances of matched pairs
    local all_near_miss = {xy = {}, z = {}}          -- Closest distance for unmatched (if < 2.0)

    for _, adj in ipairs(adjacencies) do
        local t1_name, t2_name, dir1, dir2, desc = adj[1], adj[2], adj[3], adj[4], adj[5]

        if tile_edges[t1_name] and tile_edges[t2_name] then
            local edges1 = tile_edges[t1_name][dir1].edges
            local edges2 = tile_edges[t2_name][dir2].edges

            local matches = {}
            for _, e1 in ipairs(edges1) do
                for _, e2 in ipairs(edges2) do
                    if edges_match(e1, e2) then
                        -- Calculate actual distance for this match
                        local d1_xy = math.max(
                            math.sqrt((e1.v1.x-e2.v1.x)^2 + (e1.v1.y-e2.v1.y)^2),
                            math.sqrt((e1.v2.x-e2.v2.x)^2 + (e1.v2.y-e2.v2.y)^2))
                        local d2_xy = math.max(
                            math.sqrt((e1.v1.x-e2.v2.x)^2 + (e1.v1.y-e2.v2.y)^2),
                            math.sqrt((e1.v2.x-e2.v1.x)^2 + (e1.v2.y-e2.v1.y)^2))
                        local d1_z = math.max(math.abs(e1.v1.z-e2.v1.z), math.abs(e1.v2.z-e2.v2.z))
                        local d2_z = math.max(math.abs(e1.v1.z-e2.v2.z), math.abs(e1.v2.z-e2.v1.z))

                        local dxy = math.min(d1_xy, d2_xy)
                        local dz = (d1_xy < d2_xy) and d1_z or d2_z

                        table.insert(all_match_distances.xy, dxy)
                        table.insert(all_match_distances.z, dz)
                        table.insert(matches, {e1 = e1, e2 = e2, dxy = dxy, dz = dz})
                    end
                end
            end

            local match_rate = 0
            if #edges1 > 0 then
                match_rate = #matches / #edges1 * 100
            end

            log(string.format("%s:", desc))
            log(string.format("  Edges: %d ↔ %d, Matches: %d (%.1f%%)",
                #edges1, #edges2, #matches, match_rate))

            -- Detailed analysis of matches and non-matches
            local function dist(a, b)
                return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
            end
            local function dist_xy(a, b)
                return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
            end

            -- Find which edges from tile1 didn't match
            local matched_e1 = {}
            for _, m in ipairs(matches) do
                matched_e1[m.e1] = true
            end

            local unmatched = {}
            for _, e1 in ipairs(edges1) do
                if not matched_e1[e1] then
                    -- Find closest edge in tile2
                    local best_dist = 999999
                    local best_e2 = nil
                    local best_dxy, best_dz = 0, 0
                    for _, e2 in ipairs(edges2) do
                        -- Check both vertex orderings
                        local d1 = math.max(dist_xy(e1.v1, e2.v1), dist_xy(e1.v2, e2.v2))
                        local d2 = math.max(dist_xy(e1.v1, e2.v2), dist_xy(e1.v2, e2.v1))
                        local dxy = math.min(d1, d2)
                        if dxy < best_dist then
                            best_dist = dxy
                            best_e2 = e2
                            if d1 < d2 then
                                best_dxy = d1
                                best_dz = math.max(math.abs(e1.v1.z - e2.v1.z), math.abs(e1.v2.z - e2.v2.z))
                            else
                                best_dxy = d2
                                best_dz = math.max(math.abs(e1.v1.z - e2.v2.z), math.abs(e1.v2.z - e2.v1.z))
                            end
                        end
                    end
                    table.insert(unmatched, {e1 = e1, e2 = best_e2, dxy = best_dxy, dz = best_dz})
                end
            end

            if #matches > 0 then
                local m = matches[1]
                log(string.format("  Sample match: poly%d ↔ poly%d", m.e1.poly_idx, m.e2.poly_idx))
            end

            -- Analyze unmatched edges
            if #unmatched > 0 then
                log(string.format("  Unmatched: %d edges from tile1", #unmatched))

                -- Categorize why they didn't match
                local no_nearby = 0      -- No edge nearby in XY
                local z_mismatch = 0     -- XY close but Z too different
                local xy_mismatch = 0    -- XY slightly off

                for _, u in ipairs(unmatched) do
                    if u.dxy > 1.0 then
                        no_nearby = no_nearby + 1
                    elseif u.dxy < EPSILON_XY and u.dz > EPSILON_Z then
                        z_mismatch = z_mismatch + 1
                        -- Track near-miss (would match with larger Z epsilon)
                        table.insert(all_near_miss.xy, u.dxy)
                        table.insert(all_near_miss.z, u.dz)
                    else
                        xy_mismatch = xy_mismatch + 1
                        -- Track near-miss (would match with larger XY epsilon)
                        if u.dxy < 2.0 then
                            table.insert(all_near_miss.xy, u.dxy)
                            table.insert(all_near_miss.z, u.dz)
                        end
                    end
                end

                log(string.format("    - No nearby edge (gap/corner): %d", no_nearby))
                log(string.format("    - Z mismatch (dZ > %.2f): %d", EPSILON_Z, z_mismatch))
                log(string.format("    - XY mismatch (dXY > %.3f): %d", EPSILON_XY, xy_mismatch))

                -- Show worst cases
                table.sort(unmatched, function(a, b) return a.dxy < b.dxy end)
                log("  Closest unmatched (should match but didn't):")
                for i = 1, math.min(3, #unmatched) do
                    local u = unmatched[i]
                    if u.dxy < 1.0 then
                        log(string.format("    poly%d: dXY=%.4f, dZ=%.4f",
                            u.e1.poly_idx, u.dxy, u.dz))
                        log(string.format("      E1: (%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)",
                            u.e1.v1.x, u.e1.v1.y, u.e1.v1.z, u.e1.v2.x, u.e1.v2.y, u.e1.v2.z))
                        if u.e2 then
                            log(string.format("      E2: (%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)",
                                u.e2.v1.x, u.e2.v1.y, u.e2.v1.z, u.e2.v2.x, u.e2.v2.y, u.e2.v2.z))
                        end
                    end
                end
            end
            log("")

            -- Count gaps (edges with no nearby counterpart)
            local gaps = 0
            for _, u in ipairs(unmatched) do
                if u.dxy > 1.0 then gaps = gaps + 1 end
            end

            -- Corrected rate: excluding gaps (edges that genuinely have no pair)
            local corrected_edges = #edges1 - gaps
            local corrected_rate = corrected_edges > 0 and (#matches / corrected_edges * 100) or 0

            total_matches = total_matches + #matches
            table.insert(results, {
                desc = desc,
                edges1 = #edges1,
                edges2 = #edges2,
                matches = #matches,
                rate = match_rate,
                gaps = gaps,
                corrected_rate = corrected_rate
            })
        else
            log(string.format("%s: SKIPPED (missing tile data)", desc))
            log("")
        end
    end

    -- Summary table
    local elapsed_ms = (core.cpu_ticks() - start_time) / ticks_per_ms
    log("==============================================")
    log("                  SUMMARY")
    log("==============================================")
    log("")
    log(string.format("%-30s %5s %5s %5s %5s %5s %6s", "Adjacency", "E1", "E2", "Match", "Gaps", "Rate", "Adj%"))
    log(string.rep("-", 75))
    local total_gaps = 0
    for _, r in ipairs(results) do
        log(string.format("%-30s %5d %5d %5d %5d %4.1f%% %5.1f%%",
            r.desc, r.edges1, r.edges2, r.matches, r.gaps or 0, r.rate, r.corrected_rate or r.rate))
        total_gaps = total_gaps + (r.gaps or 0)
    end
    log(string.rep("-", 75))
    log(string.format("%-30s %5s %5s %5d %5d", "TOTAL", "", "", total_matches, total_gaps))
    log("")
    log("Rate = raw match rate, Adj% = adjusted (excluding gaps/corners)")
    log("")
    log(string.format("Time: %.2f ms", elapsed_ms))
    log("")

    -- Calculate overall adjusted rate
    local total_matchable = 0
    local total_matched = 0
    for _, r in ipairs(results) do
        total_matchable = total_matchable + (r.edges1 - (r.gaps or 0))
        total_matched = total_matched + r.matches
    end
    local overall_adj_rate = total_matchable > 0 and (total_matched / total_matchable * 100) or 0

    -- EPSILON ANALYSIS
    log("==============================================")
    log("            EPSILON ANALYSIS")
    log("==============================================")
    log("")

    -- Analyze matched edge distances
    if #all_match_distances.xy > 0 then
        table.sort(all_match_distances.xy)
        table.sort(all_match_distances.z)

        local max_xy = all_match_distances.xy[#all_match_distances.xy]
        local max_z = all_match_distances.z[#all_match_distances.z]
        local p95_xy = all_match_distances.xy[math.ceil(#all_match_distances.xy * 0.95)]
        local p95_z = all_match_distances.z[math.ceil(#all_match_distances.z * 0.95)]
        local p99_xy = all_match_distances.xy[math.ceil(#all_match_distances.xy * 0.99)]
        local p99_z = all_match_distances.z[math.ceil(#all_match_distances.z * 0.99)]

        log(string.format("MATCHED EDGES (%d pairs):", #all_match_distances.xy))
        log(string.format("  XY distance: max=%.4f, 99th=%.4f, 95th=%.4f", max_xy, p99_xy, p95_xy))
        log(string.format("  Z distance:  max=%.4f, 99th=%.4f, 95th=%.4f", max_z, p99_z, p95_z))
        log("")

        -- Epsilon sweep - show match rates at different thresholds
        log("EPSILON SWEEP (XY only, Z=1.0):")
        local test_epsilons = {0.001, 0.01, 0.05, 0.10, 0.20, 0.30, 0.50, 0.80, 1.00}
        for _, eps in ipairs(test_epsilons) do
            local count = 0
            for _, d in ipairs(all_match_distances.xy) do
                if d <= eps then count = count + 1 end
            end
            local pct = #all_match_distances.xy > 0 and (count / #all_match_distances.xy * 100) or 0
            log(string.format("  eps=%.3f: %d/%d matches (%.1f%%)", eps, count, #all_match_distances.xy, pct))
        end
        log("")
    end

    -- Analyze near-miss distances (would match with larger epsilon)
    if #all_near_miss.xy > 0 then
        table.sort(all_near_miss.xy)
        table.sort(all_near_miss.z)

        local max_xy = all_near_miss.xy[#all_near_miss.xy]
        local max_z = all_near_miss.z[#all_near_miss.z]

        log(string.format("NEAR-MISS EDGES (%d pairs that would match with larger epsilon):", #all_near_miss.xy))
        log(string.format("  XY distance: max=%.4f", max_xy))
        log(string.format("  Z distance:  max=%.4f", max_z))
        log("")
        log("To get 100%% match rate (excluding gaps), use:")
        log(string.format("  EPSILON_XY >= %.3f", max_xy + 0.01))
        log(string.format("  EPSILON_Z  >= %.3f", max_z + 0.01))
    else
        log("No near-miss edges - current epsilon values are sufficient!")
    end
    log("")

    -- Final result
    if overall_adj_rate >= 90 then
        log(string.format("RESULT: %.1f%% adjusted match rate across %d adjacencies", overall_adj_rate, #adjacencies))
        log("Cross-tile vertex matching verified - ready for navigation graph.")
    elseif total_matches > 0 then
        log(string.format("PARTIAL: %.1f%% adjusted match rate - some edges don't match", overall_adj_rate))
        log("Navigation may have gaps at some tile boundaries.")
    else
        log("WARNING: No matches found - check direction mapping")
    end

    log("==============================================")

    Debug.log(string.format("Extended test: %d matches across %d adjacencies (see parse_log_crosstile.log)",
        total_matches, #adjacencies))
end

-- Scan ALL tiles to find which one actually contains the player position
local function scan_all_tiles_for_player()
    local LOG_FILE = "parse_log_tilescan.log"
    core.create_log_file(LOG_FILE)
    local function log(msg) core.write_log_file(LOG_FILE, msg .. "\n") end

    local player = core.object_manager.get_local_player()
    if not player then return end
    local pos = player:get_position()
    if not pos then return end
    local map_id = core.get_instance_id()
    if not map_id then return end

    log("==============================================")
    log("       TILE SCAN - FIND PLAYER'S TILE")
    log("==============================================")
    log(string.format("Player WoW position: (%.2f, %.2f, %.2f)", pos.x, pos.y, pos.z))
    log(string.format("Map ID: %d", map_id))
    log("")

    -- Scan a range of tiles and check polygon vertex positions
    local tiles_checked = 0
    local tiles_found = 0
    local closest_tile = nil
    local closest_dist = 999999

    log("Checking tiles 25-35 x 35-45...")
    log("")

    for tx = 25, 35 do
        for ty = 35, 45 do
            local filename = string.format("mmaps/%04d_%02d_%02d.mmtile", map_id, tx, ty)
            local data = core.read_data_file(filename)
            if data and #data > 0 then
                local tile = TileParser.parse(data)
                if tile and tile.polygons and #tile.polygons > 0 then
                    tiles_checked = tiles_checked + 1

                    -- Check if any polygon center is near the player
                    local min_dist = 999999
                    local closest_poly = nil
                    for i, poly in ipairs(tile.polygons) do
                        if poly.center then
                            local dx = poly.center.x - pos.x
                            local dy = poly.center.y - pos.y
                            local dist = math.sqrt(dx*dx + dy*dy)
                            if dist < min_dist then
                                min_dist = dist
                                closest_poly = poly
                            end
                        end
                    end

                    -- Log tile info
                    local status = "FAR"
                    if min_dist < 50 then
                        status = "*** CLOSE ***"
                        tiles_found = tiles_found + 1
                    elseif min_dist < 500 then
                        status = "NEARBY"
                    end

                    if min_dist < closest_dist then
                        closest_dist = min_dist
                        closest_tile = {tx=tx, ty=ty, dist=min_dist}
                    end

                    if min_dist < 500 or tx >= 28 and tx <= 31 and ty >= 38 and ty <= 42 then
                        log(string.format("Tile %d_%d (mesh %d_%d): %d polys, closest=%.1f %s",
                            tx, ty, tile.tileX, tile.tileY, #tile.polygons, min_dist, status))
                        if closest_poly then
                            log(string.format("  Closest poly center: (%.2f, %.2f, %.2f)",
                                closest_poly.center.x, closest_poly.center.y, closest_poly.center.z))
                        end
                        if tile.boundsWow then
                            log(string.format("  WoW bounds: X[%.1f,%.1f] Y[%.1f,%.1f]",
                                tile.boundsWow.min.x, tile.boundsWow.max.x,
                                tile.boundsWow.min.y, tile.boundsWow.max.y))
                        end
                    end
                end
            end
        end
    end

    log("")
    log("==============================================")
    log("                 RESULTS")
    log("==============================================")
    log(string.format("Tiles checked: %d", tiles_checked))
    log(string.format("Tiles with polys within 50 units: %d", tiles_found))
    if closest_tile then
        log(string.format("Closest tile: %d_%d at distance %.1f", closest_tile.tx, closest_tile.ty, closest_tile.dist))
    end
    log("")

    if tiles_found == 0 then
        log("WARNING: No tile found containing player!")
        log("This suggests the Recast→WoW coordinate conversion is wrong.")
        log("")
        log("Expected player position range:")
        log(string.format("  X: %.1f ± 50", pos.x))
        log(string.format("  Y: %.1f ± 50", pos.y))
    end

    log("==============================================")
    Debug.log("Tile scan complete - see parse_log_tilescan.log")
end

-- =========================
-- Pathfinding Functions
-- =========================

-- Initialize pathfinding system
local function init_pathfinding()
    if PathState.world then return end  -- Already initialized

    PathState.world = NavWorld.new()
    PathState.query = NavQuery.new(PathState.world)

    Debug.log("[Path] Pathfinding system initialized")
end

-- Sync NavWorld with loaded tiles
local function sync_pathfinding()
    if not PathState.world then return end

    local mgr = Wireframe.get_tile_manager()
    if not mgr then return end

    local instanceId = core.get_instance_id()
    local added = PathState.world:sync_with_tile_manager(mgr, instanceId)

    if added > 0 then
        local stats = PathState.world:get_stats()
        Debug.log(string.format("[Path] Synced %d tiles (total: %d tiles, %d polys, %d resolved edges)",
            added, stats.tiles, stats.polys, stats.resolvedEdges))
    end
end

-- Find path from player to target position
local function find_path_to(targetX, targetY, targetZ)
    if not PathState.world or not PathState.query then
        Debug.log_error("[Path] Pathfinding not initialized")
        return false
    end

    local player = core.object_manager.get_local_player()
    if not player then
        Debug.log_error("[Path] No player")
        return false
    end

    local pos = player:get_position()
    if not pos then
        Debug.log_error("[Path] No player position")
        return false
    end

    Debug.log(string.format("[Path] Finding path: (%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f)",
        pos.x, pos.y, pos.z, targetX, targetY, targetZ))

    local result = PathState.query:find_path(pos.x, pos.y, pos.z, targetX, targetY, targetZ)

    if result.success then
        PathState.path = result.path
        PathState.polyPath = result.polyPath
        PathState.stats = result.stats
        PathState.targetPos = {x = targetX, y = targetY, z = targetZ}

        Debug.log(string.format("[Path] SUCCESS: %d polys, %d waypoints, %.2f ms A*, %.2f ms funnel",
            result.stats.polys or 0, result.stats.waypoints or 0, result.stats.astarMs or 0, result.stats.funnelMs or 0))
        return true
    else
        Debug.log_error(string.format("[Path] FAILED: %s (expansions: %d)",
            result.error or "unknown", result.expansions or 0))
        -- Clear stale path visual to avoid showing invalid route
        PathState.path = nil
        PathState.polyPath = nil
        PathState.targetPos = nil
        return false
    end
end

-- Find path to current target (from targeting system)
local function find_path_to_target()
    local player = core.object_manager.get_local_player()
    if not player then
        Debug.log_error("[Path] No local player")
        return false
    end

    local target = player:get_target()
    if not target then
        Debug.log_error("[Path] No target selected")
        return false
    end

    local pos = target:get_position()
    if not pos then
        Debug.log_error("[Path] Target has no position")
        return false
    end

    return find_path_to(pos.x, pos.y, pos.z)
end

-- Clear current path
local function clear_path()
    PathState.path = nil
    PathState.polyPath = nil
    PathState.stats = nil
    PathState.targetPos = nil
    Debug.log("[Path] Path cleared")
end

-- Draw path
local function draw_path()
    if not PathState.path or #PathState.path < 2 then return end

    local path = PathState.path
    local pathColor = color.new(0, 255, 255, 255)  -- Cyan
    local waypointColor = color.new(255, 255, 0, 255)  -- Yellow

    -- Draw lines between waypoints
    for i = 1, #path - 1 do
        local p1 = path[i]
        local p2 = path[i + 1]

        local v1 = vec3.new(p1.x, p1.y, (p1.z or 0) + 0.5)  -- Slightly above ground
        local v2 = vec3.new(p2.x, p2.y, (p2.z or 0) + 0.5)

        core.graphics.line_3d(v1, v2, pathColor, 2.0)
    end

    -- Draw waypoint markers
    for i, p in ipairs(path) do
        local v = vec3.new(p.x, p.y, (p.z or 0) + 0.5)
        core.graphics.circle_3d_filled(v, 0.3, waypointColor)
    end

    -- Draw target marker
    if PathState.targetPos then
        local t = PathState.targetPos
        local v = vec3.new(t.x, t.y, (t.z or 0) + 1.0)
        core.graphics.circle_3d_filled(v, 0.5, color.new(255, 0, 0, 255))  -- Red
    end
end

-- Initialize plugin
local function initialize()
    Debug.init()
    Debug.log("LX_Nav initializing...")

    -- Log player position for reference
    local player = core.object_manager.get_local_player()
    if player then
        local pos = player:get_position()
        if pos then
            Debug.log(string.format("Player position: (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z))
        end
        local map_id = core.get_instance_id()
        Debug.log(string.format("Map ID: %d", map_id))
    end

    -- NOTE: scan_all_tiles_for_player() removed - was causing 6 second freeze
    -- Run it manually if needed via menu or console

    -- NOTE: Tests are available but not run on every load to avoid freeze
    -- To run tests, uncomment the desired test below:
    -- test_binary_helpers()
    -- test_mmap_parser()
    -- test_cross_tile_connections()

    -- Initialize pathfinding system
    init_pathfinding()

    -- Initialize repair module with pathfinding state
    Repair.init(PathState)

    -- Connect repair module to pathfinding (for blacklist/bridge support)
    NavQuery.set_repair_module(Repair)

    -- DISABLED: Old hardcoded fallback system - now using Repair module bridges instead
    -- local ok, msg = NavQuery.load_spiral_ramp_path()
    -- if ok then
    --     Debug.log("[Path] Loaded spiral ramp fallback path: " .. msg)
    -- end

    State.initialized = true
    Debug.log("LX_Nav initialized successfully")
    core.log("[LX_Nav] Loaded")
end

-- Update callback (called every frame)
local function on_update()
    if not State.initialized then return end

    -- Update debug frame timing
    Debug.update_frame_time()

    -- Check enabled state from menu
    State.enabled = menu_elements.enabled:get_state()
    if not State.enabled then return end

    -- Ensure tiles are loading for pathfinding (even when wireframe is off)
    local mgr = Wireframe.get_tile_manager()
    if mgr then
        -- Queue nearby tiles based on player position
        local player = core.object_manager.get_local_player()
        if player then
            local pos = player:get_position()
            if pos then
                local instanceId = core.get_instance_id()
                mgr:queue_nearby(instanceId, pos.x, pos.y)
            end
        end
        -- Process tile loading (frame-budgeted)
        mgr:process_frame(3.0)
    end

    -- Sync pathfinding world with loaded tiles
    sync_pathfinding()

    -- Process floor height snapping incrementally (non-blocking)
    NavQuery.process_floor_snapping(3)  -- 3 waypoints per frame

    -- Handle click-to-path mode
    if click_to_path_mode then
        local mouse_down = core.input.is_key_pressed(0x01)
        if mouse_down and not prev_mouse_down then  -- Rising edge = click
            local world_pos = core.graphics.get_cursor_world_position()
            if world_pos then
                find_path_to(world_pos.x, world_pos.y, world_pos.z)
                click_to_path_mode = false
                Debug.log("[Path] Click destination set")
            end
        end
        prev_mouse_down = mouse_down
    else
        prev_mouse_down = core.input.is_key_pressed(0x01)
    end

    -- Path recorder logic
    if PathRecorder.is_recording then
        local player = core.object_manager.get_local_player()
        if player then
            local pos = player:get_position()
            local current_time = core.time()

            -- Check if enough time has passed since last record
            if current_time - PathRecorder.last_record_time >= PathRecorder.record_interval then
                -- Check distance from last point
                local should_record = true
                if #PathRecorder.points > 0 then
                    local last = PathRecorder.points[#PathRecorder.points]
                    local dx = pos.x - last.x
                    local dy = pos.y - last.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist < PathRecorder.min_distance then
                        should_record = false
                    end
                end

                if should_record then
                    PathRecorder.points[#PathRecorder.points + 1] = {
                        x = pos.x,
                        y = pos.y,
                        z = pos.z,
                        time = current_time - PathRecorder.start_time
                    }
                    PathRecorder.last_record_time = current_time
                end
            end
        end
    end

    -- Repair mode click handling (v2 with triangle detection and mouse capture)
    if Repair.is_enabled() then
        local mouse_down = core.input.is_key_pressed(0x01)
        local world_pos = core.graphics.get_cursor_world_position()

        -- Update hover preview every frame
        if world_pos then
            Repair.update_hover(world_pos)
        end

        -- CRITICAL: Block camera movement while dragging
        if Repair.is_dragging() then
            core.graphics.capture_next_mouse_input()  -- Call every frame!
        end

        -- Check if cursor is over menu area (left side of screen) to prevent click passthrough
        local cursor_screen = core.get_cursor_position()
        local screen_size = core.graphics.get_screen_size()
        local menu_width = 350  -- Approximate menu width
        local cursor_in_menu = cursor_screen and cursor_screen.x < menu_width

        if mouse_down then
            if not repair_prev_mouse then
                -- Click START - skip if cursor is over menu
                if world_pos and not cursor_in_menu then
                    local mode = Repair.get_mode()
                    -- Only check for drag when in blacklist_point mode
                    if mode == "blacklist_point" then
                        local drag_target, drag_idx = Repair.get_blacklist_point_at(world_pos)
                        if drag_target then
                            Repair.set_selected_point_idx(drag_idx)
                            Repair.start_drag(drag_target)
                        else
                            Repair.handle_click(world_pos)
                        end
                    else
                        Repair.handle_click(world_pos)
                    end
                end
            elseif Repair.is_dragging() then
                -- DRAGGING - update position
                if world_pos then
                    Repair.update_drag_position(world_pos)
                end
            end
        else
            -- Mouse released
            if Repair.is_dragging() then
                Repair.end_drag()
            end
        end
        repair_prev_mouse = mouse_down
    end

    -- Process extraction coroutine (frame-budgeted)
    if ExtractState.running then
        process_extraction()
    end
end

-- Render callback (called every frame for drawing)
local function on_render()
    if not State.initialized then return end
    if not State.enabled then return end

    -- Update wireframe settings from menu
    local wireframe_enabled = menu_elements.wireframe_enabled:get_state()
    local wireframe_range = menu_elements.wireframe_range:get()
    local bvnodes_enabled = menu_elements.wireframe_bvnodes:get_state()
    local cross_tile_enabled = menu_elements.wireframe_cross_tile:get_state()

    Wireframe.set_enabled(wireframe_enabled)
    Wireframe.set_range(wireframe_range)
    Wireframe.set_bvnodes_enabled(bvnodes_enabled)
    Wireframe.set_cross_tile_enabled(cross_tile_enabled)

    -- Render wireframe
    if wireframe_enabled then
        Wireframe.render()

        -- Render polygon connection arrows (follows wireframe)
        if PathState.world then
            Wireframe.render_cross_tile(PathState.world:get_all_tiles())
        end

        -- Auto-run cross-tile test once when 9 tiles are loaded
        if not State.crosstile_test_done then
            local mgr = Wireframe.get_tile_manager()
            if mgr then
                local stats = mgr:get_stats()
                if stats.cached >= 9 and stats.queued == 0 then
                    Debug.log("[Auto] Running cross-tile connection test...")
                    test_cross_tile_connections()
                    State.crosstile_test_done = true
                end
            end
        end
    end

    -- Render repair highlights (selected, bridged, blacklisted)
    Repair.render()

    -- Draw path if enabled
    local path_enabled = menu_elements.path_enabled:get_state()
    if path_enabled then
        draw_path()
    end

    -- Draw recorded path points
    if #PathRecorder.points > 0 then
        local color_point = require("common/color").new(255, 128, 0, 255)     -- Orange for points
        local color_line = require("common/color").new(255, 200, 0, 200)       -- Yellow for lines
        local color_recording = require("common/color").new(255, 0, 0, 255)    -- Red for recording indicator

        for i, pt in ipairs(PathRecorder.points) do
            local screen = core.graphics.w2s(require("common/geometry/vector_3").new(pt.x, pt.y, pt.z))
            if screen and screen.x > 0 and screen.y > 0 then
                -- Draw point circle
                core.graphics.circle_2d_filled(screen, 4, color_point)

                -- Draw line to next point
                if i < #PathRecorder.points then
                    local next_pt = PathRecorder.points[i + 1]
                    local next_screen = core.graphics.w2s(require("common/geometry/vector_3").new(next_pt.x, next_pt.y, next_pt.z))
                    if next_screen and next_screen.x > 0 and next_screen.y > 0 then
                        core.graphics.line_2d(screen, next_screen, color_line, 2)
                    end
                end
            end
        end

        -- Show recording indicator
        if PathRecorder.is_recording then
            local screen_size = core.graphics.get_screen_size()
            local indicator_pos = require("common/geometry/vector_2").new(screen_size.x - 120, 50)
            core.graphics.circle_2d_filled(indicator_pos, 8, color_recording)
            core.graphics.text_2d("REC", require("common/geometry/vector_2").new(screen_size.x - 100, 42), 16, color_recording, false)
            core.graphics.text_2d(string.format("%d pts", #PathRecorder.points),
                require("common/geometry/vector_2").new(screen_size.x - 100, 58), 12, color_point, false)
        end
    end

    -- Show debug stats if enabled
    local show_debug = menu_elements.show_debug:get_state()
    if show_debug then
        local extra = {
            "LX_Nav: Active",
        }

        if wireframe_enabled then
            table.insert(extra, string.format("Wireframe: ON (range: %d)", wireframe_range))
        end

        -- Show pathfinding stats
        if PathState.world then
            local worldStats = PathState.world:get_stats()
            table.insert(extra, string.format("NavWorld: %d tiles, %d polys", worldStats.tiles, worldStats.polys))
        end

        if PathState.stats then
            table.insert(extra, string.format("Path: %d polys, %d waypoints", PathState.stats.polys, PathState.stats.waypoints))
        end

        -- Show extraction progress if running
        local status = get_extraction_status()
        if status then
            local pct = status.total > 0 and math.floor(status.progress / status.total * 100) or 0
            table.insert(extra, string.format("Extracting: %s (%d/%d) %d%%",
                status.section, status.progress, status.total, pct))
        end

        Debug.render_stats(extra)
    end
end

-- Menu render callback
local function on_render_menu()
    menu_elements.main_tree:render("LX_Nav", function()
        menu_elements.enabled:render("Enable Plugin")
        menu_elements.show_debug:render("Show Debug Stats")

        -- Wireframe submenu
        menu_elements.wireframe_tree:render("Wireframe", function()
            menu_elements.wireframe_enabled:render("Enable Wireframe")
            menu_elements.wireframe_range:render("Draw Range (yards)")
            menu_elements.wireframe_bvnodes:render("Show BVNodes (spatial tree)")
            -- Polygon link arrows now follow wireframe automatically

            -- Repair tools submenu (v3 - multi-waypoint bridges, undo, delete UI)
            menu_elements.repair_tree:render("Repair Tools", function()
                -- Enable toggle
                menu_elements.repair_enabled:render("Enable Repair Mode")
                Repair.set_enabled(menu_elements.repair_enabled:get_state())

                if Repair.is_enabled() then
                    local mode = Repair.get_mode()

                    -- === MODE SELECTION (toggle on/off) ===
                    local bridge_label = mode == "bridge" and "Bridge Mode [ACTIVE]" or "Bridge Mode (K+click)"
                    if menu_elements.repair_mode_connect:render(bridge_label) then
                        Repair.set_mode(mode == "bridge" and nil or "bridge")
                    end

                    local bl_tri_label = mode == "blacklist_tri" and "Block Triangle [ACTIVE]" or "Block Triangle"
                    if menu_elements.repair_mode_blacklist_poly:render(bl_tri_label) then
                        Repair.set_mode(mode == "blacklist_tri" and nil or "blacklist_tri")
                    end

                    local bl_point_label = mode == "blacklist_point" and "Block Area [ACTIVE]" or "Block Area (radius)"
                    if menu_elements.repair_mode_blacklist_point:render(bl_point_label) then
                        Repair.set_mode(mode == "blacklist_point" and nil or "blacklist_point")
                    end

                    -- === RADIUS SLIDER (right after Block Area, when point is selected) ===
                    local sel_idx = Repair.get_selected_point_idx()
                    if sel_idx then
                        local points = Repair.get_blacklist_points()
                        if points[sel_idx] then
                            menu_elements.repair_point_radius:render("Radius")
                            local new_radius = menu_elements.repair_point_radius:get()
                            if new_radius ~= points[sel_idx].radius then
                                Repair.set_point_radius(sel_idx, new_radius)
                            end
                        end
                    end

                    -- === RECORDING STATE (bridge mode) ===
                    if Repair.is_recording() then
                        local wps = Repair.get_recording_waypoints()
                        if menu_elements.repair_cancel_recording:render(string.format("Cancel Recording (%d pts)", #wps)) then
                            Repair.cancel_recording()
                        end
                    end

                    -- === STAGED BRIDGES ===
                    local staged_count = Repair.get_staged_count()
                    if staged_count > 0 then
                        if menu_elements.repair_save_bridges:render(string.format("Save Bridges (%d)", staged_count)) then
                            Repair.save_staged_bridges()
                        end
                        if menu_elements.repair_cancel_staged:render("Cancel All Staged") then
                            Repair.clear_staged_bridges()
                        end
                        if menu_elements.repair_remove_last_staged:render("Remove Last Staged") then
                            Repair.remove_staged_bridge(staged_count)
                        end
                    end

                    -- === UNDO ===
                    if Repair.has_undo_action() then
                        local action_type = Repair.get_last_action_type()
                        local undo_label = "Undo"
                        if action_type == "add_bridge" then
                            undo_label = "Undo (bridge)"
                        elseif action_type == "add_blacklist_tri" then
                            undo_label = "Undo (blocked tri)"
                        elseif action_type == "add_blacklist_point" then
                            undo_label = "Undo (blocked area)"
                        end
                        if menu_elements.repair_undo:render(undo_label) then
                            Repair.undo_last_action()
                        end
                    end

                    -- === SAVED DATA TREES ===
                    local bridges = Repair.get_bridges()
                    local bl_tris = Repair.get_blacklist_tris()
                    local bl_points = Repair.get_blacklist_points()

                    -- Bridges tree (click to preview/highlight, click again to delete)
                    if #bridges > 0 then
                        local preview_bridge = Repair.get_preview_bridge_idx()
                        menu_elements.repair_bridges_tree:render(string.format("Bridges (%d)", #bridges), function()
                            for i, bridge in ipairs(bridges) do
                                local wps = bridge.waypoints
                                if wps and #wps >= 2 then
                                    local is_selected = (i == preview_bridge)
                                    local label = is_selected
                                        and string.format("[DELETE] #%d (%d pts)", i, #wps)
                                        or string.format("Select #%d (%d pts)", i, #wps)
                                    if menu_elements.repair_delete_bridge:render(label .. "##bdel" .. i) then
                                        if is_selected then
                                            Repair.remove_bridge(i)
                                            Repair.clear_all_previews()
                                        else
                                            Repair.set_preview_bridge_idx(i)
                                        end
                                    end
                                end
                            end
                            if menu_elements.repair_clear_bridges:render("Clear All Bridges") then
                                Repair.clear_all_bridges()
                                Repair.clear_all_previews()
                            end
                        end)
                    end

                    -- Blocked triangles tree (click to preview, click again to delete)
                    if #bl_tris > 0 then
                        local preview_tri = Repair.get_preview_tri_idx()
                        menu_elements.repair_tris_tree:render(string.format("Blocked Tris (%d)", #bl_tris), function()
                            for i, bl in ipairs(bl_tris) do
                                local is_selected = (i == preview_tri)
                                local label = is_selected
                                    and string.format("[DELETE] T:%d P:%d", bl.tileId, bl.polyIdx)
                                    or string.format("Select T:%d P:%d Tri:%d", bl.tileId, bl.polyIdx, bl.triangleIdx)
                                if menu_elements.repair_delete_tri:render(label .. "##tdel" .. i) then
                                    if is_selected then
                                        Repair.remove_blacklist_tri(i)
                                        Repair.clear_all_previews()
                                    else
                                        Repair.set_preview_tri_idx(i)
                                    end
                                end
                            end
                            if menu_elements.repair_clear_tris:render("Clear All Blocked Tris") then
                                Repair.clear_all_blacklist_tris()
                                Repair.clear_all_previews()
                            end
                        end)
                    end

                    -- Blocked areas tree (click to preview, click again to delete)
                    if #bl_points > 0 then
                        local preview_point = Repair.get_preview_point_idx()
                        menu_elements.repair_points_tree:render(string.format("Blocked Areas (%d)", #bl_points), function()
                            for i, pt in ipairs(bl_points) do
                                local is_selected = (i == preview_point)
                                local label = is_selected
                                    and string.format("[DELETE] (%.0f,%.0f) R=%d", pt.x, pt.y, pt.radius)
                                    or string.format("Select (%.0f,%.0f) R=%d", pt.x, pt.y, pt.radius)
                                if menu_elements.repair_delete_point:render(label .. "##pdel" .. i) then
                                    if is_selected then
                                        Repair.remove_blacklist_point(i)
                                        Repair.clear_all_previews()
                                    else
                                        Repair.set_preview_point_idx(i)
                                    end
                                end
                            end
                            if menu_elements.repair_clear_points:render("Clear All Blocked Areas") then
                                Repair.clear_all_blacklist_points()
                                Repair.clear_all_previews()
                            end
                        end)
                    end
                end
            end)
        end)

        -- Pathfinding submenu
        menu_elements.path_tree:render("Pathfinding", function()
            menu_elements.path_enabled:render("Show Path")

            if menu_elements.path_to_target:render("Path to Target") then
                find_path_to_target()
            end

            local click_label = click_to_path_mode and "Path to Click [ACTIVE]" or "Path to Click"
            if menu_elements.path_to_click:render(click_label) then
                click_to_path_mode = not click_to_path_mode
                Debug.log(click_to_path_mode and "[Path] Click mode ON" or "[Path] Click mode OFF")
            end

            if menu_elements.save_safe_pos:render("Save Safe Pos") then
                local player = core.object_manager.get_local_player()
                if player then
                    local pos = player:get_position()
                    saved_safe_pos = {x = pos.x, y = pos.y, z = pos.z, map_id = core.get_instance_id()}
                    Debug.log(string.format("[Safe] Saved: %.1f, %.1f, %.1f", pos.x, pos.y, pos.z))
                end
            end

            local safe_label = saved_safe_pos and "Path to Safe Pos" or "Path to Safe Pos (none)"
            if menu_elements.path_to_safe_pos:render(safe_label) then
                if saved_safe_pos and core.get_instance_id() == saved_safe_pos.map_id then
                    find_path_to(saved_safe_pos.x, saved_safe_pos.y, saved_safe_pos.z)
                else
                    Debug.log_warning("[Path] No safe pos or wrong map")
                end
            end

            if menu_elements.path_clear:render("Clear Path") then
                clear_path()
            end
        end)

        -- Path Recorder submenu
        menu_elements.recorder_tree:render("Path Recorder", function()
            local toggle_label = PathRecorder.is_recording and "Stop Recording [REC]" or "Start Recording"
            if menu_elements.recorder_toggle:render(toggle_label) then
                PathRecorder.is_recording = not PathRecorder.is_recording
                if PathRecorder.is_recording then
                    PathRecorder.start_time = core.time()
                    PathRecorder.last_record_time = 0
                    Debug.log("[Recorder] Recording started")
                else
                    Debug.log(string.format("[Recorder] Recording stopped (%d points)", #PathRecorder.points))
                end
            end

            if menu_elements.recorder_clear:render("Clear Points") then
                PathRecorder.points = {}
                Debug.log("[Recorder] Points cleared")
            end

            local save_label = string.format("Save Path (%d pts)", #PathRecorder.points)
            if menu_elements.recorder_save:render(save_label) then
                if #PathRecorder.points > 0 then
                    -- Save to log file
                    local filename = "LX_Nav_recorded_path.log"
                    core.create_log_file(filename)

                    local lines = {}
                    lines[#lines + 1] = "=== RECORDED PATH ==="
                    lines[#lines + 1] = string.format("Points: %d", #PathRecorder.points)
                    lines[#lines + 1] = string.format("Map ID: %d", core.get_instance_id())
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = "-- Format: x, y, z, time"
                    for i, pt in ipairs(PathRecorder.points) do
                        lines[#lines + 1] = string.format("[%d] %.2f, %.2f, %.2f, %.2f",
                            i, pt.x, pt.y, pt.z, pt.time)
                    end
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = "-- Lua table format:"
                    lines[#lines + 1] = "local recorded_path = {"
                    for i, pt in ipairs(PathRecorder.points) do
                        local comma = i < #PathRecorder.points and "," or ""
                        lines[#lines + 1] = string.format("    {x=%.2f, y=%.2f, z=%.2f}%s",
                            pt.x, pt.y, pt.z, comma)
                    end
                    lines[#lines + 1] = "}"

                    core.write_log_file(filename, table.concat(lines, "\n"))
                    Debug.log(string.format("[Recorder] Saved %d points to %s", #PathRecorder.points, filename))
                else
                    Debug.log_warning("[Recorder] No points to save")
                end
            end
        end)

        -- Test submenu
        menu_elements.test_tree:render("Tests", function()
            if menu_elements.run_crosstile_test:render("Run Cross-Tile Test") then
                Debug.log("[Menu] Running cross-tile connection test...")
                test_cross_tile_connections()
            end
        end)
    end)
end

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)

-- Run initialization
initialize()
