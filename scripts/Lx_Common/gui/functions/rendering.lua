-- ==================== RENDERING FUNCTIONS ====================

local constants = require("gui/utils/constants")
local helpers = require("gui/utils/helpers")
local input = require("gui/functions/input")

local color = constants.color
local vec2 = constants.vec2
local enums = constants.enums

-- ==================== KEY NAME HELPER ====================
local function get_key_name(key_code)
    if key_code == 0 then return "None" end
    
    -- Use core.graphics function if available
    if core.graphics.translate_vkey_to_string then
        local name = core.graphics.translate_vkey_to_string(key_code)
        if name and name ~= "" then
            return name
        end
    end
    
    -- Fallback key name mapping
    local key_names = {
        [8] = "Backspace",
        [9] = "Tab",
        [13] = "Enter",
        [16] = "Shift",
        [17] = "Ctrl",
        [18] = "Alt",
        [19] = "Pause",
        [20] = "Caps Lock",
        [27] = "Escape",
        [32] = "Space",
        [33] = "Page Up",
        [34] = "Page Down",
        [35] = "End",
        [36] = "Home",
        [37] = "Left Arrow",
        [38] = "Up Arrow",
        [39] = "Right Arrow",
        [40] = "Down Arrow",
        [45] = "Insert",
        [46] = "Delete",
        [48] = "0", [49] = "1", [50] = "2", [51] = "3", [52] = "4",
        [53] = "5", [54] = "6", [55] = "7", [56] = "8", [57] = "9",
        [65] = "A", [66] = "B", [67] = "C", [68] = "D", [69] = "E",
        [70] = "F", [71] = "G", [72] = "H", [73] = "I", [74] = "J",
        [75] = "K", [76] = "L", [77] = "M", [78] = "N", [79] = "O",
        [80] = "P", [81] = "Q", [82] = "R", [83] = "S", [84] = "T",
        [85] = "U", [86] = "V", [87] = "W", [88] = "X", [89] = "Y",
        [90] = "Z",
        [96] = "Numpad 0", [97] = "Numpad 1", [98] = "Numpad 2", [99] = "Numpad 3",
        [100] = "Numpad 4", [101] = "Numpad 5", [102] = "Numpad 6", [103] = "Numpad 7",
        [104] = "Numpad 8", [105] = "Numpad 9",
        [106] = "Numpad *", [107] = "Numpad +", [109] = "Numpad -", 
        [110] = "Numpad .", [111] = "Numpad /",
        [112] = "F1", [113] = "F2", [114] = "F3", [115] = "F4",
        [116] = "F5", [117] = "F6", [118] = "F7", [119] = "F8",
        [120] = "F9", [121] = "F10", [122] = "F11", [123] = "F12",
        [160] = "Left Shift", [161] = "Right Shift",
        [162] = "Left Ctrl", [163] = "Right Ctrl",
        [164] = "Left Alt", [165] = "Right Alt",
        [186] = ";", [187] = "=", [188] = ",", [189] = "-", [190] = ".", [191] = "/",
        [192] = "`", [219] = "[", [220] = "\\", [221] = "]", [222] = "'"
    }
    
    return (key_names[key_code] or "Key ") .. tostring(key_code)
end

