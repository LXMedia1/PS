-- ==================== MENU CLASS ====================

local constants = require("gui/utils/constants")
local color = constants.color
local vec2 = constants.vec2

-- Menu class for external use
local Menu = {}
Menu.__index = Menu

function Menu:new(name, width, height, unique_plugin_key)
    -- Generate unique plugin key if not provided
    if not unique_plugin_key then
        -- Use a simple counter instead of os.time() since os is not available
        if not Menu._unique_counter then
            Menu._unique_counter = 1
        else
            Menu._unique_counter = Menu._unique_counter + 1
        end
        unique_plugin_key = "lx_gui_" .. name:lower():gsub("%s+", "_") .. "_" .. tostring(Menu._unique_counter)
    end
    
    local gui = setmetatable({
        name = name,
        width = width or 400,  -- Default width
        height = height or 300, -- Default height
        x_offset = 0,  -- Position within the 800x800 space
        y_offset = 35, -- Start below navbar
        is_open = false,
        render_callback = nil,
        labels = {},  -- Store labels for this GUI
        buttons = {},  -- Store custom buttons for this GUI
        images = {},   -- Store images for this GUI
        checkboxes = {},  -- Store checkboxes for this GUI
        sliders_int = {},  -- Store integer sliders for this GUI
        sliders_float = {},  -- Store float sliders for this GUI
        comboboxes = {},  -- Store comboboxes for this GUI
        keybinds = {},  -- Store keybinds for this GUI
        colorpickers = {},  -- Store color pickers for this GUI
        text_inputs = {},  -- Store text inputs for this GUI
        headers = {},  -- Store headers for this GUI
        tree_nodes = {},  -- Store tree nodes for this GUI
        key_checkboxes = {},  -- Store key checkboxes for this GUI
        menu_components = {},  -- Store actual menu components
        component_counter = 0,  -- For unique IDs
        unique_plugin_key = unique_plugin_key,  -- Unique identifier for this plugin
        save_data = {},  -- Store saved component values
        auto_save_enabled = true  -- Enable automatic saving by default
    }, Menu)
    
    -- Calculate position for this GUI centered on the actual screen
    local screen_size = core.graphics.get_screen_size()
    -- Center horizontally on screen, position close to navbar
    gui.x_offset = (screen_size.x - gui.width) / 2
    gui.y_offset = 38  -- Position close to navbar (28px navbar + 10px gap)
    
    -- Register the GUI
    constants.registered_guis[name] = gui
    constants.gui_states[name] = core.menu.checkbox(true, "lx_gui_enabled_" .. name:lower():gsub("%s+", "_"))
    
    -- Load saved data for this GUI
    gui:LoadSavedData()
    
    return gui
end

function Menu:set_render_callback(callback)
    self.render_callback = callback
end

-- Helper function to generate unique IDs
function Menu:generate_id(prefix)
    self.component_counter = self.component_counter + 1
    return string.format("%s_%s_%d", self.name:lower():gsub("%s+", "_"), prefix, self.component_counter)
end

