local Input = {}

local constants = require("utils/constants")
local helpers = require("utils/helpers")

-- Mouse state
local mouse = {
    x = 0,
    y = 0,
    left_down = false,
    left_clicked = false,
    left_released = false,
    right_down = false,
    right_clicked = false,
    prev_left = false,
    prev_right = false
}

-- Keyboard state
local keyboard = {
    ctrl = false,
    shift = false,
    alt = false
}

-- Frame tracking to prevent multiple updates per frame
local last_update_time = 0

-- Update input state (call once per frame)
function Input.update()
    -- Prevent multiple updates in the same frame
    local current_time = core.time and core.time() or 0
    if current_time == last_update_time and last_update_time > 0 then
        return  -- Already updated this frame
    end
    last_update_time = current_time

    -- Get cursor position
    local cursor = core.get_cursor_position()
    if cursor then
        mouse.x = cursor.x or cursor[1] or 0
        mouse.y = cursor.y or cursor[2] or 0
    end

    -- Track previous state
    mouse.prev_left = mouse.left_down
    mouse.prev_right = mouse.right_down

    -- Update mouse buttons
    mouse.left_down = core.input.is_key_pressed(constants.VK.LBUTTON)
    mouse.right_down = core.input.is_key_pressed(constants.VK.RBUTTON)

    -- Detect click (transition from not pressed to pressed)
    mouse.left_clicked = mouse.left_down and not mouse.prev_left
    mouse.left_released = not mouse.left_down and mouse.prev_left
    mouse.right_clicked = mouse.right_down and not mouse.prev_right

    -- Update modifier keys
    keyboard.ctrl = core.input.is_key_pressed(constants.VK.CONTROL)
    keyboard.shift = core.input.is_key_pressed(constants.VK.SHIFT)
    keyboard.alt = core.input.is_key_pressed(constants.VK.ALT)

end

-- Get mouse position
function Input.get_mouse_pos()
    return mouse.x, mouse.y
end

-- Check if mouse is in rectangle
function Input.is_mouse_in_rect(x, y, w, h)
    return helpers.point_in_rect(mouse.x, mouse.y, x, y, w, h)
end

-- Mouse button states
function Input.is_left_down()
    return mouse.left_down
end

function Input.is_left_clicked()
    return mouse.left_clicked
end

function Input.is_left_released()
    return mouse.left_released
end

function Input.is_right_down()
    return mouse.right_down
end

function Input.is_right_clicked()
    return mouse.right_clicked
end

-- Modifier keys
function Input.is_ctrl_down()
    return keyboard.ctrl
end

function Input.is_shift_down()
    return keyboard.shift
end

function Input.is_alt_down()
    return keyboard.alt
end

-- Check if any key is pressed
function Input.is_key_pressed(key_code)
    return core.input.is_key_pressed(key_code)
end

-- Get first pressed key (for keybind capture)
function Input.get_pressed_key()
    -- Check common keys
    for code = 0x08, 0x7B do
        if code ~= constants.VK.LBUTTON and
           code ~= constants.VK.RBUTTON and
           code ~= constants.VK.MBUTTON then
            if core.input.is_key_pressed(code) then
                return code
            end
        end
    end
    return nil
end

-- Get raw mouse state table (for advanced use)
function Input.get_mouse_state()
    return mouse
end

-- Capture keyboard input (prevents game from receiving keys)
function Input.capture_keyboard()
    if core.graphics.capture_next_keyboard_input then
        core.graphics.capture_next_keyboard_input()
    end
end

-- Key to character mapping (handles shift)
local key_char_map = {
    -- Letters (lowercase)
    [0x41] = {"a", "A"}, [0x42] = {"b", "B"}, [0x43] = {"c", "C"}, [0x44] = {"d", "D"},
    [0x45] = {"e", "E"}, [0x46] = {"f", "F"}, [0x47] = {"g", "G"}, [0x48] = {"h", "H"},
    [0x49] = {"i", "I"}, [0x4A] = {"j", "J"}, [0x4B] = {"k", "K"}, [0x4C] = {"l", "L"},
    [0x4D] = {"m", "M"}, [0x4E] = {"n", "N"}, [0x4F] = {"o", "O"}, [0x50] = {"p", "P"},
    [0x51] = {"q", "Q"}, [0x52] = {"r", "R"}, [0x53] = {"s", "S"}, [0x54] = {"t", "T"},
    [0x55] = {"u", "U"}, [0x56] = {"v", "V"}, [0x57] = {"w", "W"}, [0x58] = {"x", "X"},
    [0x59] = {"y", "Y"}, [0x5A] = {"z", "Z"},
    -- Numbers
    [0x30] = {"0", ")"}, [0x31] = {"1", "!"}, [0x32] = {"2", "@"}, [0x33] = {"3", "#"},
    [0x34] = {"4", "$"}, [0x35] = {"5", "%"}, [0x36] = {"6", "^"}, [0x37] = {"7", "&"},
    [0x38] = {"8", "*"}, [0x39] = {"9", "("},
    -- Numpad
    [0x60] = {"0", "0"}, [0x61] = {"1", "1"}, [0x62] = {"2", "2"}, [0x63] = {"3", "3"},
    [0x64] = {"4", "4"}, [0x65] = {"5", "5"}, [0x66] = {"6", "6"}, [0x67] = {"7", "7"},
    [0x68] = {"8", "8"}, [0x69] = {"9", "9"},
    -- Special characters
    [0x20] = {" ", " "},           -- Space
    [0xBD] = {"-", "_"},           -- Minus
    [0xBB] = {"=", "+"},           -- Equals
    [0xDB] = {"[", "{"},           -- Left bracket
    [0xDD] = {"]", "}"},           -- Right bracket
    [0xDC] = {"\\", "|"},          -- Backslash
    [0xBA] = {";", ":"},           -- Semicolon
    [0xDE] = {"'", '"'},           -- Quote
    [0xBC] = {",", "<"},           -- Comma
    [0xBE] = {".", ">"},           -- Period
    [0xBF] = {"/", "?"},           -- Slash
    [0xC0] = {"`", "~"},           -- Backtick
    [0x6E] = {".", "."},           -- Numpad decimal
    [0x6F] = {"/", "/"},           -- Numpad divide
    [0x6A] = {"*", "*"},           -- Numpad multiply
    [0x6D] = {"-", "-"},           -- Numpad subtract
    [0x6B] = {"+", "+"},           -- Numpad add
}

-- Track previous key states for detecting new presses
local prev_key_states = {}

-- Get typed character (returns nil if no typeable key pressed)
function Input.get_typed_char()
    local shift = keyboard.shift

    for key_code, chars in pairs(key_char_map) do
        local is_down = core.input.is_key_pressed(key_code)
        local was_down = prev_key_states[key_code]

        -- Only return character on new press (not hold)
        if is_down and not was_down then
            prev_key_states[key_code] = true
            return shift and chars[2] or chars[1]
        elseif not is_down then
            prev_key_states[key_code] = false
        end
    end

    return nil
end

-- Check if a key was just pressed (not held)
function Input.is_key_just_pressed(key_code)
    local is_down = core.input.is_key_pressed(key_code)
    local was_down = prev_key_states[key_code]

    if is_down and not was_down then
        prev_key_states[key_code] = true
        return true
    elseif not is_down then
        prev_key_states[key_code] = false
    end

    return false
end

return Input
