-- LX_Nav2 - Navigation System v2
-- Enhanced polygon-based wireframe visualization system
-- Uses actual polygon data structures with edge classification

local Debug = require("modules/debug")
local TileManager = require("modules/tile_manager")
local Wireframe = require("modules/wireframe")

local LX_Nav2 = {}

-- Menu elements (created upfront like LX_Nav)
-- Color for menu headers
local color = require("common/color")

local menu_elements = {
    main_tree = core.menu.tree_node(),
    -- Visualisation submenu
    vis_tree = core.menu.tree_node(),
    show_navmesh = core.menu.checkbox(false, "lx_nav2_show_navmesh"),
    show_polygons = core.menu.checkbox(true, "lx_nav2_show_polygons"),      -- Filled polygons enabled by default
    show_edges = core.menu.checkbox(false, "lx_nav2_show_edges"),           -- Line edges disabled by default
    show_walls_only = core.menu.checkbox(false, "lx_nav2_show_walls_only"),
    show_centers = core.menu.checkbox(false, "lx_nav2_show_centers"),
    show_penalty_zones = core.menu.checkbox(false, "lx_nav2_show_penalty_zones"),  -- Penalty zone visualization
    -- Draw range
    draw_range = core.menu.slider_int(10, 200, 50, "lx_nav2_draw_range"),
    -- Stats headers (for displaying text)
    stats_header1 = core.menu.header(),
    stats_header2 = core.menu.header(),
}

-- State
local State = {
    initialized = false,
    tile_manager = nil,
    current_map_id = nil,
    last_tile_x = nil,
    last_tile_y = nil,
    last_debug_time = 0,
}

-- Tile size constants
local TILE_SIZE = 533.33333
local HALF_WORLD = 32 * TILE_SIZE

-- Visualization settings (accessible from other modules)
LX_Nav2.settings = {
    show_navmesh = false,
    show_polygons = true,      -- Filled polygons enabled by default
    show_edges = false,        -- Line edges disabled by default
    show_walls_only = false,
    show_centers = false,
    show_penalty_zones = false,
    draw_range = 50,
}

--- Convert world position to tile coordinates
local function world_to_tile(x, y)
    local tile_x = math.floor((HALF_WORLD - x) / TILE_SIZE)
    local tile_y = math.floor((HALF_WORLD - y) / TILE_SIZE)
    tile_x = math.max(0, math.min(63, tile_x))
    tile_y = math.max(0, math.min(63, tile_y))
    return tile_x, tile_y
end

--- Queue tiles around player (3x3 grid)
local function queue_nearby_tiles(map_id, center_x, center_y)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local tx, ty = center_x + dx, center_y + dy
            local prio = math.abs(dx) + math.abs(dy)
            State.tile_manager:queue_tile(map_id, tx, ty, prio)
        end
    end
end

