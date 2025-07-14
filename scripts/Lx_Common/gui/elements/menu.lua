-- ==================== MENU CLASS ====================

local constants = require("gui/utils/constants")
local color = constants.color
local vec2 = constants.vec2

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
        component_counter = 0  -- For unique IDs
    }, Menu)
    
    -- Calculate position for this GUI centered on the actual screen
    local screen_size = core.graphics.get_screen_size()
    -- Center horizontally on screen, position close to navbar
    gui.x_offset = (screen_size.x - gui.width) / 2
    gui.y_offset = 38  -- Position close to navbar (28px navbar + 10px gap)
    
    -- Register the GUI
    constants.registered_guis[name] = gui
    constants.gui_states[name] = core.menu.checkbox(true, "lx_gui_enabled_" .. name:lower():gsub("%s+", "_"))
    
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
    
    -- Create the actual menu checkbox
    local menu_checkbox = core.menu.checkbox(default_state or false, checkbox_id)
    
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
        text_color = options.text_color or color.white(255)
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
    
    -- Create the actual menu combobox
    local menu_combo = core.menu.combobox(default_index or 1, combo_id)
    
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
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
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
--
-- Features:
--   - Click to enter listening mode (blue highlight)
--   - Press any key to assign (automatic detection)
--   - Clear button (X) to remove keybind
--   - Proper key name display (F1, Space, etc.)
--   - Conflict detection and timeout (5 seconds)
--   - Game input blocking while listening (uses core.input.disable_movement())
--   - Visual feedback for all states
function Menu:AddKeybind(text, x, y, default_key, callback, options)
    options = options or {}
    
    -- Create unique ID for this keybind
    local keybind_id = options.id or self:generate_id("keybind")
    
    -- Create the actual menu keybind
    local menu_keybind = core.menu.keybind(default_key or 0, options.initial_toggle_state or false, keybind_id)
    
    -- Store the keybind info
    local keybind_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_keybind,
        callback = callback,
        id = keybind_id,
        default_key = default_key or 0,
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.keybinds, keybind_info)
    self.menu_components[keybind_id] = menu_keybind
    
    return keybind_info
end

function Menu:AddColorPicker(text, x, y, default_color, callback, options)
    options = options or {}
    
    -- Create unique ID for this color picker
    local colorpicker_id = options.id or self:generate_id("colorpicker")
    
    -- Create the actual menu color picker
    local menu_colorpicker = core.menu.colorpicker(default_color or color.white(255), colorpicker_id)
    
    -- Store the color picker info
    local colorpicker_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_colorpicker,
        callback = callback,
        id = colorpicker_id,
        default_color = default_color or color.white(255),
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
    }
    
    table.insert(self.colorpickers, colorpicker_info)
    self.menu_components[colorpicker_id] = menu_colorpicker
    
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
    
    -- Create the actual menu text input
    local menu_textinput = core.menu.text_input(textinput_id, options.save_input ~= true)
    
    -- Store the text input info
    local textinput_info = {
        text = text,
        x = x,
        y = y,
        menu_component = menu_textinput,
        callback = callback,
        id = textinput_id,
        default_text = default_text or "",
        placeholder = options.placeholder or "",
        width = options.width or 200,
        height = options.height or 20,
        text_color = options.text_color or color.white(255)
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

-- Export the Menu class
return {
    Menu = Menu
} 