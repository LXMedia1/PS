-- ==================== PLUGIN SETTINGS ====================
local Settings = {
    debug_mode = false
}

-- ==================== MENU ELEMENTS ====================


-- ==================== CORE FUNCTIONALITY ====================


-- ==================== UPDATE CALLBACK ====================
local function on_update()

end

-- ==================== MENU CALLBACK ====================
local function on_render_menu()

end
-- ==================== PLUGIN REGISTRATION ====================

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_menu_callback(on_render_menu)

core.log("Lx Common loaded successfully")