-- Callback when a tile finishes loading - build wireframe
local function on_tile_loaded(tile_key, tile)
    local map_id = tile.mapId
    Wireframe.add_tile(map_id, tile_key, tile)
    Debug.log(string.format("[LX_Nav2] Wireframe built for tile %s (%d polys)",
        tile_key, #tile.polygons))
end

-- Initialize plugin
local function initialize()
    Debug.init()
    Debug.log("[LX_Nav2] Initializing...")
    
    -- Create tile manager
    State.tile_manager = TileManager.new({
        frame_budget_ms = 3.0,
        check_every = 128,
        max_cached = 100,
    })
    
    -- Set callback for wireframe building
    State.tile_manager:set_on_tile_loaded(on_tile_loaded)
    
    -- Log player position for reference
    local player = core.object_manager.get_local_player()
    if player then
        local pos = player:get_position()
        if pos then
            Debug.log(string.format("[LX_Nav2] Player position: (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z))
        end
        local map_id = core.get_instance_id()
        Debug.log(string.format("[LX_Nav2] Map ID: %d", map_id))
    end
    
    State.initialized = true
    Debug.log("[LX_Nav2] Initialized successfully")
    core.log("[LX_Nav2] Initialized successfully")
end

-- Update callback (called every frame)
local function on_update()
    if not State.initialized then return end
    
    -- Read visualization settings from menu
    LX_Nav2.settings.show_navmesh = menu_elements.show_navmesh:get_state()
    LX_Nav2.settings.show_polygons = menu_elements.show_polygons:get_state()
    LX_Nav2.settings.show_edges = menu_elements.show_edges:get_state()
    LX_Nav2.settings.show_walls_only = menu_elements.show_walls_only:get_state()
    LX_Nav2.settings.show_centers = menu_elements.show_centers:get_state()
    LX_Nav2.settings.show_penalty_zones = menu_elements.show_penalty_zones:get_state()
    LX_Nav2.settings.draw_range = menu_elements.draw_range:get()
    
    -- Apply settings to wireframe module
    Wireframe.set_enabled(LX_Nav2.settings.show_navmesh)
    Wireframe.set_draw_filled(LX_Nav2.settings.show_polygons)
    Wireframe.set_draw_edges(LX_Nav2.settings.show_edges)
    Wireframe.set_draw_walls_only(LX_Nav2.settings.show_walls_only)
    Wireframe.set_draw_centers(LX_Nav2.settings.show_centers)
    Wireframe.set_draw_penalty_zones(LX_Nav2.settings.show_penalty_zones)
    Wireframe.set_range(LX_Nav2.settings.draw_range)
    
    -- Process tile loading
    State.tile_manager:process_frame(3.0)
    
    -- Check if we need to queue more tiles
    local player = core.object_manager.get_local_player()
    if not player then return end
    
    local player_pos = player:get_position()
    if not player_pos then return end
    
    local map_id = core.get_instance_id()
    if not map_id then return end
    
    local tile_x, tile_y = world_to_tile(player_pos.x, player_pos.y)
    
    if map_id ~= State.current_map_id or tile_x ~= State.last_tile_x or tile_y ~= State.last_tile_y then
        State.current_map_id = map_id
        State.last_tile_x = tile_x
        State.last_tile_y = tile_y
        queue_nearby_tiles(map_id, tile_x, tile_y)
    end
    
    -- NOTE: Removed per-frame Wireframe.set_tiles() call - tiles are now added
    -- incrementally via on_tile_loaded callback to avoid rebuilding cache every frame
    
    -- Debug logging every 2 seconds
    local now = core.time()
    if now - State.last_debug_time >= 2.0 then
        State.last_debug_time = now
        local stats = State.tile_manager:get_stats()
        Debug.log(string.format("[LX_Nav2] tile(%d,%d) cached=%d queued=%d",
            tile_x, tile_y, stats.cached, stats.queued))
    end
end

-- Render callback (called every frame for drawing)
local function on_render()
    if not State.initialized then return end
    
    -- Render wireframe visualization
    Wireframe.render()
end

-- Menu render callback
local function on_render_menu()
    menu_elements.main_tree:render("Lx Nav 2", function()
        -- Visualisation submenu
        menu_elements.vis_tree:render("Visualisation", function()
            menu_elements.show_navmesh:render("Show Navmesh")
            menu_elements.show_polygons:render("Show Filled Polygons")
            menu_elements.show_edges:render("Show Edge Lines")
            menu_elements.show_walls_only:render("Show Walls Only")
            menu_elements.show_centers:render("Show Polygon Centers")
            menu_elements.show_penalty_zones:render("Show Wall Penalty Zones")
            menu_elements.draw_range:render("Draw Range (yards)")
        end)
        
        -- Show stats using header elements
        if State.tile_manager then
            local stats = State.tile_manager:get_stats()
            local text_color = color.new(200, 200, 200, 255)
            menu_elements.stats_header1:render(string.format("Tiles: %d cached, %d queued", stats.cached, stats.queued), text_color)
            menu_elements.stats_header2:render(string.format("Loaded: %d, Failed: %d", stats.loaded_total, stats.failed_total), text_color)
        end
    end)
end

-- Register callbacks
core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)
core.register_on_render_menu_callback(on_render_menu)

-- Run initialization
initialize()

-- Export to global for other modules to access settings
_G.LX_Nav2 = LX_Nav2

core.log("[LX_Nav2] Plugin loaded successfully.")

return LX_Nav2