-- Helper function to calculate proper Y spacing for keybinds
-- Returns the Y position for the next keybind based on how many already exist
function Menu:GetNextKeybindY(start_y)
    start_y = start_y or 10
    local keybind_spacing = 50  -- Proper spacing between keybinds (matches rendering.lua spacing)
    return start_y + (#self.keybinds * keybind_spacing)
end

function Menu:AddLabel(text, x, y, options)
    options = options or {}
    
    -- Support legacy color parameter
    local text_color = options.color or options or color.white(255)
    
    -- Enhanced label with awesome features
    local label = {
        -- Basic properties
        text = text,
        x = x,
        y = y,
        color = text_color,
        
        -- Visual effects
        font_size = options.font_size or constants.FONT_SIZE,
        outline = options.outline ~= false, -- Default true
        outline_color = options.outline_color or color.new(0, 0, 0, 255),
        
        -- Background options
        background = options.background or false,
        bg_color = options.bg_color or color.new(20, 20, 30, 180),
        bg_padding = options.bg_padding or 5,
        
        -- Animation effects
        animation = options.animation or "none", -- "none", "pulse", "fade", "rainbow", "glow"
        animation_speed = options.animation_speed or 2.0,
        animation_time = 0,
        
        -- Interactive features
        clickable = options.clickable or false,
        click_callback = options.click_callback,
        hover_color = options.hover_color,
        
        -- Special effects
        shadow = options.shadow or false,
        shadow_color = options.shadow_color or color.new(0, 0, 0, 100),
        shadow_offset = options.shadow_offset or {x = 2, y = 2},
        
        -- Dynamic content
        dynamic = options.dynamic or false,
        update_callback = options.update_callback, -- Function that returns new text
        
        -- Layout options
        align = options.align or "left", -- "left", "center", "right"
        max_width = options.max_width,
        
        -- Status tracking
        is_hovered = false
    }
    
    table.insert(self.labels, label)
    return label -- Return reference for dynamic updates
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

function Menu:AddCheckbox(text, x, y, default_state, callback, options)
    options = options or {}
    
    -- Create unique ID for this checkbox
    local checkbox_id = options.id or self:generate_id("checkbox")
    
    -- Load saved checkbox state (only if auto_save is enabled for this component)
    local saved_state = default_state or false
    if options.auto_save ~= false then  -- Default to true unless explicitly disabled
        saved_state = self:LoadComponentValue("checkbox", checkbox_id, default_state or false)
        core.log("DEBUG: Loaded checkbox '" .. text .. "' state: " .. tostring(saved_state))
    end
    
    -- Create the actual menu checkbox
    local menu_checkbox = core.menu.checkbox(saved_state, checkbox_id)
    
    -- Store the checkbox info
    local checkbox_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_checkbox,
        callback = callback,
        id = checkbox_id,
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255),
        auto_save = options.auto_save ~= false,  -- Default to true unless explicitly disabled
        last_state = saved_state,  -- Track last state to detect changes
        gui_ref = self  -- Reference to GUI for saving
    }
    
    table.insert(self.checkboxes, checkbox_info)
    self.menu_components[checkbox_id] = menu_checkbox
    
    return checkbox_info
end

function Menu:AddSliderInt(text, x, y, min_value, max_value, default_value, callback, options)
    options = options or {}
    
    -- Create unique ID for this slider
    local slider_id = options.id or self:generate_id("slider_int")
    
    -- Create the actual menu slider
    local menu_slider = core.menu.slider_int(min_value, max_value, default_value, slider_id)
    
    -- Store the slider info
    local slider_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_slider,
        callback = callback,
        id = slider_id,
        min_value = min_value,
        max_value = max_value,
        default_value = default_value,
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.sliders_int, slider_info)
    self.menu_components[slider_id] = menu_slider
    
    return slider_info
end

function Menu:AddSliderFloat(text, x, y, min_value, max_value, default_value, callback, options)
    options = options or {}
    
    -- Create unique ID for this slider
    local slider_id = options.id or self:generate_id("slider_float")
    
    -- Create the actual menu slider
    local menu_slider = core.menu.slider_float(min_value, max_value, default_value, slider_id)
    
    -- Store the slider info
    local slider_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_slider,
        callback = callback,
        id = slider_id,
        min_value = min_value,
        max_value = max_value,
        default_value = default_value,
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.sliders_float, slider_info)
    self.menu_components[slider_id] = menu_slider
    
    return slider_info
end

function Menu:AddCombobox(text, x, y, items, default_index, callback, options)
    options = options or {}
    
    -- Create unique ID for this combobox
    local combo_id = options.id or self:generate_id("combobox")
    
    -- Load saved combobox selection (only if auto_save is enabled for this component)
    local saved_index = default_index or 1
    if options.auto_save ~= false then  -- Default to true unless explicitly disabled
        saved_index = self:LoadComponentValue("combobox", combo_id, default_index or 1)
        core.log("DEBUG: Loaded combobox '" .. text .. "' selection: " .. tostring(saved_index))
    end
    
    -- Create the actual menu combobox with saved selection
    local menu_combo = core.menu.combobox(saved_index, combo_id)
    
    -- Store the combobox info
    local combo_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_combo,
        callback = callback,
        id = combo_id,
        items = items or {},
        default_index = default_index or 1,
        selected_index = saved_index,  -- Track current selection
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255),
        auto_save = options.auto_save ~= false,  -- Default to true unless explicitly disabled
        last_selection = saved_index,  -- Track last selection to detect changes
        gui_ref = self  -- Reference to GUI for saving
    }
    
    table.insert(self.comboboxes, combo_info)
    self.menu_components[combo_id] = menu_combo
    
    return combo_info
