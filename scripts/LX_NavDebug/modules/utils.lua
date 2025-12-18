local Config = require("modules/config")

-- Color module
local color = require("common/color")

local Utils = {}

-- Convert world position to tile coordinates
function Utils.world_to_tile(pos)
    -- WoW coordinate system:
    -- - Map center is at (0, 0)
    -- - Each tile is TILE_SIZE yards
    -- - Tile indices go from 0 to 63

    local tileX = math.floor((Config.MAP_OFFSET - (pos.x / Config.TILE_SIZE)))
    local tileY = math.floor((Config.MAP_OFFSET - (pos.y / Config.TILE_SIZE)))

    return tileX, tileY
end

-- Calculate 3D distance between two points
function Utils.distance_3d(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Calculate 2D distance (horizontal only)
function Utils.distance_2d(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx*dx + dy*dy)
end

-- Check if a point is within the front cone of the player
function Utils.is_in_front_cone(px, py, player_pos, player_facing, cone_angle_degrees)
    -- Calculate direction to point
    local dx = px - player_pos.x
    local dy = py - player_pos.y

    -- Skip if too close (avoid division issues)
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < 0.1 then
        return true
    end

    -- Normalize direction
    dx = dx / dist
    dy = dy / dist

    -- Player facing direction (WoW uses radians, 0 = north, increases counter-clockwise)
    local face_x = math.cos(player_facing)
    local face_y = math.sin(player_facing)

    -- Dot product gives cos of angle between vectors
    local dot = dx * face_x + dy * face_y

    -- Convert cone angle to radians and get cos threshold
    local half_cone = math.rad(cone_angle_degrees / 2)
    local cos_threshold = math.cos(half_cone)

    return dot >= cos_threshold
end

-- Check if an edge is within render distance of player
function Utils.is_edge_visible(edge, player_pos, max_distance)
    -- Check if either endpoint is within distance
    local d1 = Utils.distance_2d(edge.x1, edge.y1, player_pos.x, player_pos.y)
    local d2 = Utils.distance_2d(edge.x2, edge.y2, player_pos.x, player_pos.y)

    return d1 <= max_distance or d2 <= max_distance
end

-- Get edge midpoint
function Utils.edge_midpoint(edge)
    return {
        x = (edge.x1 + edge.x2) / 2,
        y = (edge.y1 + edge.y2) / 2,
        z = (edge.z1 + edge.z2) / 2
    }
end

-- Binary parsing helpers

-- Read uint32 from string at offset (little endian)
function Utils.read_uint32(data, offset)
    local b1 = string.byte(data, offset + 1) or 0
    local b2 = string.byte(data, offset + 2) or 0
    local b3 = string.byte(data, offset + 3) or 0
    local b4 = string.byte(data, offset + 4) or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Read float from string at offset (IEEE 754 little endian)
function Utils.read_float(data, offset)
    local b1 = string.byte(data, offset + 1) or 0
    local b2 = string.byte(data, offset + 2) or 0
    local b3 = string.byte(data, offset + 3) or 0
    local b4 = string.byte(data, offset + 4) or 0

    -- IEEE 754 single precision: sign(1) exponent(8) mantissa(23)
    local sign = (b4 >= 128) and -1 or 1
    local exponent = ((b4 % 128) * 2) + math.floor(b3 / 128)
    local mantissa = ((b3 % 128) * 65536) + (b2 * 256) + b1

    if exponent == 0 then
        if mantissa == 0 then
            return 0
        else
            -- Denormalized number
            return sign * mantissa * 2^(-149)
        end
    elseif exponent == 255 then
        if mantissa == 0 then
            return sign * math.huge
        else
            return 0/0  -- NaN
        end
    else
        -- Normalized number
        return sign * (1 + mantissa / 8388608) * 2^(exponent - 127)
    end
end

-- Read uint8 from string at offset
function Utils.read_uint8(data, offset)
    return string.byte(data, offset + 1) or 0
end

-- Create tile key for caching
function Utils.make_tile_key(mapId, tileX, tileY)
    return string.format("%04d_%02d_%02d", mapId, tileX, tileY)
end

-- Create color4 from RGBA table
function Utils.make_color(rgba)
    return color.new(rgba.r, rgba.g, rgba.b, rgba.a)
end

-- Dim a color by factor
function Utils.dim_color(rgba, factor)
    return {
        r = math.floor(rgba.r * factor),
        g = math.floor(rgba.g * factor),
        b = math.floor(rgba.b * factor),
        a = rgba.a
    }
end

return Utils