-- ==================== GUI CONTENT RENDERING ====================
local function render_gui_content(gui)
    if not gui.is_open then 
        return 
    end
    
    -- Check if this GUI is still enabled in the main menu
    if constants.gui_states[gui.name] and not constants.gui_states[gui.name]:get_state() then
        gui.is_open = false
        return
    end
    
    -- Only render if we have content
    local has_images = gui.images and #gui.images > 0
    local has_checkboxes = gui.checkboxes and #gui.checkboxes > 0
    local has_sliders_int = gui.sliders_int and #gui.sliders_int > 0
    local has_sliders_float = gui.sliders_float and #gui.sliders_float > 0
    local has_comboboxes = gui.comboboxes and #gui.comboboxes > 0
    local has_keybinds = gui.keybinds and #gui.keybinds > 0
    local has_colorpickers = gui.colorpickers and #gui.colorpickers > 0
    local has_text_inputs = gui.text_inputs and #gui.text_inputs > 0
    local has_headers = gui.headers and #gui.headers > 0
    local has_tree_nodes = gui.tree_nodes and #gui.tree_nodes > 0
    local has_key_checkboxes = gui.key_checkboxes and #gui.key_checkboxes > 0
    
    if not gui.render_callback and #gui.labels == 0 and #gui.buttons == 0 and not has_images 
        and not has_checkboxes and not has_sliders_int and not has_sliders_float 
        and not has_comboboxes and not has_keybinds and not has_colorpickers 
        and not has_text_inputs and not has_headers and not has_tree_nodes
        and not has_key_checkboxes then 
        return 
    end
    
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
        constants.FONT_SIZE,
        color.white(255),
        false
    )
    
    -- Content area starts below title
    local content_y_start = gui.y_offset + title_height + 10
    
    -- Render custom callback content
    if gui.render_callback then
        gui.render_callback()
    end
    
    -- Render enhanced labels with awesome features
    for _, label in ipairs(gui.labels) do
        -- Update animation time with safety check
        if not label.animation_time then
            label.animation_time = 0
        end
        label.animation_time = label.animation_time + (1.0 / 60.0) -- Assume 60 FPS
        
        -- Update dynamic content
        if label.dynamic and label.update_callback then
            local new_text = label.update_callback()
            if new_text then
                label.text = new_text
            end
        end
        
        -- Calculate position
        local label_x = gui.x_offset + label.x
        local label_y = content_y_start + label.y
        
        -- Handle alignment with safety checks
        local safe_text = label.text or ""
        local safe_font_size = label.font_size or constants.FONT_SIZE
        local text_width = core.graphics.get_text_width(safe_text, safe_font_size, 0)
        if label.align == "center" then
            label_x = label_x - (text_width / 2)
        elseif label.align == "right" then
            label_x = label_x - text_width
        end
        
        -- Check for hover/click if interactive
        local is_hovered = false
        local is_clicked = false
        if label.clickable then
            -- Use a slightly larger click area for better usability
            local click_padding = 2
            is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                  label_x - click_padding, label_y - click_padding, 
                                                  text_width + (click_padding * 2), safe_font_size + (click_padding * 2))
            
            -- Use button press instead of release for more responsive feel
            is_clicked = is_hovered and constants.mouse_state.left_button_down and not constants.mouse_state.was_down_last_frame
            label.is_hovered = is_hovered
            
            if is_clicked and label.click_callback then
                core.log("Label clicked: " .. (safe_text or "unknown"))
                label.click_callback()
            end
        end
        
        -- Calculate animated color with safety checks
        local current_color = label.color or color.white(255)
        
        -- Apply hover color and effects
        if is_hovered and label.hover_color then
            current_color = label.hover_color or current_color
            -- Add a subtle glow effect when hovered
            if not label.animation or label.animation == "none" then
                local brightness = 1.3  -- Static brightness increase instead of animated glow
                local safe_r = (current_color and current_color.r) or 255
                local safe_g = (current_color and current_color.g) or 255  
                local safe_b = (current_color and current_color.b) or 255
                local safe_a = (current_color and current_color.a) or 255
                current_color = color.new(
                    math.min(255, math.floor(safe_r * brightness)),
                    math.min(255, math.floor(safe_g * brightness)),
                    math.min(255, math.floor(safe_b * brightness)),
                    safe_a
                )
            end
        end
        
        -- Apply animation effects with proper color safety
        if label.animation == "pulse" then
            local pulse = (math.sin(label.animation_time * label.animation_speed * 3.14159) + 1) / 2
            local intensity = 0.3 + (pulse * 0.7)
            local safe_r = (current_color and current_color.r) or 255
            local safe_g = (current_color and current_color.g) or 255
            local safe_b = (current_color and current_color.b) or 255
            local safe_a = (current_color and current_color.a) or 255
            current_color = color.new(
                math.floor(safe_r * intensity),
                math.floor(safe_g * intensity), 
                math.floor(safe_b * intensity),
                safe_a
            )
        elseif label.animation == "fade" then
            local fade = (math.sin(label.animation_time * label.animation_speed * 3.14159) + 1) / 2
            local safe_r = (current_color and current_color.r) or 255
            local safe_g = (current_color and current_color.g) or 255
            local safe_b = (current_color and current_color.b) or 255
            current_color = color.new(safe_r, safe_g, safe_b, 
                                     math.floor(255 * (0.3 + fade * 0.7)))
        elseif label.animation == "rainbow" then
            local hue = (label.animation_time * label.animation_speed * 60) % 360
            -- Simple HSV to RGB conversion for rainbow effect
            local c = 1
            local x = c * (1 - math.abs(((hue / 60) % 2) - 1))
            local m = 0
            local r, g, b
            if hue < 60 then r, g, b = c, x, 0
            elseif hue < 120 then r, g, b = x, c, 0
            elseif hue < 180 then r, g, b = 0, c, x
            elseif hue < 240 then r, g, b = 0, x, c
            elseif hue < 300 then r, g, b = x, 0, c
            else r, g, b = c, 0, x end
            local safe_a = (current_color and current_color.a) or 255
            current_color = color.new(math.floor((r + m) * 255), math.floor((g + m) * 255), 
                                     math.floor((b + m) * 255), safe_a)
        elseif label.animation == "glow" then
            local glow = (math.sin(label.animation_time * label.animation_speed * 3.14159) + 1) / 2
            local brightness = 1.0 + (glow * 0.8)
            local safe_r = (current_color and current_color.r) or 255
            local safe_g = (current_color and current_color.g) or 255
            local safe_b = (current_color and current_color.b) or 255
            local safe_a = (current_color and current_color.a) or 255
            current_color = color.new(
                math.min(255, math.floor(safe_r * brightness)),
                math.min(255, math.floor(safe_g * brightness)),
                math.min(255, math.floor(safe_b * brightness)),
                safe_a
            )
        end
        
        -- Render background if enabled
        if label.background then
            local safe_padding = label.bg_padding or 5
            local bg_x = label_x - safe_padding
            local bg_y = label_y - safe_padding
            local bg_width = text_width + (safe_padding * 2)
            local bg_height = safe_font_size + (safe_padding * 2)
            
            core.graphics.rect_2d_filled(
                vec2.new(bg_x, bg_y),
                bg_width, bg_height,
                label.bg_color or color.new(20, 20, 30, 180),
                3
            )
        end
        
        -- Render shadow if enabled
        if label.shadow then
            local shadow_offset = label.shadow_offset or {x = 2, y = 2}
            local safe_shadow_color = label.shadow_color or color.new(0, 0, 0, 100)
            core.graphics.text_2d(
                safe_text,
                vec2.new(label_x + shadow_offset.x, label_y + shadow_offset.y),
                safe_font_size,
                safe_shadow_color,
                false
            )
        end
        
        -- Render text outline if enabled
        if label.outline then
            local outline_offsets = {
                {-1, -1}, {0, -1}, {1, -1},
                {-1,  0},          {1,  0},
                {-1,  1}, {0,  1}, {1,  1}
            }
            
            -- Safe outline color with fallback
            local safe_outline_color = label.outline_color or color.new(0, 0, 0, 255)
            
            for _, offset in ipairs(outline_offsets) do
                core.graphics.text_2d(
                    safe_text,
                    vec2.new(label_x + offset[1], label_y + offset[2]),
                    safe_font_size,
                    safe_outline_color,
                    false
                )
            end
        end
        
        -- Render main text
        core.graphics.text_2d(
            safe_text,
            vec2.new(label_x, label_y),
            safe_font_size,
            current_color,
            false
        )
    end
    
    -- Render buttons with working mouse logic
    for _, button in ipairs(gui.buttons) do
        local btn_x = gui.x_offset + button.x
        local btn_y = content_y_start + button.y
        local btn_min = vec2.new(btn_x, btn_y)
        local btn_max = vec2.new(btn_x + button.width, btn_y + button.height)
        
        -- Check hover and click using helper function
        local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, btn_x, btn_y, button.width, button.height)
        local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
        
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
        local text_width = core.graphics.get_text_width(button.text, constants.FONT_SIZE, 0)
        local text_x = btn_x + (button.width - text_width) / 2
        local text_y = btn_y + (button.height - constants.FONT_SIZE) / 2
        
        core.graphics.text_2d(
            button.text,
            vec2.new(text_x, text_y),
            constants.FONT_SIZE,
            safe_text,
            false
        )
        
        -- Handle click
        if is_clicked and button.callback then
            button.callback()
        end
    end
    
    -- Render images (if supported)
    if gui.images and #gui.images > 0 and core.graphics.draw_image then
        for _, image in ipairs(gui.images) do
            if not image.image_object then
                goto continue_image
            end
            
            local img_x = gui.x_offset + image.x
            local img_y = content_y_start + image.y
            
            -- Handle hover and click if interactive
            local is_hovered = false
            local is_clicked = false
            if image.clickable and image.width and image.height then
                is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                      img_x, img_y, image.width, image.height)
                is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                image.is_hovered = is_hovered
                
                if is_clicked and image.click_callback then
                    core.log("Image clicked at: " .. img_x .. ", " .. img_y)
                    image.click_callback()
                end
            end
            
            -- Calculate scale for hover effect
            local scale = 1.0
            if is_hovered and image.hover_scale then
                scale = image.hover_scale
            end
            
            -- Adjust position if scaled (center the scaling)
            local scaled_x = img_x
            local scaled_y = img_y
            if scale ~= 1.0 and image.width and image.height then
                local width_diff = (image.width * scale - image.width) / 2
                local height_diff = (image.height * scale - image.height) / 2
                scaled_x = scaled_x - width_diff
                scaled_y = scaled_y - height_diff
            end
            
            -- Render the image (base64 data will be handled by core.graphics.draw_image)
            core.graphics.draw_image(
                image.image_object,
                vec2.new(scaled_x, scaled_y)
            )
            
            ::continue_image::
        end
    end
    
    -- Render all GUI components with interactive functionality
    if gui.menu_components and next(gui.menu_components) then
        -- Use content area start for base positioning
        local base_y = content_y_start
        
        -- Render all checkboxes with click handling
        for _, checkbox in ipairs(gui.checkboxes) do
            if checkbox.menu_component and checkbox.menu_component.get_state then
                local cb_x = gui.x_offset + checkbox.x
                local cb_y = base_y + checkbox.y
                
                -- Initialize internal state on first run if not set
                if checkbox.internal_state == nil then
                    checkbox.internal_state = checkbox.menu_component:get_state()
                end
                
                -- Handle click interaction
                local checkbox_size = 16
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            cb_x, cb_y, checkbox_size + 100, checkbox_size) -- Include text area
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                
                if is_clicked then
                    -- Toggle the checkbox state
                    checkbox.internal_state = not checkbox.internal_state
                    if checkbox.callback then
                        checkbox.callback(checkbox.internal_state)
                    end
                end
                
                -- Always use internal state for display and logic
                local display_checked = checkbox.internal_state
                local checkbox_color = display_checked and color.green(255) or color.gray(200)
                
                -- Hover effect
                if is_hovered then
                    checkbox_color = display_checked and color.new(100, 255, 100, 255) or color.new(150, 150, 150, 255)
                end
                
                -- Checkbox background
                core.graphics.rect_2d_filled(
                    vec2.new(cb_x, cb_y),
                    checkbox_size, checkbox_size,
                    color.new(40, 40, 40, 255),
                    2
                )
                
                -- Checkbox border
                core.graphics.rect_2d(
                    vec2.new(cb_x, cb_y),
                    checkbox_size, checkbox_size,
                    checkbox_color,
                    1, 2
                )
                
                -- Checkmark if checked
                if display_checked then
                    core.graphics.line_2d(
                        vec2.new(cb_x + 3, cb_y + 8),
                        vec2.new(cb_x + 7, cb_y + 12),
                        color.white(255), 2
                    )
                    core.graphics.line_2d(
                        vec2.new(cb_x + 7, cb_y + 12),
                        vec2.new(cb_x + 13, cb_y + 4),
                        color.white(255), 2
                    )
                end
                
                -- Checkbox text
                local text_color = is_hovered and color.new(255, 255, 100, 255) or checkbox.text_color
                core.graphics.text_2d(
                    checkbox.text,
                    vec2.new(cb_x + checkbox_size + 5, cb_y),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
            end
        end
        
        -- Render all integer sliders with click handling
        for _, slider in ipairs(gui.sliders_int or {}) do
            if slider.menu_component then
                local sl_x = gui.x_offset + slider.x
                local sl_y = base_y + slider.y
                
                -- Initialize internal value if not set
                if slider.internal_value == nil then
                    slider.internal_value = slider.default_value
                end
                
                -- Handle drag interaction
                local slider_width = slider.width
                local slider_height = 20 -- Larger click area
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            sl_x, sl_y, slider_width, slider_height)
                local is_mouse_down = is_hovered and constants.mouse_state.left_button_down
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                local is_pressed = is_hovered and constants.mouse_state.left_button_down and not constants.mouse_state.was_down_last_frame
                
                -- Initialize drag state if not exists
                if slider.is_dragging == nil then
                    slider.is_dragging = false
                end
                
                -- Start dragging on press (not release)
                if is_pressed then
                    slider.is_dragging = true
                end
                
                -- Stop dragging when mouse is released (only if currently dragging)
                if slider.is_dragging and not constants.mouse_state.left_button_down then
                    slider.is_dragging = false
                end
                
                -- Update value while dragging
                if slider.is_dragging and constants.mouse_state.left_button_down then
                    local click_x = constants.mouse_state.position.x - sl_x
                    local ratio = math.max(0, math.min(1, click_x / slider_width))
                    local new_value = math.floor(slider.min_value + (ratio * (slider.max_value - slider.min_value)))
                    
                    -- Only update if value changed
                    if new_value ~= slider.internal_value then
                        slider.internal_value = new_value
                        if slider.callback then
                            slider.callback(new_value)
                        end
                    end
                end
                
                -- Use internal value
                local current_value = slider.internal_value
                
                -- Render slider visual
                local display_height = 6
                local handle_size = 12
                
                -- Calculate handle position
                local value_ratio = (current_value - slider.min_value) / (slider.max_value - slider.min_value)
                local handle_x = sl_x + (value_ratio * (slider_width - handle_size))
                
                -- Slider track
                local track_color = is_hovered and color.new(80, 80, 80, 255) or color.new(60, 60, 60, 255)
                core.graphics.rect_2d_filled(
                    vec2.new(sl_x, sl_y + 8),
                    slider_width, display_height,
                    track_color,
                    2
                )
                
                -- Slider handle with drag state feedback
                local handle_color = color.new(100, 150, 200, 255) -- Default
                if slider.is_dragging then
                    handle_color = color.new(150, 200, 255, 255) -- Bright blue when dragging
                elseif is_hovered then
                    handle_color = color.new(120, 170, 220, 255) -- Hover color
                end
                
                core.graphics.rect_2d_filled(
                    vec2.new(handle_x, sl_y + 4),
                    handle_size, handle_size + 4,
                    handle_color,
                    2
                )
                
                -- Slider text and value
                local text_color = is_hovered and color.new(255, 255, 100, 255) or slider.text_color
                core.graphics.text_2d(
                    slider.text .. ": " .. tostring(current_value),
                    vec2.new(sl_x, sl_y - 15),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
            end
        end
        
        -- Render all float sliders with click handling
        for _, slider in ipairs(gui.sliders_float or {}) do
            if slider.menu_component then
                local sl_x = gui.x_offset + slider.x
                local sl_y = base_y + slider.y
                
                -- Initialize internal value if not set
                if slider.internal_value == nil then
                    slider.internal_value = slider.default_value
                end
                
                -- Handle drag interaction
                local slider_width = slider.width
                local slider_height = 20 -- Larger click area
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            sl_x, sl_y, slider_width, slider_height)
                local is_mouse_down = is_hovered and constants.mouse_state.left_button_down
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                local is_pressed = is_hovered and constants.mouse_state.left_button_down and not constants.mouse_state.was_down_last_frame
                
                -- Initialize drag state if not exists
                if slider.is_dragging == nil then
                    slider.is_dragging = false
                end
                
                -- Start dragging on press (not release)
                if is_pressed then
                    slider.is_dragging = true
                end
                
                -- Stop dragging when mouse is released (only if currently dragging)
                if slider.is_dragging and not constants.mouse_state.left_button_down then
                    slider.is_dragging = false
                end
                
                -- Update value while dragging
                if slider.is_dragging and constants.mouse_state.left_button_down then
                    local click_x = constants.mouse_state.position.x - sl_x
                    local ratio = math.max(0, math.min(1, click_x / slider_width))
                    local new_value = slider.min_value + (ratio * (slider.max_value - slider.min_value))
                    -- Round to 2 decimal places
                    new_value = math.floor(new_value * 100 + 0.5) / 100
                    
                    -- Only update if value changed
                    if new_value ~= slider.internal_value then
                        slider.internal_value = new_value
                        if slider.callback then
                            slider.callback(new_value)
                        end
                    end
                end
                
                -- Use internal value
                local current_value = slider.internal_value
                
                -- Render slider visual
                local display_height = 6
                local handle_size = 12
                
                -- Calculate handle position
                local value_ratio = (current_value - slider.min_value) / (slider.max_value - slider.min_value)
                local handle_x = sl_x + (value_ratio * (slider_width - handle_size))
                
                -- Slider track
                local track_color = is_hovered and color.new(80, 80, 80, 255) or color.new(60, 60, 60, 255)
                core.graphics.rect_2d_filled(
                    vec2.new(sl_x, sl_y + 8),
                    slider_width, display_height,
                    track_color,
                    2
                )
                
                -- Slider handle with drag state feedback
                local handle_color = color.new(100, 150, 200, 255) -- Default
                if slider.is_dragging then
                    handle_color = color.new(150, 200, 255, 255) -- Bright blue when dragging
                elseif is_hovered then
                    handle_color = color.new(120, 170, 220, 255) -- Hover color
                end
                
                core.graphics.rect_2d_filled(
                    vec2.new(handle_x, sl_y + 4),
                    handle_size, handle_size + 4,
                    handle_color,
                    2
                )
                
                -- Slider text and value
                local text_color = is_hovered and color.new(255, 255, 100, 255) or slider.text_color
                core.graphics.text_2d(
                    slider.text .. ": " .. string.format("%.2f", current_value),
                    vec2.new(sl_x, sl_y - 15),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
            end
        end
        
        -- Render all comboboxes with full interactivity
        for _, combo in ipairs(gui.comboboxes) do
            if combo.menu_component then
                local cb_x = gui.x_offset + combo.x
                local cb_y = base_y + combo.y
                
                -- Initialize state if not set
                if combo.selected_index == nil then
                    combo.selected_index = combo.default_index or 1
                end
                if combo.is_open == nil then
                    combo.is_open = false
                end
                
                -- Handle interaction
                local combo_height = 20
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            cb_x, cb_y, combo.width, combo_height)
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                
                -- Debug logging
                if is_clicked then
                    core.log("Combobox clicked: " .. combo.text .. " - toggling dropdown")
                end
                
                -- Toggle dropdown on click
                if is_clicked then
                    combo.is_open = not combo.is_open
                end
                
                -- Render main combobox
                local combo_bg = is_hovered and color.new(50, 50, 50, 255) or color.new(40, 40, 40, 255)
                local combo_border = is_hovered and color.new(120, 120, 120, 255) or color.new(100, 100, 100, 255)
                
                -- Combobox background
                core.graphics.rect_2d_filled(
                    vec2.new(cb_x, cb_y),
                    combo.width, combo_height,
                    combo_bg,
                    2
                )
                
                -- Combobox border
                core.graphics.rect_2d(
                    vec2.new(cb_x, cb_y),
                    combo.width, combo_height,
                    combo_border,
                    1, 2
                )
                
                -- Selected item text
                local selected_text = combo.items[combo.selected_index] or "Unknown"
                local text_color = is_hovered and color.new(255, 255, 100, 255) or combo.text_color
                core.graphics.text_2d(
                    combo.text .. ": " .. selected_text,
                    vec2.new(cb_x + 5, cb_y + 3),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
                
                -- Dropdown arrow (rotated based on open state)
                local arrow_color = is_hovered and color.new(255, 255, 255, 255) or color.new(200, 200, 200, 255)
                if combo.is_open then
                    -- Up arrow when open
                    core.graphics.triangle_2d_filled(
                        vec2.new(cb_x + combo.width - 15, cb_y + 13),
                        vec2.new(cb_x + combo.width - 10, cb_y + 7),
                        vec2.new(cb_x + combo.width - 5, cb_y + 13),
                        arrow_color
                    )
                else
                    -- Down arrow when closed
                    core.graphics.triangle_2d_filled(
                        vec2.new(cb_x + combo.width - 15, cb_y + 7),
                        vec2.new(cb_x + combo.width - 10, cb_y + 13),
                        vec2.new(cb_x + combo.width - 5, cb_y + 7),
                        arrow_color
                    )
                end
                
                -- Store dropdown info for later rendering (on top)
                if combo.is_open then
                    combo._dropdown_render_info = {
                        cb_x = cb_x,
                        cb_y = cb_y,
                        combo_height = combo_height,
                        base_y = base_y,
                        gui_x_offset = gui.x_offset
                    }
                    
                    -- Handle dropdown interactions (but don't render yet)
                    local dropdown_y = cb_y + combo_height + 2
                    local item_height = 18
                    local dropdown_height = #combo.items * item_height
                    
                    -- Handle item selection
                    for i, item in ipairs(combo.items) do
                        local item_y = dropdown_y + (i - 1) * item_height
                        local item_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                     cb_x, item_y, combo.width, item_height)
                        local item_clicked = item_hovered and constants.mouse_state.left_button_clicked
                        
                        if item_clicked then
                            core.log("Combobox item selected: " .. combo.text .. " = " .. i .. " (" .. item .. ")")
                            combo.selected_index = i
                            combo.is_open = false
                            combo._dropdown_render_info = nil
                            if combo.callback then
                                combo.callback(i)
                            end
                        end
                    end
                    
                    -- Close dropdown if clicking outside
                    if constants.mouse_state.left_button_clicked then
                        local dropdown_area_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                              cb_x, cb_y, combo.width, combo_height + dropdown_height + 2)
                        if not dropdown_area_hovered then
                            combo.is_open = false
                            combo._dropdown_render_info = nil
                            core.log("Combobox closed by clicking outside")
                        end
                    end
                else
                    combo._dropdown_render_info = nil
                end
            end
        end
        
        -- Render interactive keybinds with full setup functionality
        for _, keybind in ipairs(gui.keybinds) do
            if keybind.menu_component then
                local kb_x = gui.x_offset + keybind.x
                local kb_y = base_y + keybind.y
                
                -- Initialize keybind state if not set
                if keybind.current_key == nil then
                    keybind.current_key = keybind.default_key or 0
                end
                if keybind.is_listening == nil then
                    keybind.is_listening = false
                end
                if keybind.listen_start_time == nil then
                    keybind.listen_start_time = 0
                end
                
                -- Handle keybind interaction
                local keybind_width = keybind.width or 200
                local keybind_height = 20
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            kb_x, kb_y, keybind_width, keybind_height)
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                
                -- Handle click to enter listening mode
                if is_clicked then
                    if keybind.is_listening then
                        -- If already listening, cancel
                        keybind.is_listening = false
                        core.log("Keybind listening cancelled for: " .. keybind.text)
                    else
                        -- Cancel any other listening keybinds
                        for _, other_keybind in ipairs(gui.keybinds) do
                            other_keybind.is_listening = false
                        end
                        
                        -- Start listening for this keybind
                        keybind.is_listening = true
                        keybind.listen_start_time = core.time()
                        core.log("Listening for keybind: " .. keybind.text)
                        
                        -- Block game input while listening for keys
                        core.input.disable_movement(true)
                    end
                end
                
                -- Handle key listening
                if keybind.is_listening then
                    -- Check for any key press (excluding mouse buttons)
                    for key_code = 8, 255 do -- Start from 8 (backspace) to avoid mouse buttons
                        if key_code ~= 0x01 and key_code ~= 0x02 and key_code ~= 0x04 then -- Skip mouse buttons
                            if core.input.is_key_pressed(key_code) then
                                -- Key pressed - assign it
                                keybind.current_key = key_code
                                keybind.is_listening = false
                                core.log("Keybind set: " .. keybind.text .. " = " .. key_code)
                                
                                -- Call callback if provided
                                if keybind.callback then
                                    keybind.callback(key_code)
                                end
                                
                                -- Re-enable game input
                                core.input.enable_movement()
                                break
                            end
                        end
                    end
                    
                    -- Cancel listening after 5 seconds
                    if core.time() - keybind.listen_start_time > 5000 then
                        keybind.is_listening = false
                        core.log("Keybind listening timeout for: " .. keybind.text)
                        core.input.enable_movement()
                    end
                end
                
                -- Visual styling based on state
                local keybind_bg = color.new(40, 40, 40, 255)
                local keybind_border = color.new(100, 100, 100, 255)
                local text_color = keybind.text_color or color.white(255)
                
                if keybind.is_listening then
                    -- Listening state - bright blue
                    keybind_bg = color.new(0, 100, 200, 255)
                    keybind_border = color.new(0, 150, 255, 255)
                    text_color = color.white(255)
                elseif is_hovered then
                    -- Hover state - lighter
                    keybind_bg = color.new(60, 60, 60, 255)
                    keybind_border = color.new(120, 120, 120, 255)
                    text_color = color.new(255, 255, 100, 255)
                end
                
                -- Render keybind background
                core.graphics.rect_2d_filled(
                    vec2.new(kb_x, kb_y),
                    keybind_width, keybind_height,
                    keybind_bg,
                    2
                )
                
                -- Render keybind border
                core.graphics.rect_2d(
                    vec2.new(kb_x, kb_y),
                    keybind_width, keybind_height,
                    keybind_border,
                    keybind.is_listening and 2 or 1, 2
                )
                
                -- Render keybind text
                local key_name = get_key_name(keybind.current_key)
                local display_text = keybind.text .. ": " .. key_name
                
                if keybind.is_listening then
                    display_text = keybind.text .. ": [Press any key...]"
                end
                
                core.graphics.text_2d(
                    display_text,
                    vec2.new(kb_x + 5, kb_y + 3),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
                
                -- Render clear button if not listening
                if not keybind.is_listening and keybind.current_key ~= 0 then
                    local clear_x = kb_x + keybind_width - 20
                    local clear_y = kb_y + 2
                    local clear_size = 16
                    
                    local clear_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                   clear_x, clear_y, clear_size, clear_size)
                    local clear_clicked = clear_hovered and constants.mouse_state.left_button_clicked
                    
                    if clear_clicked then
                        keybind.current_key = 0
                        core.log("Keybind cleared for: " .. keybind.text)
                        if keybind.callback then
                            keybind.callback(0)
                        end
                    end
                    
                    -- Render clear button
                    local clear_color = clear_hovered and color.new(255, 100, 100, 255) or color.new(200, 200, 200, 255)
                    core.graphics.rect_2d(
                        vec2.new(clear_x, clear_y),
                        clear_size, clear_size,
                        clear_color,
                        1, 2
                    )
                    
                    -- Render X
                    core.graphics.text_2d(
                        "X",
                        vec2.new(clear_x + 5, clear_y + 1),
                        constants.FONT_SIZE - 2,
                        clear_color,
                        false
                    )
                end
            end
        end
        
        -- Render all color pickers with full interactivity
        for _, colorpicker in ipairs(gui.colorpickers) do
            if colorpicker.menu_component then
                local cp_x = gui.x_offset + colorpicker.x
                local cp_y = base_y + colorpicker.y
                
                -- Initialize state if not set
                if colorpicker.current_color == nil then
                    colorpicker.current_color = colorpicker.default_color or color.white(255)
                end
                if colorpicker.is_open == nil then
                    colorpicker.is_open = false
                end
                
                -- Handle color picker interaction
                local preview_width = 80
                local preview_height = 20
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            cp_x, cp_y, preview_width, preview_height)
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                
                -- Debug logging
                if is_clicked then
                    core.log("Color picker clicked: " .. colorpicker.text .. " - toggling color picker")
                end
                
                -- Toggle color picker on click
                if is_clicked then
                    colorpicker.is_open = not colorpicker.is_open
                end
                
                -- Render color preview with border
                local preview_bg = is_hovered and color.new(70, 70, 70, 255) or color.new(50, 50, 50, 255)
                local preview_border = is_hovered and color.new(120, 120, 120, 255) or color.new(100, 100, 100, 255)
                
                -- Preview border
                core.graphics.rect_2d_filled(
                    vec2.new(cp_x - 2, cp_y - 2),
                    preview_width + 4, preview_height + 4,
                    preview_border,
                    2
                )
                
                -- Color preview
                core.graphics.rect_2d_filled(
                    vec2.new(cp_x, cp_y),
                    preview_width, preview_height,
                    colorpicker.current_color,
                    2
                )
                
                -- Color picker text
                local text_color = is_hovered and color.new(255, 255, 100, 255) or colorpicker.text_color
                core.graphics.text_2d(
                    colorpicker.text,
                    vec2.new(cp_x + preview_width + 10, cp_y + 3),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
                
                -- Store color picker info for later rendering (on top)
                if colorpicker.is_open then
                    colorpicker._picker_render_info = {
                        cp_x = cp_x,
                        cp_y = cp_y,
                        preview_height = preview_height,
                        base_y = base_y,
                        gui_x_offset = gui.x_offset
                    }
                    
                    -- Handle color picker interactions (but don't render yet)
                    local picker_y = cp_y + preview_height + 5
                    local picker_width = 280
                    local picker_height = 175
                    
                    -- Initialize RGB sliders if not set
                    if colorpicker.rgb_sliders == nil then
                        colorpicker.rgb_sliders = {
                            r = {value = colorpicker.current_color.r or 255, is_dragging = false},
                            g = {value = colorpicker.current_color.g or 255, is_dragging = false},
                            b = {value = colorpicker.current_color.b or 255, is_dragging = false}
                        }
                    end
                    
                    -- Handle rainbow color strip interaction
                    local rainbow_y = picker_y + 35
                    local rainbow_width = 220
                    local rainbow_height = 20
                    local rainbow_segments = 12
                    local segment_width = rainbow_width / rainbow_segments
                    
                    -- Check for rainbow color strip clicks
                    for i = 1, rainbow_segments do
                        local segment_x = cp_x + 10 + (i - 1) * segment_width
                        local segment_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                        segment_x, rainbow_y, segment_width, rainbow_height)
                        local segment_clicked = segment_hovered and constants.mouse_state.left_button_clicked
                        
                        if segment_clicked then
                            -- Calculate HSV color for this segment
                            local hue = (i - 1) * (360 / rainbow_segments)
                            local saturation = 1.0
                            local value = 1.0
                            
                            -- Convert HSV to RGB
                            local c = value * saturation
                            local x = c * (1 - math.abs(((hue / 60) % 2) - 1))
                            local m = value - c
                            local r, g, b
                            
                            if hue < 60 then r, g, b = c, x, 0
                            elseif hue < 120 then r, g, b = x, c, 0
                            elseif hue < 180 then r, g, b = 0, c, x
                            elseif hue < 240 then r, g, b = 0, x, c
                            elseif hue < 300 then r, g, b = x, 0, c
                            else r, g, b = c, 0, x end
                            
                            -- Convert to 0-255 range
                            local red = math.floor((r + m) * 255)
                            local green = math.floor((g + m) * 255)
                            local blue = math.floor((b + m) * 255)
                            
                            -- Update RGB sliders
                            colorpicker.rgb_sliders.r.value = red
                            colorpicker.rgb_sliders.g.value = green
                            colorpicker.rgb_sliders.b.value = blue
                            
                            core.log("Rainbow color selected: RGB(" .. red .. ", " .. green .. ", " .. blue .. ")")
                        end
                    end
                    
                    -- Handle RGB slider interactions
                    local slider_width = 150
                    local slider_height = 20
                    local slider_spacing = 25
                    
                    -- Red slider
                    local red_y = picker_y + 65
                    local red_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                               cp_x + 20, red_y, slider_width, slider_height)
                    local red_pressed = red_hovered and constants.mouse_state.left_button_down and not constants.mouse_state.was_down_last_frame
                    
                    if red_pressed then
                        colorpicker.rgb_sliders.r.is_dragging = true
                    end
                    if colorpicker.rgb_sliders.r.is_dragging and not constants.mouse_state.left_button_down then
                        colorpicker.rgb_sliders.r.is_dragging = false
                    end
                    if colorpicker.rgb_sliders.r.is_dragging and constants.mouse_state.left_button_down then
                        local click_x = constants.mouse_state.position.x - (cp_x + 20)
                        local ratio = math.max(0, math.min(1, click_x / slider_width))
                        colorpicker.rgb_sliders.r.value = math.floor(ratio * 255)
                    end
                    
                    -- Green slider
                    local green_y = picker_y + 65 + slider_spacing
                    local green_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                 cp_x + 20, green_y, slider_width, slider_height)
                    local green_pressed = green_hovered and constants.mouse_state.left_button_down and not constants.mouse_state.was_down_last_frame
                    
                    if green_pressed then
                        colorpicker.rgb_sliders.g.is_dragging = true
                    end
                    if colorpicker.rgb_sliders.g.is_dragging and not constants.mouse_state.left_button_down then
                        colorpicker.rgb_sliders.g.is_dragging = false
                    end
                    if colorpicker.rgb_sliders.g.is_dragging and constants.mouse_state.left_button_down then
                        local click_x = constants.mouse_state.position.x - (cp_x + 20)
                        local ratio = math.max(0, math.min(1, click_x / slider_width))
                        colorpicker.rgb_sliders.g.value = math.floor(ratio * 255)
                    end
                    
                    -- Blue slider
                    local blue_y = picker_y + 65 + (slider_spacing * 2)
                    local blue_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                cp_x + 20, blue_y, slider_width, slider_height)
                    local blue_pressed = blue_hovered and constants.mouse_state.left_button_down and not constants.mouse_state.was_down_last_frame
                    
                    if blue_pressed then
                        colorpicker.rgb_sliders.b.is_dragging = true
                    end
                    if colorpicker.rgb_sliders.b.is_dragging and not constants.mouse_state.left_button_down then
                        colorpicker.rgb_sliders.b.is_dragging = false
                    end
                    if colorpicker.rgb_sliders.b.is_dragging and constants.mouse_state.left_button_down then
                        local click_x = constants.mouse_state.position.x - (cp_x + 20)
                        local ratio = math.max(0, math.min(1, click_x / slider_width))
                        colorpicker.rgb_sliders.b.value = math.floor(ratio * 255)
                    end
                    
                    -- Update current color from sliders
                    local new_color = color.new(
                        colorpicker.rgb_sliders.r.value,
                        colorpicker.rgb_sliders.g.value,
                        colorpicker.rgb_sliders.b.value,
                        colorpicker.current_color.a or 255
                    )
                    
                    -- Always update current color (for live preview)
                    colorpicker.current_color = new_color
                    
                    -- Only fire callback if any slider is being dragged
                    if colorpicker.rgb_sliders.r.is_dragging or 
                       colorpicker.rgb_sliders.g.is_dragging or 
                       colorpicker.rgb_sliders.b.is_dragging then
                        if colorpicker.callback then
                            colorpicker.callback(new_color)
                        end
                    end
                    
                    -- Close color picker if clicking outside
                    if constants.mouse_state.left_button_clicked then
                        local picker_area_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                            cp_x, cp_y, picker_width, preview_height + picker_height + 10)
                        if not picker_area_hovered then
                            colorpicker.is_open = false
                            colorpicker._picker_render_info = nil
                            core.log("Color picker closed by clicking outside")
                        end
                    end
                else
                    colorpicker._picker_render_info = nil
                end
            end
        end
        
        -- Render all text inputs with full interactivity
        for _, textinput in ipairs(gui.text_inputs) do
            if textinput.menu_component then
                local ti_x = gui.x_offset + textinput.x
                local ti_y = base_y + textinput.y
                
                -- Initialize state if not set
                if textinput.current_text == nil then
                    textinput.current_text = textinput.default_text or ""
                end
                if textinput.is_focused == nil then
                    textinput.is_focused = false
                end
                if textinput.cursor_pos == nil then
                    textinput.cursor_pos = string.len(textinput.current_text)
                end
                if textinput.selection_start == nil then
                    textinput.selection_start = nil
                end
                if textinput.selection_end == nil then
                    textinput.selection_end = nil
                end
                if textinput.last_click_time == nil then
                    textinput.last_click_time = 0
                end
                if textinput.has_default_text == nil then
                    textinput.has_default_text = textinput.default_text and textinput.default_text ~= ""
                end
                if textinput.key_repeat_states == nil then
                    textinput.key_repeat_states = {}
                end
                
                -- Handle text input interaction
                local input_width = textinput.width or 150
                local input_height = 20
                local is_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            ti_x, ti_y, input_width, input_height)
                local is_clicked = is_hovered and constants.mouse_state.left_button_clicked
                
                -- Focus management and cursor positioning
                if is_clicked then
                    textinput.is_focused = true
                    -- Block game input when text input is focused (prevents typing from triggering game actions)
                    core.input.disable_movement(true)
                    -- Unfocus other text inputs
                    for _, other_input in ipairs(gui.text_inputs) do
                        if other_input ~= textinput then
                            other_input.is_focused = false
                        end
                    end
                    
                    -- Clear default text on first focus
                    if textinput.has_default_text then
                        textinput.current_text = ""
                        textinput.cursor_pos = 0
                        textinput.has_default_text = false
                        textinput.selection_start = nil
                        textinput.selection_end = nil
                        core.log("Default text cleared on focus")
                    else
                        -- Handle double-click to select all text
                        local current_time = core.time()
                        local double_click_threshold = 0.5 -- 500ms
                        
                        if (current_time - textinput.last_click_time) <= double_click_threshold then
                            -- Double-click: select all text
                            textinput.selection_start = 0
                            textinput.selection_end = string.len(textinput.current_text)
                            textinput.cursor_pos = string.len(textinput.current_text)
                            core.log("Double-click: selected all text")
                        else
                            -- Single click: position cursor based on click location
                            local click_x = constants.mouse_state.position.x - (ti_x + 5)
                            local text_width = 0
                            local best_pos = 0
                            
                            -- Find the best cursor position by checking character widths
                            for i = 0, string.len(textinput.current_text) do
                                local sub_text = string.sub(textinput.current_text, 1, i)
                                local char_width = core.graphics.get_text_width(sub_text, constants.FONT_SIZE, 0)
                                if char_width <= click_x then
                                    best_pos = i
                                    text_width = char_width
                                else
                                    break
                                end
                            end
                            
                            textinput.cursor_pos = best_pos
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                            core.log("Single-click: cursor positioned at " .. best_pos)
                        end
                        
                        textinput.last_click_time = current_time
                    end
                    
                    core.log("Text input focused: " .. textinput.text)
                elseif constants.mouse_state.left_button_clicked and not is_hovered then
                    textinput.is_focused = false
                    
                    -- Check if any text input is still focused, if not, re-enable input
                    local any_focused = false
                    for _, other_input in ipairs(gui.text_inputs) do
                        if other_input.is_focused then
                            any_focused = true
                            break
                        end
                    end
                    
                    if not any_focused then
                        core.input.enable_movement()
                    end
                end
                
                -- Keyboard input handling (only if focused)
                if textinput.is_focused then
                    -- Initialize key state tracking
                    if textinput.last_key_states == nil then
                        textinput.last_key_states = {}
                    end
                    
                    local text_changed = false
                    
                    -- Helper function to clear default text on first edit
                    local function clear_default_text_if_needed()
                        if textinput.has_default_text then
                            textinput.current_text = ""
                            textinput.cursor_pos = 0
                            textinput.has_default_text = false
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                            core.log("Default text cleared on keyboard input")
                        end
                    end
                    
                    -- Helper function to check if key was just pressed (not held)
                    local function is_key_just_pressed(key)
                        local current_state = core.input.is_key_pressed(key)
                        local last_state = textinput.last_key_states[key] or false
                        textinput.last_key_states[key] = current_state
                        return current_state and not last_state
                    end
                    
                    -- Helper function to handle key repeat (fires once, then repeats after delay)
                    local function is_key_pressed_with_repeat(key)
                        local current_state = core.input.is_key_pressed(key)
                        
                        -- Initialize key repeat state if not exists
                        if not textinput.key_repeat_states[key] then
                            textinput.key_repeat_states[key] = {
                                is_pressed = false,
                                frames_held = 0,
                                last_repeat_frame = 0
                            }
                        end
                        
                        local repeat_state = textinput.key_repeat_states[key]
                        
                        if current_state then
                            if not repeat_state.is_pressed then
                                -- Key just pressed - fire immediately
                                repeat_state.is_pressed = true
                                repeat_state.frames_held = 0
                                repeat_state.last_repeat_frame = 0
                                return true
                            else
                                -- Key is being held - increment frame counter
                                repeat_state.frames_held = repeat_state.frames_held + 1
                                
                                -- Constants for timing (assuming 60 FPS)
                                local initial_delay_frames = 24 -- ~400ms at 60fps
                                local repeat_interval_frames = 2 -- ~33ms at 60fps (30 times per second)
                                
                                -- Check if we should repeat
                                if repeat_state.frames_held >= initial_delay_frames then
                                    local frames_since_last_repeat = repeat_state.frames_held - repeat_state.last_repeat_frame
                                    if frames_since_last_repeat >= repeat_interval_frames then
                                        repeat_state.last_repeat_frame = repeat_state.frames_held
                                        return true
                                    end
                                end
                            end
                        else
                            -- Key released - reset state
                            if repeat_state.is_pressed and repeat_state.frames_held > 24 then
                                core.log("Key " .. key .. " held for " .. repeat_state.frames_held .. " frames")
                            end
                            repeat_state.is_pressed = false
                            repeat_state.frames_held = 0
                            repeat_state.last_repeat_frame = 0
                        end
                        
                        return false
                    end
                    
                    -- Helper function to insert text at cursor position
                    local function insert_text_at_cursor(char)
                        -- Clear default text if needed
                        clear_default_text_if_needed()
                        
                        -- If text is selected, replace it
                        if textinput.selection_start and textinput.selection_end then
                            local start_pos = math.min(textinput.selection_start, textinput.selection_end)
                            local end_pos = math.max(textinput.selection_start, textinput.selection_end)
                            
                            local before = string.sub(textinput.current_text, 1, start_pos)
                            local after = string.sub(textinput.current_text, end_pos + 1)
                            
                            textinput.current_text = before .. char .. after
                            textinput.cursor_pos = start_pos + 1
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                        else
                            -- Insert at cursor position
                            local before = string.sub(textinput.current_text, 1, textinput.cursor_pos)
                            local after = string.sub(textinput.current_text, textinput.cursor_pos + 1)
                            
                            textinput.current_text = before .. char .. after
                            textinput.cursor_pos = textinput.cursor_pos + 1
                        end
                        text_changed = true
                    end
                    
                    -- Handle basic character input (A-Z, 0-9, space, basic punctuation)
                    -- Letters A-Z
                    for i = 65, 90 do -- A-Z
                        if is_key_just_pressed(i) then
                            local char = string.char(i + 32) -- Convert to lowercase
                            if core.input.is_key_pressed(0x10) then -- Shift key
                                char = string.char(i) -- Use uppercase
                            end
                            insert_text_at_cursor(char)
                            break
                        end
                    end
                    
                    -- Numbers 0-9
                    for i = 48, 57 do -- 0-9
                        if is_key_just_pressed(i) then
                            local char = string.char(i)
                            insert_text_at_cursor(char)
                            break
                        end
                    end
                    
                    -- Space
                    if is_key_just_pressed(0x20) then
                        insert_text_at_cursor(" ")
                    end
                    
                    -- Common punctuation and symbols
                    if is_key_just_pressed(0xBE) then -- Period (.)
                        insert_text_at_cursor(".")
                    elseif is_key_just_pressed(0xBC) then -- Comma (,)
                        insert_text_at_cursor(",")
                    elseif is_key_just_pressed(0xBA) then -- Semicolon (;) or Colon (:)
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor(":")
                        else
                            insert_text_at_cursor(";")
                        end
                    elseif is_key_just_pressed(0xBD) then -- Hyphen (-) or Underscore (_)
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("_")
                        else
                            insert_text_at_cursor("-")
                        end
                    elseif is_key_just_pressed(0xBB) then -- Equals (=) or Plus (+)
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("+")
                        else
                            insert_text_at_cursor("=")
                        end
                    elseif is_key_just_pressed(0xDB) then -- Left bracket ([) or Left brace ({)
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("{")
                        else
                            insert_text_at_cursor("[")
                        end
                    elseif is_key_just_pressed(0xDD) then -- Right bracket (]) or Right brace (})
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("}")
                        else
                            insert_text_at_cursor("]")
                        end
                    elseif is_key_just_pressed(0xDC) then -- Backslash (\) or Pipe (|)
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("|")
                        else
                            insert_text_at_cursor("\\")
                        end
                    elseif is_key_just_pressed(0xDE) then -- Quote (') or Double quote (")
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("\"")
                        else
                            insert_text_at_cursor("'")
                        end
                    elseif is_key_just_pressed(0xC0) then -- Backtick (`) or Tilde (~)
                        if core.input.is_key_pressed(0x10) then -- Shift key
                            insert_text_at_cursor("~")
                        else
                            insert_text_at_cursor("`")
                        end
                    end
                    

                    
                    -- Backspace (with repeat)
                    if is_key_pressed_with_repeat(0x08) then
                        core.log("Backspace fired!")
                        -- Clear default text if needed
                        clear_default_text_if_needed()
                        
                        if textinput.selection_start and textinput.selection_end then
                            -- Delete selected text
                            local start_pos = math.min(textinput.selection_start, textinput.selection_end)
                            local end_pos = math.max(textinput.selection_start, textinput.selection_end)
                            
                            local before = string.sub(textinput.current_text, 1, start_pos)
                            local after = string.sub(textinput.current_text, end_pos + 1)
                            
                            textinput.current_text = before .. after
                            textinput.cursor_pos = start_pos
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                            text_changed = true
                        elseif textinput.cursor_pos > 0 then
                            -- Delete character before cursor
                            local before = string.sub(textinput.current_text, 1, textinput.cursor_pos - 1)
                            local after = string.sub(textinput.current_text, textinput.cursor_pos + 1)
                            
                            textinput.current_text = before .. after
                            textinput.cursor_pos = textinput.cursor_pos - 1
                            text_changed = true
                        end
                    end
                    
                    -- Delete key (with repeat)
                    if is_key_pressed_with_repeat(0x2E) then -- Delete
                        -- Clear default text if needed
                        clear_default_text_if_needed()
                        
                        if textinput.selection_start and textinput.selection_end then
                            -- Delete selected text
                            local start_pos = math.min(textinput.selection_start, textinput.selection_end)
                            local end_pos = math.max(textinput.selection_start, textinput.selection_end)
                            
                            local before = string.sub(textinput.current_text, 1, start_pos)
                            local after = string.sub(textinput.current_text, end_pos + 1)
                            
                            textinput.current_text = before .. after
                            textinput.cursor_pos = start_pos
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                            text_changed = true
                        elseif textinput.cursor_pos < string.len(textinput.current_text) then
                            -- Delete character at cursor
                            local before = string.sub(textinput.current_text, 1, textinput.cursor_pos)
                            local after = string.sub(textinput.current_text, textinput.cursor_pos + 2)
                            
                            textinput.current_text = before .. after
                            text_changed = true
                        end
                    end
                    
                    -- Arrow key navigation (with repeat)
                    if is_key_pressed_with_repeat(0x25) then -- Left arrow
                        if textinput.cursor_pos > 0 then
                            textinput.cursor_pos = textinput.cursor_pos - 1
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                        end
                    elseif is_key_pressed_with_repeat(0x27) then -- Right arrow
                        if textinput.cursor_pos < string.len(textinput.current_text) then
                            textinput.cursor_pos = textinput.cursor_pos + 1
                            textinput.selection_start = nil
                            textinput.selection_end = nil
                        end
                    elseif is_key_pressed_with_repeat(0x24) then -- Home
                        textinput.cursor_pos = 0
                        textinput.selection_start = nil
                        textinput.selection_end = nil
                    elseif is_key_pressed_with_repeat(0x23) then -- End
                        textinput.cursor_pos = string.len(textinput.current_text)
                        textinput.selection_start = nil
                        textinput.selection_end = nil
                    end
                    
                    -- Fire callback if text changed
                    if text_changed and textinput.callback then
                        textinput.callback(textinput.current_text)
                    end
                end
                
                -- Visual styling based on state
                local input_bg = color.new(40, 40, 40, 255)
                local input_border = color.new(100, 100, 100, 255)
                local text_color = textinput.text_color or color.white(255)
                
                if textinput.is_focused then
                    input_bg = color.new(50, 50, 60, 255)
                    input_border = color.new(100, 150, 255, 255) -- Blue border when focused
                    text_color = color.white(255)
                elseif is_hovered then
                    input_bg = color.new(45, 45, 50, 255)
                    input_border = color.new(120, 120, 120, 255)
                    text_color = color.new(255, 255, 100, 255)
                end
                
                -- Render input field background
                core.graphics.rect_2d_filled(
                    vec2.new(ti_x, ti_y),
                    input_width, input_height,
                    input_bg,
                    2
                )
                
                -- Render input field border
                core.graphics.rect_2d(
                    vec2.new(ti_x, ti_y),
                    input_width, input_height,
                    input_border,
                    textinput.is_focused and 2 or 1, 2
                )
                
                -- Render label
                core.graphics.text_2d(
                    textinput.text .. ":",
                    vec2.new(ti_x, ti_y - 15),
                    constants.FONT_SIZE,
                    text_color,
                    false
                )
                
                -- Render input text with placeholder support
                local display_text = textinput.current_text
                local render_color = text_color
                
                -- Show placeholder if text is empty and not focused (and no default text)
                if display_text == "" and not textinput.is_focused and not textinput.has_default_text then
                    display_text = textinput.placeholder or "Enter text here..."
                    render_color = color.new(120, 120, 120, 255) -- Gray placeholder
                elseif textinput.has_default_text then
                    -- Default text is shown in slightly muted color to indicate it's temporary
                    render_color = color.new(200, 200, 200, 255) -- Slightly muted white
                end
                
                -- Render text selection background if applicable
                if textinput.selection_start and textinput.selection_end and textinput.is_focused then
                    local start_pos = math.min(textinput.selection_start, textinput.selection_end)
                    local end_pos = math.max(textinput.selection_start, textinput.selection_end)
                    
                    local before_text = string.sub(textinput.current_text, 1, start_pos)
                    local selected_text = string.sub(textinput.current_text, start_pos + 1, end_pos)
                    
                    local before_width = core.graphics.get_text_width(before_text, constants.FONT_SIZE, 0)
                    local selected_width = core.graphics.get_text_width(selected_text, constants.FONT_SIZE, 0)
                    
                    -- Render selection background
                    core.graphics.rect_2d_filled(
                        vec2.new(ti_x + 5 + before_width, ti_y + 3),
                        selected_width, constants.FONT_SIZE,
                        color.new(0, 120, 215, 100),
                        0
                    )
                end
                
                core.graphics.text_2d(
                    display_text,
                    vec2.new(ti_x + 5, ti_y + 3),
                    constants.FONT_SIZE,
                    render_color,
                    false
                )
                
                -- Render cursor if focused
                if textinput.is_focused then
                    local cursor_text = string.sub(textinput.current_text, 1, textinput.cursor_pos)
                    local cursor_x = ti_x + 5 + core.graphics.get_text_width(cursor_text, constants.FONT_SIZE, 0)
                    -- Simple static cursor (always visible when focused)
                    core.graphics.line_2d(
                        vec2.new(cursor_x, ti_y + 3),
                        vec2.new(cursor_x, ti_y + input_height - 3),
                        color.white(255), 1
                    )
                end
            end
        end
        
        for _, component in ipairs(gui.headers) do
            if component.menu_component then
                core.graphics.text_2d(
                    component.text,
                    vec2.new(gui.x_offset + component.x, base_y + component.y),
                    constants.FONT_SIZE + 2,
                    color.yellow(255),
                    false
                )
            end
        end
        
        for _, component in ipairs(gui.key_checkboxes) do
            if component.menu_component then
                local key_value = component.default_key or 0
                
                core.graphics.text_2d(
                    component.text .. ": " .. tostring(key_value),
                    vec2.new(gui.x_offset + component.x, base_y + component.y),
                    constants.FONT_SIZE,
                    component.text_color,
                    false
                )
            end
        end
        
        -- Render all open dropdowns ON TOP of everything else
        for _, combo in ipairs(gui.comboboxes) do
            if combo.is_open and combo._dropdown_render_info then
                local info = combo._dropdown_render_info
                local dropdown_y = info.cb_y + info.combo_height + 2
                local item_height = 18
                local dropdown_height = #combo.items * item_height
                
                -- Dropdown background
                core.graphics.rect_2d_filled(
                    vec2.new(info.cb_x, dropdown_y),
                    combo.width, dropdown_height,
                    color.new(35, 35, 35, 255),
                    2
                )
                
                -- Dropdown border
                core.graphics.rect_2d(
                    vec2.new(info.cb_x, dropdown_y),
                    combo.width, dropdown_height,
                    color.new(80, 80, 80, 255),
                    1, 2
                )
                
                -- Render dropdown items
                for i, item in ipairs(combo.items) do
                    local item_y = dropdown_y + (i - 1) * item_height
                    local item_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                 info.cb_x, item_y, combo.width, item_height)
                    
                    -- Item background (highlight if hovered or selected)
                    local item_bg = color.new(35, 35, 35, 255) -- Default
                    if i == combo.selected_index then
                        item_bg = color.new(60, 80, 120, 255) -- Selected item
                    end
                    if item_hovered then
                        item_bg = color.new(80, 100, 140, 255) -- Hovered item
                    end
                    
                    core.graphics.rect_2d_filled(
                        vec2.new(info.cb_x, item_y),
                        combo.width, item_height,
                        item_bg,
                        0
                    )
                    
                    -- Item text
                    local item_text_color = color.white(255)
                    if i == combo.selected_index then
                        item_text_color = color.new(255, 255, 100, 255) -- Selected item text
                    end
                    if item_hovered then
                        item_text_color = color.new(255, 255, 255, 255) -- Hovered item text
                    end
                    
                    core.graphics.text_2d(
                        item,
                        vec2.new(info.cb_x + 5, item_y + 2),
                        constants.FONT_SIZE,
                        item_text_color,
                        false
                    )
                end
            end
        end
        
        -- Render all open color pickers ON TOP of everything else
        for _, colorpicker in ipairs(gui.colorpickers) do
            if colorpicker.is_open and colorpicker._picker_render_info then
                local info = colorpicker._picker_render_info
                local picker_y = info.cp_y + info.preview_height + 5
                local picker_width = 280
                local picker_height = 175
                
                -- Color picker background
                core.graphics.rect_2d_filled(
                    vec2.new(info.cp_x, picker_y),
                    picker_width, picker_height,
                    color.new(30, 30, 30, 255),
                    3
                )
                
                -- Color picker border
                core.graphics.rect_2d(
                    vec2.new(info.cp_x, picker_y),
                    picker_width, picker_height,
                    color.new(70, 70, 70, 255),
                    2, 3
                )
                
                -- Color picker title
                core.graphics.text_2d(
                    "RGB Color Picker",
                    vec2.new(info.cp_x + 10, picker_y + 10),
                    constants.FONT_SIZE,
                    color.white(255),
                    false
                )
                
                -- Rainbow color strip
                local rainbow_y = picker_y + 35
                local rainbow_width = 220
                local rainbow_height = 20
                local rainbow_segments = 12
                local segment_width = rainbow_width / rainbow_segments
                
                -- Rainbow color strip label
                core.graphics.text_2d(
                    "Quick Colors:",
                    vec2.new(info.cp_x + 120, rainbow_y - 12),
                    constants.FONT_SIZE - 1,
                    color.new(200, 200, 200, 255),
                    false
                )
                
                -- Render rainbow segments
                for i = 1, rainbow_segments do
                    local segment_x = info.cp_x + 10 + (i - 1) * segment_width
                    local segment_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                                    segment_x, rainbow_y, segment_width, rainbow_height)
                    
                    -- Calculate HSV color for this segment
                    local hue = (i - 1) * (360 / rainbow_segments)
                    local saturation = 1.0
                    local value = 1.0
                    
                    -- Convert HSV to RGB
                    local c = value * saturation
                    local x = c * (1 - math.abs(((hue / 60) % 2) - 1))
                    local m = value - c
                    local r, g, b
                    
                    if hue < 60 then r, g, b = c, x, 0
                    elseif hue < 120 then r, g, b = x, c, 0
                    elseif hue < 180 then r, g, b = 0, c, x
                    elseif hue < 240 then r, g, b = 0, x, c
                    elseif hue < 300 then r, g, b = x, 0, c
                    else r, g, b = c, 0, x end
                    
                    -- Convert to 0-255 range and create color
                    local segment_color = color.new(
                        math.floor((r + m) * 255),
                        math.floor((g + m) * 255),
                        math.floor((b + m) * 255),
                        255
                    )
                    
                    -- Render segment with hover effect
                    local segment_border = segment_hovered and color.white(255) or color.new(80, 80, 80, 255)
                    
                    core.graphics.rect_2d_filled(
                        vec2.new(segment_x, rainbow_y),
                        segment_width, rainbow_height,
                        segment_color,
                        0
                    )
                    
                    -- Segment border
                    core.graphics.rect_2d(
                        vec2.new(segment_x, rainbow_y),
                        segment_width, rainbow_height,
                        segment_border,
                        segment_hovered and 2 or 1, 0
                    )
                end
                
                -- RGB sliders
                local slider_width = 150
                local slider_height = 20
                local slider_spacing = 25
                
                -- Red slider
                local red_y = picker_y + 65
                local red_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                           info.cp_x + 20, red_y, slider_width, slider_height)
                
                -- Red slider track
                core.graphics.rect_2d_filled(
                    vec2.new(info.cp_x + 20, red_y + 8),
                    slider_width, 6,
                    color.new(60, 60, 60, 255),
                    2
                )
                
                -- Red slider handle
                local red_ratio = colorpicker.rgb_sliders.r.value / 255
                local red_handle_x = info.cp_x + 20 + (red_ratio * (slider_width - 12))
                local red_handle_color = colorpicker.rgb_sliders.r.is_dragging and color.new(255, 100, 100, 255) or color.new(200, 80, 80, 255)
                
                core.graphics.rect_2d_filled(
                    vec2.new(red_handle_x, red_y + 4),
                    12, 14,
                    red_handle_color,
                    2
                )
                
                -- Red slider text
                core.graphics.text_2d(
                    "R: " .. tostring(colorpicker.rgb_sliders.r.value),
                    vec2.new(info.cp_x + 175, red_y + 3),
                    constants.FONT_SIZE,
                    color.new(255, 100, 100, 255),
                    false
                )
                
                -- Green slider
                local green_y = picker_y + 65 + slider_spacing
                local green_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                             info.cp_x + 20, green_y, slider_width, slider_height)
                
                -- Green slider track
                core.graphics.rect_2d_filled(
                    vec2.new(info.cp_x + 20, green_y + 8),
                    slider_width, 6,
                    color.new(60, 60, 60, 255),
                    2
                )
                
                -- Green slider handle
                local green_ratio = colorpicker.rgb_sliders.g.value / 255
                local green_handle_x = info.cp_x + 20 + (green_ratio * (slider_width - 12))
                local green_handle_color = colorpicker.rgb_sliders.g.is_dragging and color.new(100, 255, 100, 255) or color.new(80, 200, 80, 255)
                
                core.graphics.rect_2d_filled(
                    vec2.new(green_handle_x, green_y + 4),
                    12, 14,
                    green_handle_color,
                    2
                )
                
                -- Green slider text
                core.graphics.text_2d(
                    "G: " .. tostring(colorpicker.rgb_sliders.g.value),
                    vec2.new(info.cp_x + 175, green_y + 3),
                    constants.FONT_SIZE,
                    color.new(100, 255, 100, 255),
                    false
                )
                
                -- Blue slider
                local blue_y = picker_y + 65 + (slider_spacing * 2)
                local blue_hovered = helpers.is_point_in_rect(constants.mouse_state.position.x, constants.mouse_state.position.y, 
                                                            info.cp_x + 20, blue_y, slider_width, slider_height)
                
                -- Blue slider track
                core.graphics.rect_2d_filled(
                    vec2.new(info.cp_x + 20, blue_y + 8),
                    slider_width, 6,
                    color.new(60, 60, 60, 255),
                    2
                )
                
                -- Blue slider handle
                local blue_ratio = colorpicker.rgb_sliders.b.value / 255
                local blue_handle_x = info.cp_x + 20 + (blue_ratio * (slider_width - 12))
                local blue_handle_color = colorpicker.rgb_sliders.b.is_dragging and color.new(100, 100, 255, 255) or color.new(80, 80, 200, 255)
                
                core.graphics.rect_2d_filled(
                    vec2.new(blue_handle_x, blue_y + 4),
                    12, 14,
                    blue_handle_color,
                    2
                )
                
                -- Blue slider text
                core.graphics.text_2d(
                    "B: " .. tostring(colorpicker.rgb_sliders.b.value),
                    vec2.new(info.cp_x + 175, blue_y + 3),
                    constants.FONT_SIZE,
                    color.new(100, 100, 255, 255),
                    false
                )
                
                -- RGB values display (positioned at bottom)
                local values_y = picker_y + 150
                core.graphics.text_2d(
                    "RGB(" .. colorpicker.rgb_sliders.r.value .. ", " .. colorpicker.rgb_sliders.g.value .. ", " .. colorpicker.rgb_sliders.b.value .. ")",
                    vec2.new(info.cp_x + 10, values_y),
                    constants.FONT_SIZE - 1,
                    color.new(200, 200, 200, 255),
                    false
                )
            end
        end
    end
