-- LX_NavDebug
-- NavMesh visualization plugin for debugging navigation data
-- Author: Lexxer

-- Initialize log file
core.create_log_file("LX_NavDebug.log")
local function log(msg)
    core.write_log_file("LX_NavDebug.log", tostring(msg) .. "\n")
    core.log("[LX_NavDebug] " .. tostring(msg))
end

log("Starting LX_NavDebug...")

local ok, Config = pcall(require, "modules/config")
if not ok then log("ERROR loading config: " .. tostring(Config)) Config = nil end

local ok2, Utils = pcall(require, "modules/utils")
if not ok2 then log("ERROR loading utils: " .. tostring(Utils)) Utils = nil end

local ok3, Loader = pcall(require, "modules/loader")
if not ok3 then log("ERROR loading loader: " .. tostring(Loader)) Loader = nil end

local ok4, Renderer = pcall(require, "modules/renderer")
if not ok4 then log("ERROR loading renderer: " .. tostring(Renderer)) Renderer = nil end

log("Modules loaded: config=" .. tostring(ok) .. " utils=" .. tostring(ok2) .. " loader=" .. tostring(ok3) .. " renderer=" .. tostring(ok4))

-- Log map ID info at start
local test_inst = core.get_instance_id()
log("Instance ID (TrinityCore map): " .. tostring(test_inst))

-- State
local loaded_tiles = {}
local last_tile_check = 0
local TILE_CHECK_INTERVAL = 0.5  -- seconds

-- Menu elements (created upfront)
local menu_elements = {
    main_tree = core.menu.tree_node(),
    enabled = core.menu.checkbox(false, "lx_navdebug_enabled"),
    render_distance = core.menu.slider_int(10, 200, 100, "lx_navdebug_render_distance"),
    cone_angle = core.menu.slider_int(30, 360, 90, "lx_navdebug_cone_angle"),
    edge_thickness = core.menu.slider_int(1, 5, 2, "lx_navdebug_edge_thickness"),
    show_debug = core.menu.checkbox(true, "lx_navdebug_show_debug"),
    tile_grid_size = core.menu.slider_int(1, 7, 3, "lx_navdebug_tile_grid_size"),
    clear_cache_btn = core.menu.button("lx_navdebug_clear_cache"),
}

-- Debug counter
local debug_frame = 0
local last_debug_log = 0
local update_count = 0

-- On update callback
local function on_update()
    update_count = update_count + 1
    if update_count == 1 or update_count % 500 == 0 then
        log("on_update called: " .. update_count)
    end

    -- Get local player
    local player = core.object_manager.get_local_player()
    if not player then return end

    local pos = player:get_position()
    if not pos then return end

    -- Get current map ID (instance_id is the TrinityCore map ID)
    local mapId = core.get_instance_id()
    if not mapId then return end

    -- Throttle tile loading
    local now = core.time()
    if now - last_tile_check > TILE_CHECK_INTERVAL then
        last_tile_check = now

        -- Get enabled state from menu
        local is_enabled = menu_elements.enabled:get_state()

        -- Debug log every 5 seconds (always, even when disabled)
        if now - last_debug_log > 5 then
            last_debug_log = now
            local tileX, tileY = Utils.world_to_tile(pos)
            log(string.format("Update: enabled=%s instId=%d pos=(%.1f,%.1f,%.1f) tile=(%d,%d) loaded=%d",
                tostring(is_enabled), mapId, pos.x, pos.y, pos.z, tileX, tileY, #loaded_tiles))
        end

        -- Only load tiles if enabled
        if is_enabled and Loader then
            -- Update config values from menu
            Config.enabled = is_enabled
            Config.render_distance = menu_elements.render_distance:get()
            Config.cone_angle = menu_elements.cone_angle:get()
            Config.edge_thickness = menu_elements.edge_thickness:get()
            Config.tile_grid_size = menu_elements.tile_grid_size:get()

            loaded_tiles = Loader.update_tiles(mapId, pos)
        end
    end
end

-- On render callback
local function on_render()
    local is_enabled = menu_elements.enabled:get_state()
    if not is_enabled then return end

    -- Get local player
    local player = core.object_manager.get_local_player()
    if not player then return end

    local pos = player:get_position()
    local facing = player:get_rotation()
    if not pos or not facing then return end

    -- Render all loaded tiles
    if Renderer then
        Renderer.render_tiles(loaded_tiles, pos, facing)

        -- Debug overlay
        local show_debug = menu_elements.show_debug:get_state()
        if show_debug then
            Renderer.render_debug_overlay(loaded_tiles)
        end
    end
end

-- On render menu callback
local function on_render_menu()
    menu_elements.main_tree:render("LX_NavDebug", function()
        -- Enable checkbox
        menu_elements.enabled:render("Enable Visualization")

        -- Render distance slider
        menu_elements.render_distance:render("Render Distance (yards)")

        -- Cone angle slider
        menu_elements.cone_angle:render("View Cone (degrees)")

        -- Edge thickness slider
        menu_elements.edge_thickness:render("Line Thickness")

        -- Debug overlay checkbox
        menu_elements.show_debug:render("Show Debug Info")

        -- Tile grid size slider
        menu_elements.tile_grid_size:render("Tile Grid Size")

        -- Cache info text (using core.graphics for custom text if needed)
        if Loader then
            local cache_tiles, cache_edges = Loader.get_cache_stats()
            -- Note: For now just log cache stats, can add visual display later
        end

        -- Clear cache button
        menu_elements.clear_cache_btn:render("Clear Cache")
        if menu_elements.clear_cache_btn:is_clicked() then
            if Loader then
                Loader.clear_cache()
            end
            loaded_tiles = {}
            log("Cache cleared by user")
        end
    end)
end

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)

core.log("[LX_NavDebug] Loaded successfully")
