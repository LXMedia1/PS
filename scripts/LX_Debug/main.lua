-- ==================== IMPORTS ====================
---@type color
local color = require("common/color")
---@type vec2
local vec2 = require("common/geometry/vector_2")
---@type vec3
local vec3 = require("common/geometry/vector_3")

-- Import LxCommon GUI system
local lx = _G.LxCommon

-- ==================== GUI and State Variables ====================
local demo_gui = nil
local navmesh_points = {} -- Stores the grid points persistently
local test_enabled_checkbox_info = nil
local show_navmesh_checkbox_info = nil
local navmesh_grid_size = 0
local last_scan_time = 0
local scan_interval = 1.0 -- seconds
local has_logged_drawing = false -- Flag to prevent log spam

-- Settings table to be managed by the GUI, as recommended by LxCommon docs
local Settings = {
    test_enabled = false,
    show_navmesh = false,
}

-- ==================== MAIN LOOP ====================

local function on_frame()
    if not test_enabled_checkbox_info or not test_enabled_checkbox_info.menu_component:get_state() then return end
    
    -- Add your frame-based logic here
end

-- ==================== RENDERING ====================

local function on_render()
    if not test_enabled_checkbox_info or not test_enabled_checkbox_info.menu_component:get_state() then return end
    if not show_navmesh_checkbox_info or not show_navmesh_checkbox_info.menu_component:get_state() then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end
    local player_pos = player:get_position()

    -- Scan for new grid points around the player
    local scan_radius = 50 -- Yards
    local grid_step = 1.25 -- Yards, size of each grid cell (Increased density)
    local cells_in_radius = math.floor(scan_radius / grid_step)

    local center_ix = math.floor(player_pos.x / grid_step)
    local center_iy = math.floor(player_pos.y / grid_step)

    for i = -cells_in_radius, cells_in_radius do
        for j = -cells_in_radius, cells_in_radius do
            local grid_ix = center_ix + i
            local grid_iy = center_iy + j

            -- Create row if it doesn't exist
            if not navmesh_points[grid_ix] then
                navmesh_points[grid_ix] = {}
            end

            -- Check if we need to scan this point (if it's nil, it has never been scanned)
            if navmesh_points[grid_ix][grid_iy] == nil then
                -- This point has never been scanned, scan it now
                local world_x = grid_ix * grid_step
                local world_y = grid_iy * grid_step
                
                local test_pos = vec3.new(world_x, world_y, player_pos.z)
                local ground_z = core.get_height_for_position(test_pos)

                if ground_z and ground_z ~= 0 then
                    -- Store the valid ground point
                    navmesh_points[grid_ix][grid_iy] = vec3.new(world_x, world_y, ground_z)
                else
                    -- Mark as scanned but invalid to avoid re-scanning
                    navmesh_points[grid_ix][grid_iy] = false
                end
            end
        end
    end

    -- Render all known valid points and their connections
    local max_walkable_slope = 1.0 -- Corresponds to a 45-degree angle. Higher is steeper.
    for ix, row in pairs(navmesh_points) do
        for iy, p1 in pairs(row) do
            if p1 then -- is a vec3, not false or nil
                -- Raise all points slightly to avoid Z-fighting with the ground
                local p1_raised = vec3.new(p1.x, p1.y, p1.z + 0.1)
                core.graphics.circle_3d(p1_raised, 0.25, color.green(200), 2)

                -- Connect to the point on the "right" (ix + 1)
                local p2 = navmesh_points[ix + 1] and navmesh_points[ix + 1][iy]
                if p2 then
                    -- Calculate slope and determine color
                    local slope = math.abs(p2.z - p1.z) / grid_step
                    local line_color = slope > max_walkable_slope and color.red(200) or color.cyan(200)
                    
                    local p2_raised = vec3.new(p2.x, p2.y, p2.z + 0.1)
                    core.graphics.line_3d(p1_raised, p2_raised, line_color, 2)
                end

                -- Connect to the point "below" (iy + 1)
                local p3 = navmesh_points[ix] and navmesh_points[ix][iy + 1]
                if p3 then
                    -- Calculate slope and determine color
                    local slope = math.abs(p3.z - p1.z) / grid_step
                    local line_color = slope > max_walkable_slope and color.red(200) or color.cyan(200)

                    local p3_raised = vec3.new(p3.x, p3.y, p3.z + 0.1)
                    core.graphics.line_3d(p1_raised, p3_raised, line_color, 2)
                end
            end
        end
    end
end

-- ==================== GUI SETUP ====================
if lx then
    -- Create debug GUI
    demo_gui = lx.Gui.register("LX Debug", 300, 200, "lx_debug_gui")
    
    -- Add a check to ensure the GUI was created, as per the documentation example
    if not demo_gui then
        core.log("Failed to register GUI for LX Debug!")
    else
        -- Header
        demo_gui:AddLabel("LX Debug Test Environment", 10, 10, color.white(255))
        demo_gui:AddLabel("Ready for testing", 10, 35, color.gray(200))
        
        -- Basic controls
        test_enabled_checkbox_info = demo_gui:AddCheckbox("Enable Testing", 10, 65, false, function(value)
            core.log("Testing: " .. tostring(value))
        end)
        
        -- Test button
        demo_gui:AddButton("Run Test", 10, 95, 100, 25, function()
            core.log("Test button clicked")
        end)
        
        show_navmesh_checkbox_info = demo_gui:AddCheckbox("Show Navmesh", 10, 125, false, function(value)
            core.log("Show Navmesh: " .. tostring(value))
        end)
        
        -- Register callbacks only if GUI was successfully initialized
        core.register_on_update_callback(on_frame)
        core.register_on_render_callback(on_render)
    end
else
    core.log("LxCommon GUI system not found!")
end

core.log("LX Debug environment ready")