end

-- ==================== NAVBAR RENDERING ====================
local function render_navbar()
    if not constants.selection_bar_enabled then
        return
    end
    
    local screen_size = core.graphics.get_screen_size()
    local navbar_height = 28
    
    -- No full-screen background - tabs will have their own backgrounds
    
    -- Calculate total width needed for all tabs
    local total_buttons = 0
    for name, gui in pairs(constants.registered_guis) do
        if constants.gui_states[name] and constants.gui_states[name]:get_state() then
            total_buttons = total_buttons + 1
        end
    end
    
    if total_buttons == 0 then
        return
    end
    
    local button_width = 100
    local button_spacing = 4
    local total_width = (total_buttons * button_width) + ((total_buttons - 1) * button_spacing)
    local start_x = (screen_size.x - total_width) / 2
    
    local current_x = start_x
    local button_height = navbar_height
    local tab_angle = 6  -- Angle cut for hanging tab effect (proportional to height)
    
    -- Render tabs
    for name, gui in pairs(constants.registered_guis) do
        if not (constants.gui_states[name] and constants.gui_states[name]:get_state()) then
            goto continue
        end
        
        local btn_x = current_x
        local btn_y = 0
        
        -- Check for mouse interaction
        local is_hovered, is_clicked = input.process_mouse_input(btn_x, btn_y, button_width, button_height)
        
        -- Tab colors based on state
        local tab_bg, tab_text, tab_border
        local glow_color = nil
        
        if gui.is_open then
            -- Open state - bright colors
            tab_bg = color.new(70, 100, 150, 255)
            tab_text = color.white(255)
            tab_border = color.new(100, 130, 180, 255)
        else
            -- Closed state - muted colors
            tab_bg = color.new(40, 50, 70, 200)
            tab_text = color.new(180, 180, 180, 255)
            tab_border = color.new(60, 70, 90, 255)
        end
        
        -- Add glow effect on hover
        if is_hovered then
            glow_color = color.new(0, 255, 255, 255)  -- Bright cyan glow
        end
        
        -- Tab background with hanging effect (angled bottom cuts)
        -- Main top section
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
        
        -- Tab text (centered with black outline for readability)
        local text_width = core.graphics.get_text_width(name, constants.TAB_FONT_SIZE, 0)
        local text_x = btn_x + (button_width - text_width) / 2
        local text_y = btn_y + (button_height - constants.TAB_FONT_SIZE) / 2
        
        -- Render black outline (render text multiple times with slight offsets)
        local outline_color = color.new(0, 0, 0, 255)
        local outline_offsets = {
            {-1, -1}, {0, -1}, {1, -1},
            {-1,  0},          {1,  0},
            {-1,  1}, {0,  1}, {1,  1}
        }
        
        for _, offset in ipairs(outline_offsets) do
            core.graphics.text_2d(
                name,
                vec2.new(text_x + offset[1], text_y + offset[2]),
                constants.TAB_FONT_SIZE,
                outline_color,
                false
            )
        end
        
        -- Render main text on top
        core.graphics.text_2d(
            name,
            vec2.new(text_x, text_y),
            constants.TAB_FONT_SIZE,
            tab_text,
            false
        )
        
        -- Handle click
        if is_clicked then
            -- Close all other open GUIs first
            for other_name, other_gui in pairs(constants.registered_guis) do
                if other_name ~= name and other_gui.is_open then
                    other_gui.is_open = false
                end
            end
            
            -- Then toggle this GUI
            gui:toggle()
        end
        
        current_x = current_x + button_width + button_spacing
        
        ::continue::
    end
