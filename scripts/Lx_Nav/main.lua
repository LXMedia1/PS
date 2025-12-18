--[[
    Lx_Nav - A* Navigation Plugin
    Author: Lexxer

    Main entry point with menu and callbacks.
]]

local Config = require("modules/config")
local Utils = require("modules/utils")
local State = require("modules/state")
local Loader = require("modules/loader")
local AStar = require("modules/astar")
local Renderer = require("modules/renderer")

-- Menu elements (created upfront)
local menu_elements = {
    main_tree = core.menu.tree_node(),
    enabled = core.menu.checkbox(true, "lx_nav_enabled"),
    show_path = core.menu.checkbox(true, "lx_nav_show_path"),
    show_debug = core.menu.checkbox(true, "lx_nav_show_debug"),
    btn_set_start = core.menu.button("lx_nav_btn_start"),
    btn_set_end = core.menu.button("lx_nav_btn_end"),
    btn_calculate = core.menu.button("lx_nav_btn_calculate"),
    btn_clear = core.menu.button("lx_nav_btn_clear"),
}

-- Get local player
local function get_local_player()
    local player = core.object_manager.get_local_player()
    return player
end

-- Get player position
local function get_player_position()
    local player = get_local_player()
    if not player then return nil end

    local pos = player:get_position()
    if not pos then return nil end

    return pos.x, pos.y, pos.z
end

-- Get player map ID
local function get_player_map_id()
    local player = get_local_player()
    if not player then return nil end

    -- Try to get map ID from player or environment
    local map_id = core.get_map_id and core.get_map_id() or 0
    return map_id
end

-- Set start point to current player position
local function set_start_point()
    local x, y, z = get_player_position()
    local mapId = get_player_map_id()

    if not x then
        Utils.log_warning("Could not get player position")
        return
    end

    State.set_start(x, y, z, mapId)
    Utils.log(string.format("Start point set: (%.1f, %.1f, %.1f) map %d", x, y, z, mapId))
end

-- Set end point to current player position
local function set_end_point()
    local x, y, z = get_player_position()
    local mapId = get_player_map_id()

    if not x then
        Utils.log_warning("Could not get player position")
        return
    end

    State.set_end(x, y, z, mapId)
    Utils.log(string.format("End point set: (%.1f, %.1f, %.1f) map %d", x, y, z, mapId))
end

-- Calculate path from start to end
local function calculate_path()
    if not State.has_valid_endpoints() then
        Utils.log_warning("Set both start and end points first")
        return
    end

    if not State.same_map() then
        Utils.log_warning("Cross-map navigation not yet implemented")
        return
    end

    local mapId = State.start_point.mapId

    -- Load graph for this map
    local graph = Loader.load_map(mapId)
    if not graph then
        Utils.log_error("Failed to load navigation data for map " .. mapId)
        return
    end

    State.graph = graph

    -- Find nearest nodes to start and end points
    local startNode, startDist = Loader.find_nearest_node(graph, State.start_point.x, State.start_point.y)
    local endNode, endDist = Loader.find_nearest_node(graph, State.end_point.x, State.end_point.y)

    if not startNode then
        Utils.log_error("Could not find start node in navigation graph")
        return
    end

    if not endNode then
        Utils.log_error("Could not find end node in navigation graph")
        return
    end

    State.start_node = startNode
    State.end_node = endNode

    Utils.log(string.format("Start node: %d (%.1f yards away)", startNode, startDist))
    Utils.log(string.format("End node: %d (%.1f yards away)", endNode, endDist))

    -- Start A* search
    if not AStar.start_search(graph, startNode, endNode) then
        Utils.log_error("Failed to start A* search")
        return
    end

    Utils.log("Path calculation started...")
end

-- Clear all navigation data
local function clear_all()
    State.clear_all()
    AStar.cancel()
    Utils.log("Navigation cleared")
end

-- Update callback (called every frame)
local function on_update()
    if not menu_elements.enabled:get_state() then
        return
    end

    -- Continue A* search if in progress
    if AStar.is_searching() and State.graph then
        local result = AStar.process_frame(State.graph, Config.FRAME_BUDGET_MS)

        if result == State.SEARCH_FOUND then
            -- Path found, reconstruct it
            AStar.reconstruct_path(State.graph, State.end_node)
            Utils.log("Path found!")
        elseif result == State.SEARCH_FAILED then
            Utils.log_warning("No path found")
        end
    end
end

-- Render callback (called every frame for 3D rendering)
local function on_render()
    if not menu_elements.enabled:get_state() then
        return
    end

    -- Update visualization settings from menu
    State.show_path = menu_elements.show_path:get_state()
    State.show_debug = menu_elements.show_debug:get_state()

    -- Render path and markers
    Renderer.render_path()

    -- Render debug overlay
    Renderer.render_debug_overlay()
end

-- Menu render callback
local function on_render_menu()
    menu_elements.main_tree:render("Lx_Nav", function()
        -- Enable checkbox
        menu_elements.enabled:render("Enable Navigation")

        -- Visualization options
        menu_elements.show_path:render("Show Path")
        menu_elements.show_debug:render("Show Debug Info")

        -- Buttons
        if menu_elements.btn_set_start:render("Set Start Point") then
            set_start_point()
        end

        if menu_elements.btn_set_end:render("Set End Point") then
            set_end_point()
        end

        if menu_elements.btn_calculate:render("Calculate Route") then
            calculate_path()
        end

        if menu_elements.btn_clear:render("Clear All") then
            clear_all()
        end
    end)
end

-- Initialize
local function initialize()
    Utils.file_log("Lx_Nav initializing...")

    -- Register callbacks
    core.register_on_update_callback(on_update)
    core.register_on_render_callback(on_render)
    core.register_on_render_menu_callback(on_render_menu)

    Utils.file_log("Lx_Nav initialized")
    Utils.log("Lx_Nav loaded")
end

-- Run initialization
initialize()
