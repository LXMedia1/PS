-- ==================== LX COMMON GUI SYSTEM - MAIN ENTRY POINT ====================

-- Import all modules
local constants = require("gui/utils/constants")
local helpers = require("gui/utils/helpers")
local input = require("gui/functions/input")
local rendering = require("gui/functions/rendering")
local menu_module = require("gui/elements/menu")

-- Extract Menu class
local Menu = menu_module.Menu

-- ==================== MAIN MENU INTEGRATION ====================
local lx_guis_tree_node = core.menu.tree_node()
local lx_guis_checkbox = core.menu.checkbox(true, "lx_selection_bar_enabled")

-- ==================== UPDATE CALLBACK ====================
local function on_update()
    -- Update selection bar enabled state
    if lx_guis_checkbox then
        constants.selection_bar_enabled = lx_guis_checkbox:get_state()
    end
end

-- ==================== RENDER CALLBACK ====================
local function on_render()
    rendering.render_direct_gui()
end

-- ==================== MENU CALLBACK ====================
local function on_render_menu()
    lx_guis_tree_node:render("LX GUIs", function()
        if lx_guis_checkbox then
            lx_guis_checkbox:render("Selection Bar Enabled", "Show/hide the top selection bar for LX GUIs")
        end
        
        -- Render individual GUI enable/disable checkboxes
        for name, checkbox in pairs(constants.gui_states) do
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
        return helpers.is_input_blocked()
    end
}

-- ==================== PLUGIN REGISTRATION ====================

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)

core.log("Lx Common GUI system loaded successfully - Modular Version") 