end

-- ==================== INPUT BLOCKING WINDOW ====================
local function render_input_blocking_window()
    -- Check if any GUI window is currently open
    local open_gui = nil
    
    for name, gui in pairs(constants.registered_guis) do
        if gui.is_open and constants.gui_states[name] and constants.gui_states[name]:get_state() then
            open_gui = gui
            break
        end
    end
    
    -- Only show blocking window if a GUI window is actually open (not just tabs)
    if open_gui then
        -- Reset any previous size constraints and set new ones
        constants.blocking_window:stop_forcing_size()
        constants.blocking_window:force_next_begin_window_pos(vec2.new(open_gui.x_offset, open_gui.y_offset))
        constants.blocking_window:set_next_window_min_size(vec2.new(open_gui.width, open_gui.height))
        constants.blocking_window:force_window_size(vec2.new(open_gui.width, open_gui.height))
        
        constants.blocking_window:set_background_multicolored(
            color.new(0, 0, 0, 0),
            color.new(0, 0, 0, 0),
            color.new(0, 0, 0, 0),
            color.new(0, 0, 0, 0)
        )
        
        constants.blocking_window:begin(
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
                constants.blocking_window:add_artificial_item_bounds(vec2.new(0, 0), vec2.new(open_gui.width, open_gui.height))
            end
        )
    end