end

-- Add an interactive keybind setup field with full functionality
-- text: Label text for the keybind
-- x, y: Position coordinates
-- default_key: Default key code (0 for none)
-- callback: Function called when key is changed: callback(new_key_code)
-- options: Table with optional parameters:
--   - width, height: Keybind field dimensions
--   - text_color: Color of the text
--   - initial_toggle_state: Initial toggle state for the keybind
--   - show_visibility_option: Whether to show the visibility dropdown (default: true)
--
-- Features:
--   - Click to enter listening mode (blue highlight)
--   - Press any key to assign (automatic detection)
--   - Clear button (X) to remove keybind
--   - Proper key name display (F1, Space, etc.)
--   - Visibility dropdown: None, On Active, Permanent
--   - Conflict detection and timeout (5 seconds)
--   - Game input blocking while listening (uses core.input.disable_movement())
--   - Visual feedback for all states
function Menu:AddKeybind(text, x, y, default_key, callback, options)
    options = options or {}
    
    -- Create unique ID for this keybind
    local keybind_id = options.id or self:generate_id("keybind")
    
    -- Create the actual menu keybind
    local menu_keybind = core.menu.keybind(default_key or 0, options.initial_toggle_state or false, keybind_id)
    
    -- Create visibility combobox if key is set and option is enabled
    local visibility_combo = nil
    if options.show_visibility_option ~= false then
        local visibility_id = keybind_id .. "_visibility"
        visibility_combo = core.menu.combobox(1, visibility_id) -- Default to "None"
    end
    
    -- Load saved values
    local saved_key = self:LoadComponentValue("keybind_key", keybind_id, default_key or 0)
    local saved_visibility = self:LoadComponentValue("keybind_visibility", keybind_id, 1)
    
    -- Apply saved key to the menu component
    if saved_key ~= (default_key or 0) then
        core.log("DEBUG: Applying saved key " .. saved_key .. " to keybind " .. keybind_id)
        menu_keybind:set_key(saved_key)
    end
    
    -- Apply saved visibility to the visibility combobox
    if visibility_combo and saved_visibility ~= 1 then
        core.log("DEBUG: Applying saved visibility " .. saved_visibility .. " to keybind " .. keybind_id)
        visibility_combo:set(saved_visibility)
    end
    
    -- Store the keybind info
    local keybind_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_keybind,
        callback = callback,
        id = keybind_id,
        default_key = default_key or 0,
        current_key = saved_key,  -- Load saved key
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255),
        show_visibility_option = options.show_visibility_option ~= false,
        visibility_combo = visibility_combo,
        visibility_options = {"None", "On Active", "Permanent"},
        current_visibility = saved_visibility, -- Load saved visibility
        visibility_callback = options.visibility_callback,
        gui_ref = self  -- Reference to GUI for saving
    }
    
    table.insert(self.keybinds, keybind_info)
    self.menu_components[keybind_id] = menu_keybind
    if visibility_combo then
        self.menu_components[keybind_id .. "_visibility"] = visibility_combo
    end
    
    return keybind_info
end

