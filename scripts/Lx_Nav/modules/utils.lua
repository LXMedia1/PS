--[[
    Lx_Nav Utilities
    Author: Lexxer

    Binary parsing helpers for reading PSNG files.
]]

local Config = require("modules/config")

local Utils = {}

-- Read unsigned 32-bit integer (little endian)
function Utils.read_uint32(data, offset)
    local b1 = string.byte(data, offset + 1) or 0
    local b2 = string.byte(data, offset + 2) or 0
    local b3 = string.byte(data, offset + 3) or 0
    local b4 = string.byte(data, offset + 4) or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Read signed 32-bit integer (little endian)
function Utils.read_int32(data, offset)
    local value = Utils.read_uint32(data, offset)
    if value >= 0x80000000 then
        return value - 0x100000000
    end
    return value
end

-- Read unsigned 16-bit integer (little endian)
function Utils.read_uint16(data, offset)
    local b1 = string.byte(data, offset + 1) or 0
    local b2 = string.byte(data, offset + 2) or 0
    return b1 + b2 * 256
end

-- Read signed 16-bit integer (little endian)
function Utils.read_int16(data, offset)
    local value = Utils.read_uint16(data, offset)
    if value >= 0x8000 then
        return value - 0x10000
    end
    return value
end

-- Read unsigned 8-bit integer
function Utils.read_uint8(data, offset)
    return string.byte(data, offset + 1) or 0
end

-- Read float (IEEE 754 single precision, little endian)
function Utils.read_float(data, offset)
    local b1 = string.byte(data, offset + 1) or 0
    local b2 = string.byte(data, offset + 2) or 0
    local b3 = string.byte(data, offset + 3) or 0
    local b4 = string.byte(data, offset + 4) or 0

    local sign = (b4 >= 128) and -1 or 1
    local exponent = ((b4 % 128) * 2) + math.floor(b3 / 128)
    local mantissa = ((b3 % 128) * 65536) + (b2 * 256) + b1

    if exponent == 0 then
        if mantissa == 0 then
            return 0
        else
            return sign * mantissa * 2^(-149)
        end
    elseif exponent == 255 then
        if mantissa == 0 then
            return sign * math.huge
        else
            return 0/0
        end
    else
        return sign * (1 + mantissa / 8388608) * 2^(exponent - 127)
    end
end

-- Convert fixed-point to float
function Utils.fixed_to_float(value, scale)
    return value / scale
end

-- Convert float to fixed-point
function Utils.float_to_fixed(value, scale)
    return math.floor(value * scale + 0.5)
end

-- Calculate 2D distance
function Utils.distance_2d(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx*dx + dy*dy)
end

-- Calculate 3D distance
function Utils.distance_3d(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Calculate 2D triangle area (for funnel algorithm)
-- Positive = counterclockwise, Negative = clockwise, Zero = collinear
function Utils.triangle_area_2d(ax, ay, bx, by, cx, cy)
    return (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
end

-- Get PSNG filename for a map
function Utils.get_psng_path(mapId)
    return string.format("%s/%04d.psng", Config.PSNG_PATH, mapId)
end

-- Debug logging
function Utils.log(msg)
    core.log("[Lx_Nav] " .. tostring(msg))
end

function Utils.log_warning(msg)
    core.log_warning("[Lx_Nav] " .. tostring(msg))
end

function Utils.log_error(msg)
    core.log_error("[Lx_Nav] " .. tostring(msg))
end

-- File logging
local LOG_FILE = "Lx_Nav.log"
local log_initialized = false

function Utils.file_log(msg)
    if not log_initialized then
        core.create_log_file(LOG_FILE)
        log_initialized = true
    end
    core.write_log_file(LOG_FILE, tostring(msg) .. "\n")
end

return Utils