end

-- ==================== MAIN RENDER FUNCTION ====================
local function render_direct_gui()
    -- Render input blocking window first (behind our GUI)
    render_input_blocking_window()
    
    -- Update mouse input state
    input.update_mouse_state()
    
    -- Check if any text input is focused or keybind is listening across all GUIs
    local any_input_blocking = false
    for name, gui in pairs(constants.registered_guis) do
        if constants.gui_states[name] and constants.gui_states[name]:get_state() then
            if gui.text_inputs then
                for _, textinput in ipairs(gui.text_inputs) do
                    if textinput.is_focused then
                        any_input_blocking = true
                        break
                    end
                end
            end
            
            if not any_input_blocking and gui.keybinds then
                for _, keybind in ipairs(gui.keybinds) do
                    if keybind.is_listening then
                        any_input_blocking = true
                        break
                    end
                end
            end
        end
        if any_input_blocking then
            break
        end
    end
    
    -- Disable game input if any text input is focused or keybind is listening

    
    -- Render navbar tabs
    render_navbar()
    
    -- Render all active GUIs
    for name, gui in pairs(constants.registered_guis) do
        if constants.gui_states[name] and constants.gui_states[name]:get_state() then
            render_gui_content(gui)
        end
    end
end

-- Export functions
return {
    render_direct_gui = render_direct_gui,
    render_gui_content = render_gui_content,
    render_navbar = render_navbar,
    render_input_blocking_window = render_input_blocking_window
} 