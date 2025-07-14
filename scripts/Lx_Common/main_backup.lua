-- ==================== IMPORTS ====================
---@type color
local color = require("common/color")
---@type vec2
local vec2 = require("common/geometry/vector_2")
---@type enums
local enums = require("common/enums")

-- ==================== PLUGIN SETTINGS ====================
local Settings = {
    debug_mode = false
}

-- ==================== DIRECT RENDERING GUI SYSTEM ====================
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
    is_over_gui = false  -- Track if mouse is over any GUI element
}

-- Font size constants
local FONT_SIZE = 12
local TAB_FONT_SIZE = 11

-- Menu class for external use
local Menu = {}
Menu.__index = Menu

function Menu:new(name, width, height)
    local gui = setmetatable({
        name = name,
        width = width or 400,  -- Default width
        height = height or 300, -- Default height
        x_offset = 0,  -- Position within the 800x800 space
        y_offset = 35, -- Start below navbar
        is_open = false,
        render_callback = nil,
        labels = {},  -- Store labels for this GUI
        buttons = {}  -- Store custom buttons for this GUI
    }, Menu)
    
    -- Calculate position for this GUI centered on the actual screen
    local screen_size = core.graphics.get_screen_size()
    -- Center horizontally on screen, position close to navbar
    gui.x_offset = (screen_size.x - gui.width) / 2
    gui.y_offset = 45  -- Position close to navbar (35px navbar + 10px gap)
    
    -- Register the GUI
    registered_guis[name] = gui
    gui_states[name] = core.menu.checkbox(true, "lx_gui_enabled_" .. name:lower():gsub("%s+", "_"))
    
    return gui
end

function Menu:set_render_callback(callback)
    self.render_callback = callback
end

function Menu:AddLabel(text, x, y, label_color)
    -- Default to white if no color provided
    local text_color = label_color or color.white(255)
    
    -- Add label to the labels table
    table.insert(self.labels, {
        text = text,
        x = x,
        y = y,
        color = text_color
    })
end

function Menu:AddButton(text, x, y, width, height, callback, bg_color, text_color, border_color)
    -- Default colors if not provided
    local button_bg = bg_color or color.new(60, 90, 140, 200)
    local button_text = text_color or color.white(255)
    local button_border = border_color or color.new(80, 110, 160, 255)
    
    -- Add button to the buttons table
    table.insert(self.buttons, {
        text = text,
        x = x,
        y = y,
        width = width,
        height = height,
        callback = callback,
        bg_color = button_bg,
        text_color = button_text,
        border_color = button_border
    })
end

function Menu:toggle()
    if not self.is_open then
        -- Close all other open GUIs when opening this one
        for name, gui in pairs(registered_guis) do
            if gui ~= self and gui.is_open then
                gui.is_open = false
            end
        end
    end
    self.is_open = not self.is_open
end

-- ==================== MOUSE INPUT FUNCTIONS ====================
local function is_point_in_rect(point, rect_min, rect_max)
    return point.x >= rect_min.x and point.x <= rect_max.x and 
           point.y >= rect_min.y and point.y <= rect_max.y
end