function Menu:AddColorPicker(text, x, y, default_color, callback, options)
    options = options or {}
    
    -- Create unique ID for this color picker
    local colorpicker_id = options.id or self:generate_id("colorpicker")
    
    -- Load saved color value (only if auto_save is enabled for this component)
    local saved_color = color.new(r, g, b, a)  -- Use extracted RGBA values
    
    -- Color parsing successful, debug output removed
    
    -- Extract RGBA from color object (handle both .r/.g/.b/.a format and .value format)
    local r, g, b, a = 0, 0, 0, 255
    if default_color then
        if default_color.r and default_color.g and default_color.b then
            -- Standard RGBA format
            r, g, b = default_color.r, default_color.g, default_color.b
            a = default_color.a or 255
        elseif default_color.value then
            -- Packed color value format - need to unpack it
            local value = default_color.value
            if value == -1 then
                -- -1 typically means white (0xFFFFFFFF)
                r, g, b, a = 255, 255, 255, 255
            else
                -- Unpack the color value (assuming ARGB format)
                a = math.floor(value / 16777216) % 256
                r = math.floor(value / 65536) % 256
                g = math.floor(value / 256) % 256
                b = value % 256
                
                -- Handle negative values (convert from signed to unsigned)
                if a < 0 then a = a + 256 end
                if r < 0 then r = r + 256 end
                if g < 0 then g = g + 256 end
                if b < 0 then b = b + 256 end
            end
        end
    end
    

    if options.auto_save ~= false then  -- Default to true unless explicitly disabled
        local saved_color_str = self:LoadComponentValue("colorpicker", colorpicker_id, nil)
        if saved_color_str and type(saved_color_str) == "string" then
            -- Parse color string "r,g,b,a"
            local saved_r, saved_g, saved_b, saved_a = saved_color_str:match("([^,]+),([^,]+),([^,]+),([^,]+)")
            if saved_r and saved_g and saved_b and saved_a then
                local parsed_r = tonumber(saved_r)
                local parsed_g = tonumber(saved_g)
                local parsed_b = tonumber(saved_b)
                local parsed_a = tonumber(saved_a)
                
                -- Ensure all values are valid numbers
                if parsed_r and parsed_g and parsed_b and parsed_a then
                    saved_color = color.new(parsed_r, parsed_g, parsed_b, parsed_a)

                else
                    core.log("DEBUG: Invalid color values in saved string: " .. saved_color_str)
                    saved_color = color.new(r, g, b, a)
                end
            else
                core.log("DEBUG: Failed to parse color string: " .. saved_color_str)
                saved_color = color.new(r, g, b, a)
            end
        end
        
        -- Final fallback to ensure we always have a valid color
        if not saved_color then
            saved_color = color.new(r, g, b, a)
        end
    end
    
    -- Create the actual menu color picker
    local menu_colorpicker = core.menu.colorpicker(saved_color, colorpicker_id)
    
    -- Store the color picker info
    local colorpicker_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_colorpicker,
        callback = callback,
        id = colorpicker_id,
        default_color = color.new(r, g, b, a),
        current_color = saved_color,  -- Load saved color
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255),
        auto_save = options.auto_save ~= false,  -- Default to true unless explicitly disabled
        last_color = saved_color,  -- Track last color to detect changes
        gui_ref = self  -- Reference to GUI for saving
    }
    

    
    table.insert(self.colorpickers, colorpicker_info)
    self.menu_components[colorpicker_id] = menu_colorpicker
    
    -- Save initial color value if auto-save is enabled and no existing saved data
    if colorpicker_info.auto_save then
        local existing_save = self:LoadComponentValue("colorpicker", colorpicker_id, nil)
        if not existing_save then
            -- Only save if there's no existing saved data
            local color_str = r .. "," .. g .. "," .. b .. "," .. a
            self:SaveComponentValue("colorpicker", colorpicker_id, color_str)
            -- Initial value saved
        else
            -- Existing data found, skipping initial save
        end
    end
    
    return colorpicker_info
end

