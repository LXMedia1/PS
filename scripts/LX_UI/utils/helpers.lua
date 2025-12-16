local helpers = {}

local constants = require("utils/constants")

-- ID counter for generating unique IDs
local id_counter = 0

function helpers.generate_id(prefix)
    id_counter = id_counter + 1
    return (prefix or "component") .. "_" .. id_counter
end

function helpers.reset_id_counter()
    id_counter = 0
end

-- Point in rectangle check
function helpers.point_in_rect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

-- Clamp value between min and max
function helpers.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Lerp (linear interpolation)
function helpers.lerp(a, b, t)
    return a + (b - a) * t
end

-- Round number to decimal places
function helpers.round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Map value from one range to another
function helpers.map_range(value, in_min, in_max, out_min, out_max)
    return (value - in_min) * (out_max - out_min) / (in_max - in_min) + out_min
end

-- Deep copy table
function helpers.deep_copy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[helpers.deep_copy(k)] = helpers.deep_copy(v)
        end
        setmetatable(copy, helpers.deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Merge tables (shallow)
function helpers.merge_tables(t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
        result[k] = v
    end
    for k, v in pairs(t2 or {}) do
        result[k] = v
    end
    return result
end

-- Color helpers
function helpers.color_with_alpha(col, alpha)
    return constants.color.new(col:r(), col:g(), col:b(), alpha)
end

function helpers.lighten_color(col, amount)
    local r = helpers.clamp(col:r() + amount, 0, 255)
    local g = helpers.clamp(col:g() + amount, 0, 255)
    local b = helpers.clamp(col:b() + amount, 0, 255)
    return constants.color.new(r, g, b, col:a())
end

function helpers.darken_color(col, amount)
    return helpers.lighten_color(col, -amount)
end

-- String helpers
function helpers.truncate_string(str, max_length, suffix)
    suffix = suffix or "..."
    if #str <= max_length then
        return str
    end
    return string.sub(str, 1, max_length - #suffix) .. suffix
end

-- Key name lookup
local key_names = {
    [0x01] = "LMB", [0x02] = "RMB", [0x04] = "MMB",
    [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter",
    [0x10] = "Shift", [0x11] = "Ctrl", [0x12] = "Alt",
    [0x1B] = "Escape", [0x20] = "Space",
    [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
    [0x2E] = "Delete",
    [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
    [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
    [0x41] = "A", [0x42] = "B", [0x43] = "C", [0x44] = "D", [0x45] = "E",
    [0x46] = "F", [0x47] = "G", [0x48] = "H", [0x49] = "I", [0x4A] = "J",
    [0x4B] = "K", [0x4C] = "L", [0x4D] = "M", [0x4E] = "N", [0x4F] = "O",
    [0x50] = "P", [0x51] = "Q", [0x52] = "R", [0x53] = "S", [0x54] = "T",
    [0x55] = "U", [0x56] = "V", [0x57] = "W", [0x58] = "X", [0x59] = "Y",
    [0x5A] = "Z",
    [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4",
    [0x74] = "F5", [0x75] = "F6", [0x76] = "F7", [0x77] = "F8",
    [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12"
}

function helpers.get_key_name(key_code)
    return key_names[key_code] or string.format("Key_%02X", key_code)
end

return helpers
