local Config = require("modules/config")
local Utils = require("modules/utils")

local Loader = {}

-- Tile cache
Loader.tile_cache = {}

-- Currently loaded tile keys
Loader.loaded_tiles = {}

-- NavVis file constants
local NAVVIS_MAGIC = 0x5349564E  -- 'NVIS' in little endian

-- Parse a .navvis file and return edges
function Loader.parse_navvis(data)
    if not data or #data < 16 then
        return nil, "File too small"
    end

    -- Read header
    local magic = Utils.read_uint32(data, 0)
    local version = Utils.read_uint32(data, 4)
    local edgeCount = Utils.read_uint32(data, 8)

    -- Verify magic
    if magic ~= NAVVIS_MAGIC then
        return nil, "Invalid magic number"
    end

    if version ~= 1 then
        return nil, "Unsupported version: " .. version
    end

    -- Calculate expected size (header 16 bytes + edges 28 bytes each)
    local expected_size = 16 + (edgeCount * 28)
    if #data < expected_size then
        return nil, "File truncated"
    end

    -- Parse edges
    local edges = {}
    local offset = 16

    for i = 1, edgeCount do
        local edge = {
            x1 = Utils.read_float(data, offset),
            y1 = Utils.read_float(data, offset + 4),
            z1 = Utils.read_float(data, offset + 8),
            x2 = Utils.read_float(data, offset + 12),
            y2 = Utils.read_float(data, offset + 16),
            z2 = Utils.read_float(data, offset + 20),
            edgeType = Utils.read_uint8(data, offset + 24),
            areaType = Utils.read_uint8(data, offset + 25),
        }
        edges[i] = edge
        offset = offset + 28
    end

    return edges
end

-- Load a tile from data file
function Loader.load_tile(mapId, tileX, tileY)
    local key = Utils.make_tile_key(mapId, tileX, tileY)

    -- Check cache first
    if Loader.tile_cache[key] then
        return Loader.tile_cache[key]
    end

    -- Build filename
    local filename = Config.data_path .. "/" .. key .. ".navvis"

    -- Try to read the file
    local data = core.read_data_file(filename)
    if not data then
        -- File doesn't exist, cache as empty
        Loader.tile_cache[key] = { edges = {}, empty = true }
        return Loader.tile_cache[key]
    end

    -- Parse the data
    local edges, err = Loader.parse_navvis(data)
    if not edges then
        core.log_warning("[LX_NavDebug] Failed to parse " .. filename .. ": " .. (err or "unknown"))
        Loader.tile_cache[key] = { edges = {}, empty = true }
        return Loader.tile_cache[key]
    end

    -- Cache the tile
    local tile = {
        mapId = mapId,
        tileX = tileX,
        tileY = tileY,
        edges = edges,
        empty = false
    }
    Loader.tile_cache[key] = tile

    core.log("[LX_NavDebug] Loaded " .. #edges .. " edges from " .. key)
    return tile
end

-- Get tiles around a position
function Loader.get_tiles_around(mapId, pos)
    local centerX, centerY = Utils.world_to_tile(pos)
    local tiles = {}

    local half = math.floor(Config.tile_grid_size / 2)

    for dx = -half, half do
        for dy = -half, half do
            local tx = centerX + dx
            local ty = centerY + dy

            -- Validate tile coordinates
            if tx >= 0 and tx < Config.MAP_SIZE and ty >= 0 and ty < Config.MAP_SIZE then
                local tile = Loader.load_tile(mapId, tx, ty)
                if tile and not tile.empty then
                    tiles[#tiles + 1] = tile
                end
            end
        end
    end

    return tiles
end

-- Update loaded tiles based on player position
function Loader.update_tiles(mapId, pos)
    local centerX, centerY = Utils.world_to_tile(pos)
    local half = math.floor(Config.tile_grid_size / 2)

    -- Calculate new tile set
    local new_tiles = {}
    for dx = -half, half do
        for dy = -half, half do
            local tx = centerX + dx
            local ty = centerY + dy
            if tx >= 0 and tx < Config.MAP_SIZE and ty >= 0 and ty < Config.MAP_SIZE then
                local key = Utils.make_tile_key(mapId, tx, ty)
                new_tiles[key] = true
            end
        end
    end

    -- Update loaded tiles set
    Loader.loaded_tiles = new_tiles

    -- Return tiles for rendering
    return Loader.get_tiles_around(mapId, pos)
end

-- Clear tile cache
function Loader.clear_cache()
    Loader.tile_cache = {}
    Loader.loaded_tiles = {}
    core.log("[LX_NavDebug] Cache cleared")
end

-- Get cache stats
function Loader.get_cache_stats()
    local count = 0
    local edges = 0
    for _, tile in pairs(Loader.tile_cache) do
        count = count + 1
        if tile.edges then
            edges = edges + #tile.edges
        end
    end
    return count, edges
end

return Loader
