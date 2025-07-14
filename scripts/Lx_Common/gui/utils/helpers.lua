-- ==================== HELPER UTILITIES ====================

local constants = require("gui/utils/constants")
local vec2 = constants.vec2

-- Helper function to check if a point is within a rectangle
local function is_point_in_rect(point_x, point_y, rect_x, rect_y, rect_width, rect_height)
    return point_x >= rect_x and point_x <= rect_x + rect_width and
           point_y >= rect_y and point_y <= rect_y + rect_height
end

-- Helper function to check if mouse is over any GUI area (navbar or open windows)
local function is_mouse_over_gui_area()
    local mouse_pos = constants.mouse_state.position
    
    -- Check if mouse is over navbar (full width, 28px height)
    local screen_size = core.graphics.get_screen_size()
    if is_point_in_rect(mouse_pos.x, mouse_pos.y, 0, 0, screen_size.x, 28) then
        return true
    end
    
    -- Check if mouse is over any open GUI window
    for name, gui in pairs(constants.registered_guis) do
        if gui.is_open and constants.gui_states[name] and constants.gui_states[name]:get_state() then
            if is_point_in_rect(mouse_pos.x, mouse_pos.y, gui.x_offset, gui.y_offset, gui.width, gui.height) then
                return true
            end
        end
    end
    
    return false
end

-- Check if input is currently blocked by GUI
local function is_input_blocked()
    -- Block input if mouse is over GUI area
    if is_mouse_over_gui_area() then
        return true
    end
    
    -- Block input if any text input is focused or keybind is listening
    for name, gui in pairs(constants.registered_guis) do
        if constants.gui_states[name] and constants.gui_states[name]:get_state() then
            if gui.text_inputs then
                for _, textinput in ipairs(gui.text_inputs) do
                    if textinput.is_focused then
                        return true
                    end
                end
            end
            
            if gui.keybinds then
                for _, keybind in ipairs(gui.keybinds) do
                    if keybind.is_listening then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

-- Export functions
return {
    is_point_in_rect = is_point_in_rect,
    is_mouse_over_gui_area = is_mouse_over_gui_area,
    is_input_blocked = is_input_blocked
} 