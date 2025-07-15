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

-- ==================== GUI SETUP ====================
local demo_gui = nil

if lx then
    -- Create a clean debug GUI
    demo_gui = lx.Gui.register("LX Debug", 600, 500, "lx_debug_gui")
    
    -- Header
    demo_gui:AddLabel("LX Debug Panel - Listbox Component Testing", 10, 10, color.white(255))
    demo_gui:AddLabel("Ready for testing...", 10, 35, color.gray(200))
    
    -- Debug controls
    demo_gui:AddCheckbox("Enable Debug Mode", 10, 60, Settings.debug_mode, function(value)
        Settings.debug_mode = value
        core.log("Debug mode: " .. tostring(value))
    end)
    
    -- ==================== LISTBOX DEMOS ====================
    demo_gui:AddLabel("=== LISTBOX DEMONSTRATIONS ===", 10, 90, color.cyan(255))
    demo_gui:AddLabel("Scrolling: Page Up/Down, Arrow keys (when focused), or drag scrollbar", 10, 105, color.yellow(200))
    
    -- Basic single-select listbox
    local basic_items = {"Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape", "Honeydew"}
    local basic_listbox = demo_gui:AddListbox("Single-Select Fruits", 10, 140, basic_items, 1, function(index, item)
        core.log("Selected fruit: " .. (item or "None") .. " (index: " .. index .. ")")
        Settings.test_values.selected_fruit = item
    end, {
        width = 150,
        height = 120,
        visible_items = 6
    })
    
    -- Multi-select listbox
    local colors = {"Red", "Green", "Blue", "Yellow", "Purple", "Orange", "Pink", "Cyan", "Magenta", "Brown"}
    local multi_listbox = demo_gui:AddListbox("Multi-Select Colors", 180, 140, colors, 0, function(selected_items)
        if type(selected_items) == "table" and #selected_items > 0 then
            local selected_names = {}
            for _, selection in ipairs(selected_items) do
                table.insert(selected_names, selection.item)
            end
            core.log("Selected colors: " .. table.concat(selected_names, ", "))
        else
            core.log("No colors selected")
        end
    end, {
        width = 150,
        height = 120,
        visible_items = 6,
        multi_select = true
    })
    
    -- Scrollable listbox with many items
    local large_list = {}
    for i = 1, 50 do
        table.insert(large_list, "Item " .. i)
    end
    local scroll_listbox = demo_gui:AddListbox("Scrollable List", 350, 140, large_list, 5, function(index, item)
        core.log("Scrollable list selection: " .. (item or "None"))
        Settings.test_values.scroll_item = item
    end, {
        width = 150,
        height = 100,
        visible_items = 5
    })
    
    -- Dynamic listbox with controls
    local dynamic_items = {"Dynamic Item 1", "Dynamic Item 2"}
    local dynamic_listbox = demo_gui:AddListbox("Dynamic List", 10, 280, dynamic_items, 0, function(index, item)
        core.log("Dynamic list selection: " .. (item or "None"))
    end, {
        width = 200,
        height = 80,
        visible_items = 4
    })
    
    -- Control buttons for dynamic listbox
    demo_gui:AddButton("Add Item", 220, 280, 80, 25, function()
        local new_item = "Item " .. (#dynamic_listbox.items + 1)
        demo_gui:AddListboxItems(dynamic_listbox, {new_item})
        core.log("Added: " .. new_item)
    end)
    
    demo_gui:AddButton("Clear All", 310, 280, 80, 25, function()
        demo_gui:ClearListbox(dynamic_listbox)
        core.log("Cleared dynamic listbox")
    end)
    
    demo_gui:AddButton("Select Item 2", 220, 310, 80, 25, function()
        if #dynamic_listbox.items >= 2 then
            demo_gui:SetListboxSelection(dynamic_listbox, 2)
            core.log("Programmatically selected item 2")
        end
    end)
    
    -- Instructions
    demo_gui:AddLabel("Instructions:", 10, 350, color.yellow(255))
    demo_gui:AddLabel("- Click items to select them", 10, 370, color.white(200))
    demo_gui:AddLabel("- Multi-select: Click normally or Ctrl+Click to toggle items", 10, 390, color.white(200))
    demo_gui:AddLabel("- Scrollable: Drag scrollbar, arrow keys, Page Up/Down", 10, 410, color.white(200))
    demo_gui:AddLabel("- Focus: Click a listbox to enable keyboard navigation (blue border)", 10, 430, color.white(200))
    demo_gui:AddLabel("- All selections are auto-saved", 10, 450, color.white(200))
end

-- ==================== MENU ELEMENTS ====================
-- Clean template - add your menu elements here as needed

-- ==================== CORE FUNCTIONALITY ====================
-- Add your debug functions here

-- ==================== UPDATE CALLBACKS ====================
local function on_update()
    -- Add update logic here if needed
end

-- ==================== RENDER CALLBACKS ====================
local function on_render()
    -- Add render logic here if needed
end

-- ==================== MENU CALLBACK ====================
local function on_render_menu()
    -- Add menu rendering here if needed
end

-- ==================== REGISTER CALLBACKS ====================
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)
