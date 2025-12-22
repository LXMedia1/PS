-- LX_Nav2 Binary Reading Helpers
-- Little-endian binary parsing for mmtile files

local Binary = {}

-- Read unsigned 8-bit integer
function Binary.read_u8(data, pos)
    if not data or not pos or pos > #data then
        return 0
    end
    return string.byte(data, pos) or 0
end

-- Read unsigned 16-bit integer (little-endian)
function Binary.read_u16(data, pos)
    if not data or not pos or (pos + 1) > #data then
        return 0
    end
    local b1 = string.byte(data, pos) or 0
    local b2 = string.byte(data, pos + 1) or 0
    return b1 + b2 * 256
end

-- Read unsigned 32-bit integer (little-endian)
function Binary.read_u32(data, pos)
    if not data or not pos or (pos + 3) > #data then
        return 0
    end
    local b1 = string.byte(data, pos) or 0
    local b2 = string.byte(data, pos + 1) or 0
    local b3 = string.byte(data, pos + 2) or 0
    local b4 = string.byte(data, pos + 3) or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Read signed 32-bit integer (little-endian)
function Binary.read_i32(data, pos)
    local u = Binary.read_u32(data, pos)
    if u >= 0x80000000 then
        return u - 0x100000000
    end
    return u
end

-- Read IEEE 754 single-precision float (little-endian)
function Binary.read_f32(data, pos)
    local bits = Binary.read_u32(data, pos)
    if bits == 0 then
        return 0.0
    end

    -- Extract sign
    local sign = 1
    if bits >= 2^31 then
        sign = -1
        bits = bits - 2^31
    end

    -- Extract exponent (8 bits)
    local exp = math.floor(bits / 2^23)
    bits = bits - exp * 2^23

    -- Extract mantissa (23 bits)
    local mant = bits / 2^23

    -- Handle special cases
    if exp == 0 then
        -- Denormalized number or zero
        if mant == 0 then
            return sign * 0
        end
        return sign * mant * 2^(-126)
    elseif exp == 0xFF then
        -- Infinity or NaN
        if mant == 0 then
            return sign * math.huge
        end
        return 0/0  -- NaN
    end

    -- Normalized number
    return sign * (1 + mant) * 2^(exp - 127)
end

-- Read raw bytes as string
function Binary.read_bytes(data, pos, count)
    if not data or not pos or (pos + count - 1) > #data then
        return ""
    end
    return string.sub(data, pos, pos + count - 1)
end

-- Utility: Format bytes as hex string (for debugging)
function Binary.to_hex(data, pos, count)
    local bytes = Binary.read_bytes(data, pos, count)
    local hex = {}
    for i = 1, #bytes do
        hex[i] = string.format("%02X", string.byte(bytes, i))
    end
    return table.concat(hex, " ")
end

return Binary