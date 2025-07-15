-- ==================== INPUT HANDLING ====================

local constants = require("gui/utils/constants")
local helpers = require("gui/utils/helpers")
local vec2 = constants.vec2



-- Update mouse input state
local function update_mouse_state()
    -- Get current mouse position
    local cursor_pos = core.get_cursor_position()
    constants.mouse_state.position = vec2.new(cursor_pos.x, cursor_pos.y)
    
    -- Get current left mouse button state
    local current_left_button_state = core.input.is_key_pressed(0x01) -- VK_LBUTTON
    
    -- Detect click (button was released this frame)
    constants.mouse_state.left_button_clicked = constants.mouse_state.last_left_button_state and not current_left_button_state
    
    -- Update button states
    constants.mouse_state.was_down_last_frame = constants.mouse_state.left_button_down
    constants.mouse_state.left_button_down = current_left_button_state
    constants.mouse_state.last_left_button_state = current_left_button_state
    
    -- Keyboard scrolling alternatives (Page Up/Down and Arrow keys)
    local wheel_up_page = core.input.is_key_pressed(0x21)   -- VK_PRIOR (Page Up)
    local wheel_down_page = core.input.is_key_pressed(0x22) -- VK_NEXT (Page Down)
    
    -- Detect wheel events (pressed this frame)
    constants.mouse_state.wheel_up_pressed = wheel_up_page and not constants.mouse_state.last_wheel_up_state
    constants.mouse_state.wheel_down_pressed = wheel_down_page and not constants.mouse_state.last_wheel_down_state
    
    -- Update wheel states
    constants.mouse_state.last_wheel_up_state = wheel_up_page
    constants.mouse_state.last_wheel_down_state = wheel_down_page
    
    -- Update Ctrl key state
    constants.mouse_state.ctrl_pressed = core.input.is_key_pressed(0x11) -- VK_CONTROL
    
    -- Update GUI area tracking
    constants.mouse_state.is_over_gui = helpers.is_mouse_over_gui_area()
    

end



-- Process mouse input for a specific area (returns true if clicked and should process)
local function process_mouse_input(x, y, width, height)
    local mouse_pos = constants.mouse_state.position
    local is_hovered = helpers.is_point_in_rect(mouse_pos.x, mouse_pos.y, x, y, width, height)
    local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
    
    -- Only process clicks if mouse is over GUI area (prevents click-through)
    if is_clicked and not constants.mouse_state.is_over_gui then
        is_clicked = false
    end
    
    return is_hovered, is_clicked
end

-- Export functions
return {
    update_mouse_state = update_mouse_state,
    process_mouse_input = process_mouse_input
} 