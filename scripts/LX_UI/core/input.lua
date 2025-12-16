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

-- Update input state (call once per frame)
function Input.update()
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

return Input