-- Add a text input field with advanced features
-- text: Label text for the input
-- x, y: Position coordinates
-- default_text: Text that appears in the field initially and gets cleared on first focus
-- callback: Function called when text changes
-- options: Table with optional parameters:
--   - placeholder: Grayed-out text shown when field is empty and unfocused
--   - width, height: Input field dimensions
--   - text_color: Color of the text
--   - save_input: Whether to persist input across sessions (default: true)
-- 
-- Features:
--   - Automatic game input blocking when focused (uses core.input.disable_movement())
--   - Double-click to select all text
--   - Click positioning for cursor placement
--   - Full keyboard support with arrow keys, home/end, delete, backspace
--   - Key repeat functionality - hold keys for continuous action (backspace, delete, arrows)
--   - Visual text selection with highlighting
--   - Default text that clears on first edit
--   - Placeholder text when empty
function Menu:AddTextInput(text, x, y, default_text, callback, options)
    options = options or {}
    
    -- Create unique ID for this text input
    local textinput_id = options.id or self:generate_id("textinput")
    
    -- Load saved text value (only if auto_save is enabled for this component)
    local saved_text = default_text or ""
    if options.auto_save == true then  -- Default to false unless explicitly enabled
        saved_text = self:LoadComponentValue("text_input", textinput_id, default_text or "")
    end
    
    -- Create the actual menu text input
    local menu_textinput = core.menu.text_input(textinput_id, options.save_input ~= true)
    
    -- Apply saved text to the component if auto_save is enabled
    if options.auto_save == true and saved_text ~= (default_text or "") then
        core.log("DEBUG: Applying saved text '" .. saved_text .. "' to text input " .. textinput_id)
        menu_textinput:set(saved_text)
    end
    
    -- Store the text input info
    local textinput_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_textinput,
        callback = callback,
        id = textinput_id,
        default_text = default_text or "",
        current_text = saved_text,  -- Load saved text
        placeholder = options.placeholder or "",
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255),
        auto_save = options.auto_save == true,  -- Default to false unless explicitly enabled
        last_text = saved_text,  -- Track last text to detect changes
        gui_ref = self  -- Reference to GUI for saving
    }
    
    table.insert(self.text_inputs, textinput_info)
    self.menu_components[textinput_id] = menu_textinput
    
    return textinput_info
end

function Menu:AddHeader(text, x, y, options)
    options = options or {}
    
    -- Create unique ID for this header
    local header_id = options.id or self:generate_id("header")
    
    -- Create the actual menu header
    local menu_header = core.menu.header()
    
    -- Store the header info
    local header_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_header,
        id = header_id,
        width = options.width or 200,
        height = options.height or 25,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.headers, header_info)
    self.menu_components[header_id] = menu_header
    
    return header_info
end

function Menu:AddTreeNode(text, x, y, render_callback, options)
    options = options or {}
    
    -- Create unique ID for this tree node
    local treenode_id = options.id or self:generate_id("treenode")
    
    -- Create the actual menu tree node
    local menu_treenode = core.menu.tree_node()
    
    -- Store the tree node info
    local treenode_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_treenode,
        render_callback = render_callback,
        id = treenode_id,
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.tree_nodes, treenode_info)
    self.menu_components[treenode_id] = menu_treenode
    
    return treenode_info
end

function Menu:AddKeyCheckbox(text, x, y, default_key, default_state, callback, options)
    options = options or {}
    
    -- Create unique ID for this key checkbox
    local keycheckbox_id = options.id or self:generate_id("keycheckbox")
    
    -- Create the actual menu key checkbox
    local menu_keycheckbox = core.menu.key_checkbox(
        default_key or 0,
        options.initial_toggle_state or false,
        default_state or false,
        options.show_in_binds ~= false,
        options.default_mode_state or 0,
        keycheckbox_id
    )
    
    -- Store the key checkbox info
    local keycheckbox_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_keycheckbox,
        callback = callback,
        id = keycheckbox_id,
        default_key = default_key or 0,
        default_state = default_state or false,
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.key_checkboxes, keycheckbox_info)
    self.menu_components[keycheckbox_id] = menu_keycheckbox
    
    return keycheckbox_info
end

function Menu:AddImage(image_data, x, y, width, height, options)
    options = options or {}
    
    -- Check if image drawing is supported
    if not core.graphics.draw_image then
        core.log("Warning: Image drawing not supported in this environment. Skipping image.")
        return nil
    end
    
    -- Image data can be base64 string or image object
    local image_object = image_data
    if type(image_data) == "string" then
        -- Assume it's base64 data - store as is for now
        image_object = image_data
    end
    
    -- Create image object
    local image = {
        image_object = image_object,
        x = x,
        y = y,
        width = width or nil,  -- nil means use original size
        height = height or nil, -- nil means use original size
        
        -- Optional features
        clickable = options.clickable or false,
        click_callback = options.click_callback,
        hover_scale = options.hover_scale or 1.1,
        rotation = options.rotation or 0,
        alpha = options.alpha or 1.0,
        
        -- Status tracking
        is_hovered = false
    }
    
    table.insert(self.images, image)
    return image -- Return reference for dynamic updates