-- Check if mouse is over any GUI area (tabs or open windows)
local function is_mouse_over_gui_area()
    local mouse_pos = mouse_state.position
    
    -- Check if mouse is over navbar area
    if selection_bar_enabled then
        local button_width = 110
        local button_height = 30
        local spacing = 8
        
        -- Get enabled GUIs for navbar
        local enabled_guis = {}
        for name, gui in pairs(registered_guis) do
            if gui_states[name] and gui_states[name]:get_state() then
                table.insert(enabled_guis, {name = name, gui = gui})
            end
        end
        
        if #enabled_guis > 0 then
            -- Calculate navbar bounds based on actual screen width
            local screen_size = core.graphics.get_screen_size()
            local total_width = (#enabled_guis * button_width) + ((#enabled_guis - 1) * spacing)
            local start_x = (screen_size.x - total_width) / 2
            local navbar_min = vec2.new(start_x, 0)
            local navbar_max = vec2.new(start_x + total_width, button_height)
            
            if is_point_in_rect(mouse_pos, navbar_min, navbar_max) then
                return true
            end
        end
    end
    
    -- Check if mouse is over any open GUI window
    for name, gui in pairs(registered_guis) do
        if gui.is_open and gui_states[name] and gui_states[name]:get_state() then
            local gui_min = vec2.new(gui.x_offset, gui.y_offset)
            local gui_max = vec2.new(gui.x_offset + gui.width, gui.y_offset + gui.height)
            
            if is_point_in_rect(mouse_pos, gui_min, gui_max) then
                return true
            end
        end
    end
    
    return false
end

local function update_mouse_state()
    -- Get current mouse position and button state
    mouse_state.position = core.get_cursor_position()
    local current_left_state = core.input.is_key_pressed(0x01) -- VK_LBUTTON
    
    -- Check if mouse is over any GUI area
    mouse_state.is_over_gui = is_mouse_over_gui_area()
    
    -- Only detect clicks when mouse is over our GUI areas
    if mouse_state.is_over_gui then
        mouse_state.left_button_clicked = current_left_state and not mouse_state.last_left_button_state
    else
        mouse_state.left_button_clicked = false
    end
    
    mouse_state.left_button_down = current_left_state
    mouse_state.last_left_button_state = current_left_state
end

-- Public function for other systems to check if input should be blocked
local function is_input_blocked()
    return mouse_state.is_over_gui
end

-- ==================== DIRECT RENDERING FUNCTIONS ====================
local function render_gui_content(gui)
    if not gui.is_open then return end
    
    -- Check if this GUI is still enabled in the main menu
    if gui_states[gui.name] and not gui_states[gui.name]:get_state() then
        gui.is_open = false
        return
    end
    
    -- Only render if we have content
    if not gui.render_callback and #gui.labels == 0 and #gui.buttons == 0 then return end
    
    -- Render GUI background
    core.graphics.rect_2d_filled(
        vec2.new(gui.x_offset, gui.y_offset),
        gui.width, gui.height,
        color.new(25, 25, 35, 240),
        3
    )
    
    -- Render GUI border
    core.graphics.rect_2d(
        vec2.new(gui.x_offset, gui.y_offset),
        gui.width, gui.height,
        color.new(50, 50, 60, 255),
        2, 3
    )
    
    -- Render title bar
    local title_height = 25
    core.graphics.rect_2d_filled(
        vec2.new(gui.x_offset, gui.y_offset),
        gui.width, title_height,
        color.new(40, 40, 50, 240),
        3
    )
    
    -- Render title text
    core.graphics.text_2d(
        gui.name,
        vec2.new(gui.x_offset + 10, gui.y_offset + 5),
        FONT_SIZE,
        color.white(255),
        false,
        0
    )
    
    -- Content area starts below title
    local content_y_start = gui.y_offset + title_height + 10
    
    -- Render custom callback content
    if gui.render_callback then
        gui.render_callback()
    end
    
    -- Render labels
    for _, label in ipairs(gui.labels) do
        core.graphics.text_2d(
            label.text,
            vec2.new(gui.x_offset + label.x, content_y_start + label.y),
            FONT_SIZE,
            label.color,
            false,
            0
        )
    end
    
    -- Render buttons
    for _, button in ipairs(gui.buttons) do
        local btn_x = gui.x_offset + button.x
        local btn_y = content_y_start + button.y
        local btn_min = vec2.new(btn_x, btn_y)
        local btn_max = vec2.new(btn_x + button.width, btn_y + button.height)
        
        -- Check hover and click
        local is_hovered = is_point_in_rect(mouse_state.position, btn_min, btn_max)
        local is_clicked = is_hovered and mouse_state.left_button_clicked
        
        -- Color setup with safety
        local safe_bg = button.bg_color or color.new(60, 90, 140, 200)
        local safe_border = button.border_color or color.new(80, 110, 160, 255)
        local safe_text = button.text_color or color.white(255)
        
        -- Hover effect
        local current_bg = safe_bg
        local current_border = safe_border
        if is_hovered then
            local bg_r = math.min(255, (safe_bg.r or 60) + 30)
            local bg_g = math.min(255, (safe_bg.g or 90) + 30)
            local bg_b = math.min(255, (safe_bg.b or 140) + 30)
            local bg_a = safe_bg.a or 200
            
            local border_r = math.min(255, (safe_border.r or 80) + 40)
            local border_g = math.min(255, (safe_border.g or 110) + 40)
            local border_b = math.min(255, (safe_border.b or 160) + 40)
            local border_a = safe_border.a or 255
            
            current_bg = color.new(bg_r, bg_g, bg_b, bg_a)
            current_border = color.new(border_r, border_g, border_b, border_a)
        end
        
        -- Render button background
        core.graphics.rect_2d_filled(
            btn_min,
            button.width, button.height,
            current_bg,
            3
        )
        
        -- Render button border
        core.graphics.rect_2d(
            btn_min,
            button.width, button.height,
            current_border,
            2, 3
        )
        
        -- Render button text (centered)
        local text_width = core.graphics.get_text_width(button.text, FONT_SIZE, 0)
        local text_x = btn_x + (button.width - text_width) / 2
        local text_y = btn_y + (button.height - FONT_SIZE) / 2
        
        core.graphics.text_2d(
            button.text,
            vec2.new(text_x, text_y),
            FONT_SIZE,
            safe_text,
            false,
            0
        )
        
        -- Handle click
        if is_clicked and button.callback then
            button.callback()
        end
    end
end

-- ==================== NAVBAR RENDERING ====================
local function render_navbar()
    if not selection_bar_enabled then return end
    
    local button_width = 110
    local button_height = 30
    local spacing = 8
    
    -- Get enabled GUIs
    local enabled_guis = {}
    for name, gui in pairs(registered_guis) do
        if gui_states[name] and gui_states[name]:get_state() then
            table.insert(enabled_guis, {name = name, gui = gui})
        end
    end
    
    if #enabled_guis == 0 then return end
    
    -- Calculate centered starting position based on actual screen width
    local screen_size = core.graphics.get_screen_size()
    local total_width = (#enabled_guis * button_width) + ((#enabled_guis - 1) * spacing)
    local start_x = (screen_size.x - total_width) / 2
    
    -- Render tabs
    for i, gui_data in ipairs(enabled_guis) do
        local name = gui_data.name
        local gui = gui_data.gui
        
        local btn_x = start_x + ((i - 1) * (button_width + spacing))
        local btn_y = 0
        local btn_min = vec2.new(btn_x, btn_y)
        local btn_max = vec2.new(btn_x + button_width, btn_y + button_height)
        
        -- Check hover and click
        local is_hovered = is_point_in_rect(mouse_state.position, btn_min, btn_max)
        local is_clicked = is_hovered and mouse_state.left_button_clicked
        
        -- Tab colors based on state
        local tab_bg, tab_border, tab_text
        if gui.is_open then
            tab_bg = color.new(70, 110, 180, 240)
            tab_border = color.new(90, 130, 200, 255)
            tab_text = color.white(255)
        else
            tab_bg = color.new(40, 50, 70, 200)
            tab_border = color.new(60, 70, 90, 240)
            tab_text = color.new(180, 190, 210, 255)
        end
        
        -- Hover effect
        local glow_color = nil
        if is_hovered then
            local bg_r = math.min(255, (tab_bg.r or 70) + 25)
            local bg_g = math.min(255, (tab_bg.g or 110) + 25)
            local bg_b = math.min(255, (tab_bg.b or 180) + 25)
            local bg_a = tab_bg.a or 240
            
            tab_bg = color.new(bg_r, bg_g, bg_b, bg_a)
            
            -- Create bright glow color for hover
            glow_color = color.new(0, 255, 255, 255) -- Bright cyan glow
        end
        
        -- Draw upside-down tab shape
        local tab_angle = 8
        
        -- Main tab body
        core.graphics.rect_2d_filled(
            vec2.new(btn_x, btn_y),
            button_width, button_height - tab_angle,
            tab_bg,
            0
        )
        
        -- Bottom section between angled cuts
        core.graphics.rect_2d_filled(
            vec2.new(btn_x + tab_angle, btn_y + button_height - tab_angle),
            button_width - (2 * tab_angle), tab_angle,
            tab_bg,
            0
        )
        
        -- Left angled triangle
        core.graphics.triangle_2d_filled(
            vec2.new(btn_x, btn_y + button_height - tab_angle),
            vec2.new(btn_x + tab_angle, btn_y + button_height - tab_angle),
            vec2.new(btn_x + tab_angle, btn_y + button_height),
            tab_bg
        )
        
        -- Right angled triangle
        core.graphics.triangle_2d_filled(
            vec2.new(btn_x + button_width - tab_angle, btn_y + button_height - tab_angle),
            vec2.new(btn_x + button_width, btn_y + button_height - tab_angle),
            vec2.new(btn_x + button_width - tab_angle, btn_y + button_height),
            tab_bg
        )
        
        -- Tab border outline
        -- Top border (normal, no glow)
        core.graphics.line_2d(vec2.new(btn_x, btn_y), vec2.new(btn_x + button_width, btn_y), tab_border, 1)
        
        -- Left border
        core.graphics.line_2d(vec2.new(btn_x, btn_y), vec2.new(btn_x, btn_y + button_height - tab_angle), tab_border, 1)
        
        -- Right border  
        core.graphics.line_2d(vec2.new(btn_x + button_width, btn_y), vec2.new(btn_x + button_width, btn_y + button_height - tab_angle), tab_border, 1)
        
        -- Left angled cut
        core.graphics.line_2d(vec2.new(btn_x, btn_y + button_height - tab_angle), vec2.new(btn_x + tab_angle, btn_y + button_height), tab_border, 1)
        
        -- Right angled cut
        core.graphics.line_2d(vec2.new(btn_x + button_width - tab_angle, btn_y + button_height), vec2.new(btn_x + button_width, btn_y + button_height - tab_angle), tab_border, 1)
        
        -- Bottom border
        core.graphics.line_2d(vec2.new(btn_x + tab_angle, btn_y + button_height), vec2.new(btn_x + button_width - tab_angle, btn_y + button_height), tab_border, 1)
        
        -- Add glow effect on sides and bottom when hovered
        if glow_color then
            -- Left border glow (thicker, brighter)
            core.graphics.line_2d(vec2.new(btn_x - 1, btn_y + 1), vec2.new(btn_x - 1, btn_y + button_height - tab_angle), glow_color, 2)
            
            -- Right border glow (thicker, brighter)
            core.graphics.line_2d(vec2.new(btn_x + button_width + 1, btn_y + 1), vec2.new(btn_x + button_width + 1, btn_y + button_height - tab_angle), glow_color, 2)
            
            -- Left angled cut glow
            core.graphics.line_2d(vec2.new(btn_x - 1, btn_y + button_height - tab_angle), vec2.new(btn_x + tab_angle, btn_y + button_height + 1), glow_color, 2)
            
            -- Right angled cut glow
            core.graphics.line_2d(vec2.new(btn_x + button_width - tab_angle, btn_y + button_height + 1), vec2.new(btn_x + button_width + 1, btn_y + button_height - tab_angle), glow_color, 2)
            
            -- Bottom border glow (thicker, brighter)
            core.graphics.line_2d(vec2.new(btn_x + tab_angle, btn_y + button_height + 1), vec2.new(btn_x + button_width - tab_angle, btn_y + button_height + 1), glow_color, 2)
        end
        
        -- Tab text (centered)
        local text_width = core.graphics.get_text_width(name, TAB_FONT_SIZE, 0)
        local text_x = btn_x + (button_width - text_width) / 2
        local text_y = btn_y + (button_height - TAB_FONT_SIZE) / 2
        
        core.graphics.text_2d(
            name,
            vec2.new(text_x, text_y),
            TAB_FONT_SIZE,
            tab_text,
            false,
            0
        )
        
        -- Handle click
        if is_clicked then
            gui:toggle()
        end
    end
end

-- ==================== INPUT BLOCKING WINDOW ====================
local function render_input_blocking_window()
    -- Check if any GUI window is currently open
    local open_gui = nil
    
    for name, gui in pairs(registered_guis) do
        if gui.is_open and gui_states[name] and gui_states[name]:get_state() then
            open_gui = gui
            break
        end
    end
    
    -- Only show blocking window if a GUI window is actually open (not just tabs)
    if open_gui then
        -- Reset any previous size constraints and set new ones
        blocking_window:stop_forcing_size()
        blocking_window:force_next_begin_window_pos(vec2.new(open_gui.x_offset, open_gui.y_offset))
        blocking_window:set_next_window_min_size(vec2.new(open_gui.width, open_gui.height))
        blocking_window:force_window_size(vec2.new(open_gui.width, open_gui.height))
        
        blocking_window:set_background_multicolored(
            color.new(0, 0, 0, 0),
            color.new(0, 0, 0, 0),
            color.new(0, 0, 0, 0),
            color.new(0, 0, 0, 0)
        )
        
        blocking_window:begin(
            0, -- resizable false (0 = not resizable)
            false, -- no close button  
            color.new(0, 0, 0, 0), -- transparent bg_color
            color.new(0, 0, 0, 0), -- transparent border_color
            0, -- cross_style
            enums.window_enums.window_behaviour_flags.NO_MOVE, -- flag_1: prevent window movement
            0, -- flag_2: unused
            0, -- flag_3: unused
            function()
                -- Add an artificial item to block any interactions within the window
                blocking_window:add_artificial_item_bounds(vec2.new(0, 0), vec2.new(open_gui.width, open_gui.height))
            end
        )
    end
end

-- ==================== MAIN RENDER FUNCTION ====================
local function render_direct_gui()
    -- Render input blocking window first (behind our GUI)
    render_input_blocking_window()
    
    -- Update mouse input state
    update_mouse_state()
    
    -- Render navbar tabs
    render_navbar()
    
    -- Render all active GUIs
    for name, gui in pairs(registered_guis) do
        if gui_states[name] and gui_states[name]:get_state() then
            render_gui_content(gui)
        end
    end
end

-- ==================== MAIN MENU INTEGRATION ====================
local lx_guis_tree_node = core.menu.tree_node()
local lx_guis_checkbox = core.menu.checkbox(true, "lx_selection_bar_enabled")

-- ==================== UPDATE CALLBACK ====================
local function on_update()
    -- Update selection bar enabled state
    if lx_guis_checkbox then
        selection_bar_enabled = lx_guis_checkbox:get_state()
    end
end

-- ==================== RENDER CALLBACK ====================
local function on_render()
    render_direct_gui()
end

-- ==================== MENU CALLBACK ====================
local function on_render_menu()
    lx_guis_tree_node:render("LX GUIs", function()
        if lx_guis_checkbox then
            lx_guis_checkbox:render("Selection Bar Enabled", "Show/hide the top selection bar for LX GUIs")
        end
        
        -- Render individual GUI enable/disable checkboxes
        for name, checkbox in pairs(gui_states) do
            if checkbox then
                checkbox:render("Enable " .. name, "Show " .. name .. " in selection bar")
            end
        end
    end)
end

-- ==================== EXPORT FUNCTIONS ====================
-- Global export for other plugins to use
_G.LxCommon = {
    Menu = Menu,
    Gui = {
        register = function(name, width, height)
            return Menu:new(name, width, height)
        end
    },
    -- Legacy support
    registerGui = function(name, width, height)
        return Menu:new(name, width, height)
    end,
    -- Input blocking for other systems
    isInputBlocked = function()
        return is_input_blocked()
    end
}

-- ==================== PLUGIN REGISTRATION ====================

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)

core.log("Lx Common GUI system loaded successfully")