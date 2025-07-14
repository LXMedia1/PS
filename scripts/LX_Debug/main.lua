-- ==================== IMPORTS ====================
---@type color
local color = require("common/color")
---@type vec2
local vec2 = require("common/geometry/vector_2")

-- Import LxCommon GUI system
local lx = _G.LxCommon

-- ==================== DEBUG SETTINGS ====================
local Settings = {
    debug_mode = true,
    verbose_logging = false,
    test_values = {}
}

-- ==================== COMPREHENSIVE GUI DEMO ====================
local demo_gui = nil

if lx then
    -- ==================== MAIN DEMO GUI ====================
    demo_gui = lx.Gui.register("GUI Component Demo", 800, 800)
    
    -- Add title
    demo_gui:AddLabel("=== COMPREHENSIVE GUI DEMO ===", 10, 10, color.orange(255))
    demo_gui:AddLabel("Showcasing all available GUI components", 10, 35, color.white(255))
    
    -- ==================== LEFT COLUMN ====================
    demo_gui:AddLabel("← Left Column", 10, 50, color.cyan(255))
    -- ==================== CHECKBOXES ====================
    demo_gui:AddHeader("Checkboxes", 10, 70)
    
    local checkbox1 = demo_gui:AddCheckbox("Enable Debug Mode", 10, 100, true, function(value)
        Settings.debug_mode = value
        core.log("Debug mode: " .. tostring(value))
    end)
    
    local checkbox2 = demo_gui:AddCheckbox("Verbose Logging", 10, 125, false, function(value)
        Settings.verbose_logging = value
        core.log("Verbose logging: " .. tostring(value))
    end)
    
    -- ==================== SLIDERS ====================
    demo_gui:AddHeader("Sliders", 10, 160)
    
    local slider_int = demo_gui:AddSliderInt("Integer Value", 10, 190, 0, 100, 50, function(value)
        Settings.test_values.int_value = value
        core.log("Integer slider: " .. tostring(value))
    end)
    
    local slider_float = demo_gui:AddSliderFloat("Float Value", 10, 220, 0.0, 1.0, 0.5, function(value)
        Settings.test_values.float_value = value
        core.log("Float slider: " .. string.format("%.2f", value))
    end)
    
    -- ==================== COMBOBOXES ====================
    demo_gui:AddHeader("Comboboxes", 10, 260)
    
    local combo_items = {"Option 1", "Option 2", "Option 3", "Option 4"}
    local combo1 = demo_gui:AddCombobox("Select Option", 10, 290, combo_items, 1, function(value)
        Settings.test_values.selected_option = value
        core.log("Selected option: " .. tostring(value) .. " (" .. (combo_items[value] or "Unknown") .. ")")
    end)
    
    -- ==================== RIGHT COLUMN ====================
    -- Visual separator
    demo_gui:AddLabel("|", 305, 70, color.gray(100))
    demo_gui:AddLabel("|", 305, 90, color.gray(100))
    demo_gui:AddLabel("|", 305, 110, color.gray(100))
    demo_gui:AddLabel("|", 305, 130, color.gray(100))
    demo_gui:AddLabel("|", 305, 150, color.gray(100))
    demo_gui:AddLabel("|", 305, 170, color.gray(100))
    demo_gui:AddLabel("|", 305, 190, color.gray(100))
    demo_gui:AddLabel("|", 305, 210, color.gray(100))
    demo_gui:AddLabel("|", 305, 230, color.gray(100))
    demo_gui:AddLabel("|", 305, 250, color.gray(100))
    demo_gui:AddLabel("|", 305, 270, color.gray(100))
    demo_gui:AddLabel("|", 305, 290, color.gray(100))
    demo_gui:AddLabel("|", 305, 310, color.gray(100))
    
    demo_gui:AddLabel("Right Column →", 320, 50, color.cyan(255))
    -- ==================== KEYBINDS ====================
    demo_gui:AddHeader("Keybinds", 320, 70)
    
    -- Advanced keybind setup with full features
    local keybind1 = demo_gui:AddKeybind("Primary Action", 320, 100, 0x47, function(key) -- 'G' key default
        Settings.test_values.primary_key = key
        core.log("Primary Action keybind set to: " .. tostring(key))
    end)
    
    local keybind2 = demo_gui:AddKeybind("Secondary Action", 320, 130, 0x48, function(key) -- 'H' key default
        Settings.test_values.secondary_key = key
        core.log("Secondary Action keybind set to: " .. tostring(key))
    end)
    
    local keybind3 = demo_gui:AddKeybind("Modifier Key", 320, 160, 0x10, function(key) -- Shift key default
        Settings.test_values.modifier_key = key
        core.log("Modifier Key keybind set to: " .. tostring(key))
    end)
    
    local keybind4 = demo_gui:AddKeybind("Unassigned Key", 320, 190, 0, function(key) -- No default
        Settings.test_values.unassigned_key = key
        core.log("Unassigned Key keybind set to: " .. tostring(key))
    end)
    
    -- Add instructions
    demo_gui:AddLabel("Instructions:", 320, 225, color.yellow(255))
    demo_gui:AddLabel("• Click on any keybind to start listening", 320, 245, color.white(200))
    demo_gui:AddLabel("• Press any key to assign it", 320, 265, color.white(200))
    demo_gui:AddLabel("• Click 'X' to clear a keybind", 320, 285, color.white(200))
    demo_gui:AddLabel("• Listening times out after 5 seconds", 320, 305, color.white(200))
    
    -- ==================== COLOR PICKERS ====================
    demo_gui:AddHeader("Color Pickers", 320, 340)
    
    local colorpicker1 = demo_gui:AddColorPicker("Text Color", 320, 370, color.white(255), function(selected_color)
        Settings.test_values.text_color = selected_color
        core.log("Text color changed")
    end)
    
    local colorpicker2 = demo_gui:AddColorPicker("Background Color", 320, 400, color.new(50, 50, 50, 255), function(selected_color)
        Settings.test_values.bg_color = selected_color
        core.log("Background color changed")
    end)
    
    -- ==================== TEXT INPUTS ====================
    demo_gui:AddHeader("Text Inputs", 320, 440)
    
    local textinput1 = demo_gui:AddTextInput("Name", 320, 470, "Enter your name", function(text)
        Settings.test_values.name = text
        core.log("Name changed to: " .. tostring(text))
    end)
    
    local textinput2 = demo_gui:AddTextInput("Notes", 320, 500, "Additional notes", function(text)
        Settings.test_values.notes = text
        core.log("Notes updated")
    end)
    
    -- ==================== KEY CHECKBOXES ====================
    demo_gui:AddHeader("Key Checkboxes", 320, 540)
    
    local key_checkbox1 = demo_gui:AddKeyCheckbox("Toggle Feature", 320, 570, 0x54, true, function(value) -- 'T' key
        Settings.test_values.toggle_feature = value
        core.log("Toggle feature: " .. tostring(value))
    end)
    
    -- ==================== BOTTOM SECTION - ADVANCED FEATURES ====================
    demo_gui:AddHeader("Advanced Features", 10, 340)
    
    -- Tree node example
    local tree_node1 = demo_gui:AddTreeNode("Advanced Settings", 10, 370, function()
        -- This would render child elements inside the tree node
        core.log("Tree node expanded")
    end)
    
    -- Dynamic buttons with value display
    demo_gui:AddButton("Get All Values", 10, 400, 150, 30, function()
        core.log("=== Current Values ===")
        core.log("Debug Mode: " .. tostring(Settings.debug_mode))
        core.log("Verbose Logging: " .. tostring(Settings.verbose_logging))
        
        if Settings.test_values.int_value then
            core.log("Integer: " .. tostring(Settings.test_values.int_value))
        end
        if Settings.test_values.float_value then
            core.log("Float: " .. string.format("%.2f", Settings.test_values.float_value))
        end
        if Settings.test_values.selected_option then
            core.log("Selected: " .. tostring(Settings.test_values.selected_option))
        end
        if Settings.test_values.name then
            core.log("Name: " .. tostring(Settings.test_values.name))
        end
        core.log("=== End Values ===")
    end)
    
    demo_gui:AddButton("Reset All", 170, 400, 150, 30, function()
        -- Reset all values to defaults
        Settings.test_values = {}
        core.log("All values reset to defaults")
    end)
    
    -- Status labels
    demo_gui:AddLabel("Status indicators:", 10, 440, color.cyan(255))
    demo_gui:AddLabel("• All components functional", 10, 465, color.green(255))
    demo_gui:AddLabel("• Callbacks working", 10, 490, color.green(255))
    demo_gui:AddLabel("• Values stored in Settings", 10, 515, color.green(255))

end

-- ==================== MENU ELEMENTS ====================
-- Clean template - add your menu elements here as needed

-- ==================== CORE FUNCTIONALITY ====================
-- Add your debug functions here

-- ==================== UPDATE CALLBACKS ====================
local function on_update()
    -- Add update logic here if needed
end

-- ==================== RENDER CALLBACK ====================
local function on_render()
    -- Add render logic here if needed
end

-- ==================== MENU CALLBACK ====================
local function on_render_menu()
    -- Add main menu controls here if needed
end

-- ==================== PLUGIN REGISTRATION ====================

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)

-- Load clean demo (no images)
require("demo_labels_no_images")

core.log("LX Debug plugin loaded successfully - Full GUI Demo Ready")