end

-- Helper functions to get component values
function Menu:GetCheckboxValue(checkbox_info)
    if checkbox_info and checkbox_info.menu_component then
        return checkbox_info.menu_component:get_state()
    end
    return false
end

function Menu:GetSliderIntValue(slider_info)
    if slider_info and slider_info.menu_component then
        return slider_info.menu_component:get_state()
    end
    return 0
end

function Menu:GetSliderFloatValue(slider_info)
    if slider_info and slider_info.menu_component then
        return slider_info.menu_component:get_state()
    end
    return 0.0
end

function Menu:GetComboboxValue(combo_info)
    if combo_info and combo_info.menu_component then
        return combo_info.menu_component:get_state()
    end
    return 1
end

function Menu:GetKeybindValue(keybind_info)
    if keybind_info and keybind_info.menu_component then
        return keybind_info.menu_component:get_state()
    end
    return 0
end

-- Get the current key code from a keybind (including any user changes)
function Menu:GetKeybindCurrentKey(keybind_info)
    if keybind_info then
        return keybind_info.current_key or keybind_info.default_key or 0
    end
    return 0
end

-- Check if a keybind is currently being listened to
function Menu:IsKeybindListening(keybind_info)
    if keybind_info then
        return keybind_info.is_listening or false
    end
    return false
end

-- Programmatically set a keybind's key (useful for loading saved settings)
function Menu:SetKeybindKey(keybind_info, key_code)
    if keybind_info then
        keybind_info.current_key = key_code or 0
        if keybind_info.callback then
            keybind_info.callback(key_code or 0)
        end
    end
end

-- Get the current visibility setting for a keybind
function Menu:GetKeybindVisibility(keybind_info)
    if keybind_info and keybind_info.visibility_combo then
        return keybind_info.visibility_combo:get_state()
    end
    return 1 -- Default to "None"
end

-- Set the visibility setting for a keybind
function Menu:SetKeybindVisibility(keybind_info, visibility_index)
    if keybind_info and keybind_info.visibility_combo then
        keybind_info.current_visibility = visibility_index or 1
        if keybind_info.visibility_callback then
            keybind_info.visibility_callback(visibility_index or 1)
        end
    end
end

-- Get the visibility option name for a keybind
function Menu:GetKeybindVisibilityName(keybind_info)
    if keybind_info and keybind_info.visibility_options then
        local index = keybind_info.current_visibility or 1
        return keybind_info.visibility_options[index] or "None"
    end
    return "None"
end

function Menu:GetColorPickerValue(colorpicker_info)
    if colorpicker_info and colorpicker_info.menu_component then
        return colorpicker_info.menu_component:get_state()
    end
    return color.white(255)
end

function Menu:GetTextInputValue(textinput_info)
    if textinput_info and textinput_info.menu_component then
        return textinput_info.menu_component:get_state()
    end
    return ""
end

function Menu:GetKeyCheckboxValue(keycheckbox_info)
    if keycheckbox_info and keycheckbox_info.menu_component then
        return keycheckbox_info.menu_component:get_state()
    end
    return false
end

function Menu:toggle()
    self.is_open = not self.is_open
end

-- ==================== SAVE/LOAD SYSTEM ====================

-- Generate a unique save key for a component
function Menu:GenerateSaveKey(component_type, component_id)
    return string.format("%s_%s_%s", self.unique_plugin_key, component_type, component_id)
end

-- Generate filename for saving data
function Menu:GenerateSaveFilename()
    local filename = "lxcommon_" .. self.unique_plugin_key .. ".dat"

    return filename
end

