-- LX_Nav2 mmap File Parser
-- Parses .mmap files to extract dtNavMeshParams

local Binary = require("modules/binary")

local MMapParser = {}

-- Calculate log2 (returns floor of log2)
local function ilog2(v)
    if v <= 0 then return 0 end
    local r = 0
    while v > 1 do
        v = math.floor(v / 2)
        r = r + 1
    end
    return r
end

-- Calculate next power of 2
local function next_pow2(v)
    if v <= 1 then return 1 end
    v = v - 1
    local power = 1
    while power < v do
        power = power * 2
    end
    return power * 2
end

--- Parse .mmap file to extract dtNavMeshParams
-- @param data string Binary data from .mmap file
-- @return table|nil params
-- @return string|nil error
function MMapParser.parse(data)
    if not data or #data < 36 then
        return nil, string.format("File too short: %d bytes (need at least 36)", data and #data or 0)
    end

    local pos = 1
    local params = {}

    -- Header (8 bytes)
    params.magic = Binary.read_u32(data, pos); pos = pos + 4
    if params.magic ~= 0x4D4D4150 then
        return nil, string.format("Invalid magic: 0x%08X (expected 0x4D4D4150)", params.magic)
    end

    params.version = Binary.read_u32(data, pos); pos = pos + 4

    -- dtNavMeshParams structure (28 bytes)
    -- float orig[3] - 12 bytes
    params.orig = {
        x = Binary.read_f32(data, pos),
        y = Binary.read_f32(data, pos + 4),
        z = Binary.read_f32(data, pos + 8)
    }
    pos = pos + 12

    -- float tileWidth, tileHeight - 8 bytes
    params.tileWidth = Binary.read_f32(data, pos); pos = pos + 4
    params.tileHeight = Binary.read_f32(data, pos); pos = pos + 4

    -- int maxTiles, maxPolys - 8 bytes
    params.maxTiles = Binary.read_u32(data, pos); pos = pos + 4
    params.maxPolys = Binary.read_u32(data, pos); pos = pos + 4

    -- Debug: log raw values
    core.log(string.format("[MMapParser] Raw: maxTiles=%d (0x%08X), maxPolys=%d (0x%08X)",
        params.maxTiles, params.maxTiles, params.maxPolys, params.maxPolys))

    -- Validate maxTiles
    if params.maxTiles == 0 then
        core.log("[MMapParser] WARNING: maxTiles invalid, using default 4096")
        params.maxTiles = 4096
    end

    -- Detect 64-bit vs 32-bit poly reference mode
    -- TrinityCore uses DT_POLYREF64 with: SALT=12, TILE=21, POLY=31 (total 64 bits)
    -- Standard Detour uses 32-bit refs with dynamic bit allocation
    params.use64BitRefs = (params.maxPolys == 0x80000000)

    if params.use64BitRefs then
        -- 64-bit mode (TrinityCore): static bit allocation
        params.polyBits = 31  -- DT_POLY_BITS
        params.tileBits = 21  -- DT_TILE_BITS
        params.saltBits = 12  -- DT_SALT_BITS
        core.log("[MMapParser] Detected 64-bit poly refs (DT_POLYREF64)")
    else
        -- 32-bit mode: dynamic bit allocation based on maxTiles/maxPolys
        if params.maxPolys == 0 then
            core.log("[MMapParser] WARNING: maxPolys is 0, using default 32768")
            params.maxPolys = 32768
        end

        params.tileBits = ilog2(next_pow2(params.maxTiles))
        params.polyBits = ilog2(next_pow2(params.maxPolys))

        -- Validate: tileBits + polyBits <= 31 for 32-bit mode
        if params.tileBits + params.polyBits > 31 then
            core.log(string.format("[MMapParser] WARNING: Bit overflow in 32-bit mode, clamping"))
            params.polyBits = 31 - params.tileBits
        end

        -- Calculate salt bits (fills remaining space in 32-bit ref)
        params.saltBits = math.min(31, 32 - params.tileBits - params.polyBits)
    end

    return params, nil
end

--- Parse .mmap file from path
-- @param filename string Path relative to scripts_data (e.g., "mmaps/0001.mmap")
-- @return table|nil params
-- @return string|nil error
function MMapParser.parse_file(filename)
    local data = core.read_data_file(filename)
    if not data or #data == 0 then
        return nil, "Failed to read file: " .. tostring(filename)
    end
    return MMapParser.parse(data)
end

return MMapParser