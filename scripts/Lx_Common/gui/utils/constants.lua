-- ==================== CONSTANTS AND SETTINGS ====================

-- External imports
---@type color
local color = require("common/color")
---@type vec2
local vec2 = require("common/geometry/vector_2")
---@type enums
local enums = require("common/enums")

-- Plugin settings
local Settings = {
    debug_mode = false
}

-- Font size constants
local FONT_SIZE = 12
local TAB_FONT_SIZE = 14

-- Global state variables
local registered_guis = {}
local gui_states = {}
local selection_bar_enabled = true

-- Input blocking invisible window  
local blocking_window = core.menu.window("lx_input_blocker")

-- Mouse state tracking
local mouse_state = {
    position = vec2.new(0, 0),
    left_button_down = false,
    left_button_clicked = false,
    last_left_button_state = false,
    was_down_last_frame = false,
    is_over_gui = false,  -- Track if mouse is over any GUI element
    
    -- Mouse wheel state tracking
    wheel_up_pressed = false,
    wheel_down_pressed = false,
    last_wheel_up_state = false,
    last_wheel_down_state = false,
    
    -- Modifier keys
    ctrl_pressed = false
}

-- Export everything
return {
    color = color,
    vec2 = vec2,
    enums = enums,
    Settings = Settings,
    FONT_SIZE = FONT_SIZE,
    TAB_FONT_SIZE = TAB_FONT_SIZE,
    registered_guis = registered_guis,
    gui_states = gui_states,
    selection_bar_enabled = selection_bar_enabled,
    blocking_window = blocking_window,
    mouse_state = mouse_state,
    key_debug_active = false,  -- Key debug system state
    debug_last_keys = {}       -- Tracks last key states for debug
} 