-- Save all data to file
function Menu:SaveDataToFile()
    if not self.auto_save_enabled then 
        core.log("DEBUG: Auto-save disabled for GUI: " .. self.name)
        return 
    end
    
    local filename = self:GenerateSaveFilename()
    -- Convert save_data table to a simple string format
    local data_lines = {}
    for key, value in pairs(self.save_data) do
        -- Simple key=value format, handling different types
        local value_str
        if type(value) == "boolean" then
            value_str = value and "true" or "false"
        elseif type(value) == "number" then
            value_str = tostring(value)
        elseif type(value) == "string" then
            value_str = value
        else
            value_str = tostring(value)
        end
        table.insert(data_lines, key .. "=" .. value_str)
    end
    
    local data_string = table.concat(data_lines, "\n")
    
    -- Create file first, then write to it using core API
    core.create_data_file(filename)
    core.write_data_file(filename, data_string)
end

-- Load all data from file
function Menu:LoadDataFromFile()
    if not self.auto_save_enabled then 
        core.log("DEBUG: Auto-save disabled for GUI: " .. self.name .. ", skipping load")
        return 
    end
    
    local filename = self:GenerateSaveFilename()
    core.log("DEBUG: Loading data from file: " .. filename)
    
    -- Read from file using core API
    local data_string = core.read_data_file(filename)
    core.log("DEBUG: Read data string length: " .. (data_string and string.len(data_string) or 0))
    
    if data_string and data_string ~= "" then
        -- Parse the data string
        for line in data_string:gmatch("[^\r\n]+") do
            local key, value = line:match("^(.-)=(.*)$")
            if key and value then
                -- Convert value back to appropriate type
                if value == "true" then
                    self.save_data[key] = true
                elseif value == "false" then
                    self.save_data[key] = false
                elseif tonumber(value) then
                    self.save_data[key] = tonumber(value)
                else
                    self.save_data[key] = value
                end
                core.log("DEBUG: Loaded key=" .. key .. " value=" .. tostring(self.save_data[key]))
            end
        end
        core.log("Loaded saved data for GUI: " .. self.name .. " (Key: " .. self.unique_plugin_key .. ")")
    else
        core.log("DEBUG: No data found in file: " .. filename)
    end
end

-- Save a component's value
function Menu:SaveComponentValue(component_type, component_id, value)
    core.log("DEBUG: SaveComponentValue called - type=" .. component_type .. " id=" .. component_id .. " value=" .. tostring(value))
    
    if not self.auto_save_enabled then 
        core.log("DEBUG: Auto-save disabled, not saving")
        return 
    end
    
    local save_key = self:GenerateSaveKey(component_type, component_id)
    core.log("DEBUG: Generated save key: " .. save_key)
    self.save_data[save_key] = value
    
    -- Save to file immediately for persistence
    self:SaveDataToFile()
    
    core.log("Saved " .. component_type .. " '" .. component_id .. "' = " .. tostring(value))
end

-- Load a component's value
function Menu:LoadComponentValue(component_type, component_id, default_value)
    local save_key = self:GenerateSaveKey(component_type, component_id)
    
    -- Check if we have it in memory
    local saved_value = self.save_data[save_key]
    return saved_value ~= nil and saved_value or default_value
end

-- Load all saved data for this GUI
function Menu:LoadSavedData()
    if not self.auto_save_enabled then return end
    
    -- Load data from file
    self:LoadDataFromFile()
    
    core.log("Loading saved data for GUI: " .. self.name .. " (Key: " .. self.unique_plugin_key .. ")")
end

-- Clear all saved data for this GUI
function Menu:ClearSavedData()
    self.save_data = {}
    
    -- Clear the file as well
    local filename = self:GenerateSaveFilename()
    core.write_data_file(filename, "")
    
    core.log("Cleared all saved data for GUI: " .. self.name)
end

-- Enable/disable auto-save
function Menu:SetAutoSave(enabled)
    self.auto_save_enabled = enabled
    core.log("Auto-save " .. (enabled and "enabled" or "disabled") .. " for GUI: " .. self.name)
end

-- Export the Menu class
return {
    Menu = Menu
} 