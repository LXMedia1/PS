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
local last_logged_path_info = nil -- Last logged path info to prevent spam
local current_map_id = nil -- Track current map for cleanup

-- Safe spot movement variables
local safe_spot = nil
local is_moving_to_safe_spot = false
local movement_threshold = 3.0  -- Distance threshold to consider "arrived"
local is_turning_left = false
local is_turning_right = false
local is_moving_forward = false
local is_facing_next_waypoint = false -- New state for precise turning at waypoints

-- Path planning variables
local calculated_path = {}  -- Array of vec3 waypoints
local current_waypoint_index = 1
local waypoint_threshold = 1.5  -- Distance to consider waypoint reached (reduced from 2.0)
local path_calculation_needed = true

-- Settings table to be managed by the GUI, as recommended by LxCommon docs
local Settings = {
    test_enabled = false,
    show_navmesh = false,
}

-- ==================== SAFE SPOT FUNCTIONS ====================

-- New function to handle turning towards a point without moving forward
local function face_towards_point(player, target_pos)
    local player_pos = player:get_position()
    local dx = target_pos.x - player_pos.x
    local dy = target_pos.y - player_pos.y
    local target_angle = math.atan2(dy, dx)
    local player_facing = player:get_rotation()
    
    local angle_diff = target_angle - player_facing
    while angle_diff > math.pi do angle_diff = angle_diff - 2 * math.pi end
    while angle_diff < -math.pi do angle_diff = angle_diff + 2 * math.pi end
    
    local facing_threshold = 0.05 -- Tighter threshold for stationary turning
    
    if math.abs(angle_diff) <= facing_threshold then
        -- Stop turning, we are facing the target
        if is_turning_left then core.input.turn_left_stop(); is_turning_left = false end
        if is_turning_right then core.input.turn_right_stop(); is_turning_right = false end
        return true -- Facing is complete
    else
        -- Turn left or right
        if angle_diff > 0 then
            if not is_turning_left then core.input.turn_left_start(); is_turning_left = true end
            if is_turning_right then core.input.turn_right_stop(); is_turning_right = false end
        else
            if not is_turning_right then core.input.turn_right_start(); is_turning_right = true end
            if is_turning_left then core.input.turn_left_stop(); is_turning_left = false end
        end
    end
    
    return false -- Still turning
end

-- Improved A* pathfinding using navmesh data with better route optimization
local function calculate_path_to_target(start_pos, target_pos)
    calculated_path = {}
    current_waypoint_index = 1
    
    core.log("=== PATHFINDING START ===")
    core.log("Start: " .. start_pos.x .. ", " .. start_pos.y .. ", " .. start_pos.z)
    core.log("Target: " .. target_pos.x .. ", " .. target_pos.y .. ", " .. target_pos.z)
    
    -- If no navmesh data, fall back to direct path
    if not navmesh_points or next(navmesh_points) == nil then
        core.log("No navmesh data available, using direct path")
        table.insert(calculated_path, target_pos)
        return calculated_path
    end
    
    core.log("Navmesh data available with " .. navmesh_grid_size .. " points")
    
    -- Check if direct line of sight is possible (no obstacles)
    local function has_line_of_sight(from_pos, to_pos)
        local distance = math.sqrt((to_pos.x - from_pos.x)^2 + (to_pos.y - from_pos.y)^2)
        local steps = math.max(20, math.ceil(distance / 0.5)) -- More steps for longer distances
        local blocked_count = 0
        local total_checked = 0
        local last_z = from_pos.z -- Track Z of the last valid point

        for i = 1, steps do
            local t = i / steps
            local check_x = from_pos.x + (to_pos.x - from_pos.x) * t
            local check_y = from_pos.y + (to_pos.y - from_pos.y) * t
            
            local gx = math.floor(check_x / 1.25)
            local gy = math.floor(check_y / 1.25)
            
            total_checked = total_checked + 1
            
            local grid_point = navmesh_points[gx] and navmesh_points[gx][gy]

            -- Check if this grid position exists and is walkable
            if not grid_point or grid_point == false then
                blocked_count = blocked_count + 1
                if blocked_count <= 3 then
                    if not navmesh_points[gx] then
                        core.log("Blocked at step " .. i .. ": no data for gx=" .. gx)
                    elseif not navmesh_points[gx][gy] then
                        core.log("Blocked at step " .. i .. ": no data for gy=" .. gy .. " at gx=" .. gx)
                    else
                        core.log("Blocked at step " .. i .. ": marked as unwalkable at (" .. gx .. "," .. gy .. ")")
                    end
                end
            else -- The point is walkable (it's a vec3)
                -- Check for significant height differences (slope check)
                local current_z = grid_point.z
                local height_diff = math.abs(current_z - last_z)
                local dist_step = distance / steps
                
                if dist_step > 0.01 then -- Avoid division by zero
                    local slope = height_diff / dist_step
                    if slope > 1.0 then -- Max walkable slope (same as A*)
                        blocked_count = blocked_count + 1
                        if blocked_count <= 3 then
                            core.log("Blocked at step " .. i .. ": slope too steep (" .. string.format("%.2f", slope) .. ") at (" .. gx .. "," .. gy .. ")")
                        end
                    end
                end
                
                last_z = current_z -- Update last_z for the next iteration
            end
        end
        
        local clear_path = blocked_count == 0
        core.log("Line of sight check: " .. blocked_count .. "/" .. total_checked .. " points blocked. Distance: " .. string.format("%.1f", distance) .. ". Clear: " .. tostring(clear_path))
        
        -- For debugging, if it claims clear path but we suspect obstacles, force A*
        if clear_path and distance > 5.0 then  -- Reduced from 10.0 to 5.0
            core.log("Distance > 5 units, forcing A* pathfinding for safety")
            return false
        end
        
        return clear_path
    end
    
    -- If we have direct line of sight, use direct path
    core.log("Checking line of sight...")
    local has_clear_path = has_line_of_sight(start_pos, target_pos)
    if has_clear_path then
        core.log("Direct line of sight available - using direct path")
        table.insert(calculated_path, target_pos)
        return calculated_path
    end
    
    core.log("No direct line of sight - using A* pathfinding")
    
    -- A* pathfinding for complex routes
    local grid_step = 1.25
    local open_set = {}
    local closed_set = {}
    local came_from = {}
    local g_score = {}
    local f_score = {}
    
    -- Convert positions to grid coordinates
    local function pos_to_grid(pos)
        return math.floor(pos.x / grid_step), math.floor(pos.y / grid_step)
    end
    
    local function grid_to_pos(gx, gy)
        local x, y = gx * grid_step, gy * grid_step
        local z = start_pos.z -- Default fallback
        if navmesh_points[gx] and navmesh_points[gx][gy] and type(navmesh_points[gx][gy]) == "table" then
            z = navmesh_points[gx][gy].z
        end
        return vec3.new(x, y, z)
    end
    
    local function is_walkable(gx, gy)
        return navmesh_points[gx] and navmesh_points[gx][gy] and navmesh_points[gx][gy] ~= false
    end
    
    local function can_move_between(from_gx, from_gy, to_gx, to_gy)
        -- Check if both points are walkable
        if not is_walkable(from_gx, from_gy) or not is_walkable(to_gx, to_gy) then
            return false
        end
        
        local from_point = navmesh_points[from_gx][from_gy]
        local to_point = navmesh_points[to_gx][to_gy]
        
        -- Both must be vec3 objects (not false)
        if type(from_point) ~= "table" or type(to_point) ~= "table" then
            return false
        end
        
        -- Calculate distance and height difference
        local dx = (to_gx - from_gx) * 1.25
        local dy = (to_gy - from_gy) * 1.25
        local distance = math.sqrt(dx*dx + dy*dy)
        
        if distance == 0 then 
            return true 
        end
        
        local height_diff = math.abs(to_point.z - from_point.z)
        local slope = height_diff / distance
        
        -- Max walkable slope (about 45 degrees)
        local max_slope = 1.0
        
        local can_walk = slope <= max_slope
        if not can_walk then
            core.log("Movement blocked from (" .. from_gx .. "," .. from_gy .. ") to (" .. to_gx .. "," .. to_gy .. ") - slope: " .. string.format("%.2f", slope) .. " > " .. max_slope)
        end
        
        return can_walk
    end
    
    local function heuristic(gx1, gy1, gx2, gy2)
        return math.sqrt((gx2 - gx1)^2 + (gy2 - gy1)^2)
    end
    
    local function grid_key(gx, gy)
        return gx .. "," .. gy
    end
    
    local start_gx, start_gy = pos_to_grid(start_pos)
    local target_gx, target_gy = pos_to_grid(target_pos)
    
    core.log("A* from grid (" .. start_gx .. "," .. start_gy .. ") to (" .. target_gx .. "," .. target_gy .. ")")
    
    -- Check if start and target positions are walkable
    if not is_walkable(start_gx, start_gy) then
        core.log("Warning: Start position not walkable, using direct path")
        table.insert(calculated_path, target_pos)
        return calculated_path
    end
    
    if not is_walkable(target_gx, target_gy) then
        core.log("Warning: Target position not walkable, finding nearest walkable point")
        -- Find nearest walkable point to target
        local best_gx, best_gy = target_gx, target_gy
        local best_distance = math.huge
        
        for search_radius = 1, 5 do
            for dx = -search_radius, search_radius do
                for dy = -search_radius, search_radius do
                    local test_gx, test_gy = target_gx + dx, target_gy + dy
                    if is_walkable(test_gx, test_gy) then
                        local distance = math.sqrt(dx*dx + dy*dy)
                        if distance < best_distance then
                            best_gx, best_gy = test_gx, test_gy
                            best_distance = distance
                        end
                    end
                end
            end
            if best_distance < math.huge then
                break
            end
        end
        
        if best_distance == math.huge then
            core.log("No walkable point found near target, using direct path")
            table.insert(calculated_path, target_pos)
            return calculated_path
        end
        
        target_gx, target_gy = best_gx, best_gy
        core.log("Using nearest walkable point: (" .. target_gx .. "," .. target_gy .. ")")
    end
    
    -- Initialize A*
    local start_key = grid_key(start_gx, start_gy)
    table.insert(open_set, {gx = start_gx, gy = start_gy})
    g_score[start_key] = 0
    f_score[start_key] = heuristic(start_gx, start_gy, target_gx, target_gy)
    
    local max_iterations = 1000  -- Prevent infinite loops
    local iterations = 0
    
    core.log("Starting A* algorithm with " .. #open_set .. " initial nodes")
    
    while #open_set > 0 and iterations < max_iterations do
        iterations = iterations + 1
        
        if iterations % 100 == 0 then
            core.log("A* iteration " .. iterations .. ", open set size: " .. #open_set)
        end
        -- Find node with lowest f_score
        local current_idx = 1
        for i = 2, #open_set do
            local current_key = grid_key(open_set[i].gx, open_set[i].gy)
            local best_key = grid_key(open_set[current_idx].gx, open_set[current_idx].gy)
            if (f_score[current_key] or math.huge) < (f_score[best_key] or math.huge) then
                current_idx = i
            end
        end
        
        local current = table.remove(open_set, current_idx)
        local current_key = grid_key(current.gx, current.gy)
        closed_set[current_key] = true
        
        -- Check if we reached the target
        if current.gx == target_gx and current.gy == target_gy then
            -- Reconstruct path
            local path = {}
            while current do
                table.insert(path, 1, grid_to_pos(current.gx, current.gy))
                current = came_from[grid_key(current.gx, current.gy)]
            end
            
            -- Simplify path by removing unnecessary waypoints
            local simplified_path = {path[1]}
            for i = 2, #path - 1 do
                local prev = simplified_path[#simplified_path]
                local next_pt = path[i + 1]
                
                -- If we can go directly from prev to next_pt, skip current point
                if not has_line_of_sight(prev, next_pt) then
                    table.insert(simplified_path, path[i])
                end
            end
            table.insert(simplified_path, path[#path])
            
            calculated_path = simplified_path
            core.log("A* pathfinding successful: " .. #simplified_path .. " waypoints")
            return calculated_path
        end
        
        -- Check neighbors (8-directional)
        local neighbors = {
            {-1, -1}, {-1, 0}, {-1, 1},
            {0, -1},           {0, 1},
            {1, -1},  {1, 0},  {1, 1}
        }
        
        for _, neighbor in ipairs(neighbors) do
            local nx, ny = current.gx + neighbor[1], current.gy + neighbor[2]
            local neighbor_key = grid_key(nx, ny)
            
            if is_walkable(nx, ny) and not closed_set[neighbor_key] and can_move_between(current.gx, current.gy, nx, ny) then
                local tentative_g = (g_score[current_key] or math.huge) + heuristic(current.gx, current.gy, nx, ny)
                
                local in_open_set = false
                for _, node in ipairs(open_set) do
                    if node.gx == nx and node.gy == ny then
                        in_open_set = true
                        break
                    end
                end
                
                if not in_open_set then
                    table.insert(open_set, {gx = nx, gy = ny})
                end
                
                if tentative_g < (g_score[neighbor_key] or math.huge) then
                    came_from[neighbor_key] = current
                    g_score[neighbor_key] = tentative_g
                    f_score[neighbor_key] = tentative_g + heuristic(nx, ny, target_gx, target_gy)
                end
            end
        end
    end
    
    -- No path found, fall back to direct path
    core.log("A* pathfinding failed after " .. iterations .. " iterations - no path found, using direct fallback")
    core.log("Final open set size: " .. #open_set)
    table.insert(calculated_path, target_pos)
    return calculated_path
end

-- Draw the calculated path
local function draw_calculated_path()
    if not calculated_path or #calculated_path == 0 then
        core.log("No calculated path to draw")
        return
    end
    
    -- Only log path info when it changes to reduce spam
    local current_path_info = #calculated_path .. "_" .. current_waypoint_index
    if last_logged_path_info ~= current_path_info then
        core.log("Drawing path with " .. #calculated_path .. " waypoints, current: " .. current_waypoint_index)
        last_logged_path_info = current_path_info
    end
    
    -- Draw waypoints as spheres
    for i, waypoint in ipairs(calculated_path) do
        local waypoint_color = color.yellow(200)
        if i == current_waypoint_index then
            waypoint_color = color.green(255) -- Current target waypoint
        end
        
        -- Raise slightly above ground to avoid Z-fighting
        local raised_waypoint = vec3.new(waypoint.x, waypoint.y, waypoint.z + 0.3)
        core.graphics.circle_3d(raised_waypoint, 0.5, waypoint_color, 3)
        
        -- Draw line to next waypoint
        if i < #calculated_path then
            local next_waypoint = calculated_path[i + 1]
            local raised_next = vec3.new(next_waypoint.x, next_waypoint.y, next_waypoint.z + 0.3)
            core.graphics.line_3d(raised_waypoint, raised_next, color.orange(255), 3)
        end
    end
    
    -- Draw line from player to current waypoint
    local player = core.object_manager.get_local_player()
    if player and player:is_valid() and current_waypoint_index <= #calculated_path then
        local player_pos = player:get_position()
        if player_pos then
            local current_waypoint = calculated_path[current_waypoint_index]
            local raised_player = vec3.new(player_pos.x, player_pos.y, player_pos.z + 0.3)
            local raised_waypoint = vec3.new(current_waypoint.x, current_waypoint.y, current_waypoint.z + 0.3)
            core.graphics.line_3d(raised_player, raised_waypoint, color.cyan(255), 4)
        end
    end
end

-- Process safe spot movement using navmesh pathfinding
local function process_safe_spot_movement()
    if not is_moving_to_safe_spot or not safe_spot then
        return
    end
    
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        is_moving_to_safe_spot = false
        return
    end
    
    local player_pos = player:get_position()
    if not player_pos then
        return
    end
    
    -- Calculate path if needed
    if path_calculation_needed then
        calculate_path_to_target(player_pos, safe_spot)
        path_calculation_needed = false
        last_logged_path_info = nil -- Reset path log info for new path
        
        -- Skip first waypoints that are too close to current position to avoid circling
        while current_waypoint_index <= #calculated_path do
            local waypoint = calculated_path[current_waypoint_index]
            local dx = waypoint.x - player_pos.x
            local dy = waypoint.y - player_pos.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance > waypoint_threshold then
                break -- Found a waypoint far enough away
            else
                current_waypoint_index = current_waypoint_index + 1
                core.log("Skipping waypoint " .. (current_waypoint_index - 1) .. " - too close to start position (distance: " .. string.format("%.1f", distance) .. ")")
            end
        end
    end
    
    -- Check if we have a valid path
    if not calculated_path or #calculated_path == 0 then
        core.log_warning("No valid path found to safe spot!")
        is_moving_to_safe_spot = false
        return
    end
    
    -- Get current target waypoint
    local current_target = calculated_path[current_waypoint_index]
    if not current_target then
        is_moving_to_safe_spot = false
        core.log("Path completed!")
        core.graphics.add_notification("safespot", "Safe Spot", "Arrived at destination!", 5, color.green())
        return
    end
    
    -- If we are in the special "facing" state, only turn
    if is_facing_next_waypoint then
        if face_towards_point(player, current_target) then
            -- We are now facing the waypoint, so we can start moving towards it
            is_facing_next_waypoint = false
            core.log("Finished facing waypoint, resuming movement.")
        end
        return -- Don't do regular movement processing while facing
    end

    -- Calculate distance to current waypoint
    local dx = current_target.x - player_pos.x
    local dy = current_target.y - player_pos.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- Check if we've reached the current waypoint
    if distance <= waypoint_threshold then
        current_waypoint_index = current_waypoint_index + 1
        last_logged_path_info = nil -- Reset log info when reaching new waypoint
        core.log("Reached waypoint " .. (current_waypoint_index - 1) .. "/" .. #calculated_path .. " (distance: " .. string.format("%.1f", distance) .. ")")
        
        -- Stop all movement immediately upon reaching a waypoint
        if is_moving_forward then core.input.move_forward_stop(); is_moving_forward = false end
        if is_turning_left then core.input.turn_left_stop(); is_turning_left = false end
        if is_turning_right then core.input.turn_right_stop(); is_turning_right = false end
        
        -- Check if this was the final waypoint
        if current_waypoint_index > #calculated_path then
            is_moving_to_safe_spot = false
            core.log("Arrived at safe spot!")
            core.graphics.add_notification("safespot", "Safe Spot", "Arrived at destination!", 5, color.green())
            return
        else
            -- We have a next waypoint, so enter the "facing" state
            is_facing_next_waypoint = true
            core.log("Reached waypoint. Now turning to face the next one.")
            return -- Skip the rest of the logic for this frame
        end
    end
    
    -- Calculate angle to current waypoint
    local target_angle = math.atan2(dy, dx)
    local player_facing = player:get_rotation()
    
    -- Normalize angles to -pi to pi range
    local angle_diff = target_angle - player_facing
    while angle_diff > math.pi do angle_diff = angle_diff - 2 * math.pi end
    while angle_diff < -math.pi do angle_diff = angle_diff + 2 * math.pi end
    
    -- Calculate required movement actions
    local facing_threshold = 0.15  -- Slightly tighter threshold
    local should_move_forward = false
    local should_turn_left = false
    local should_turn_right = false
    local should_use_direction = false
    
    -- Determine what actions we need
    if math.abs(angle_diff) <= facing_threshold then
        -- Close to target direction, just move forward
        should_move_forward = true
    else
        -- For large angle differences, use direction input for initial alignment
        if math.abs(angle_diff) > math.pi * 0.25 then -- > 45 degrees
            should_use_direction = true
            should_move_forward = true
        else
            -- For smaller angles, use left/right turning for fine adjustment
            if angle_diff > 0.05 then
                should_turn_left = true
            elseif angle_diff < -0.05 then
                should_turn_right = true
            end
            
            -- Also move forward unless we need a sharp turn
            if math.abs(angle_diff) < math.pi * 0.5 then -- 90 degrees
                should_move_forward = true
            end
        end
    end
    
    -- Handle direction-based movement for large angle differences
    if should_use_direction then
        -- Stop any current turning
        if is_turning_left then
            core.input.turn_left_stop()
            is_turning_left = false
        end
        if is_turning_right then
            core.input.turn_right_stop()
            is_turning_right = false
        end
        
        -- Use direction input for quick alignment
        local direction_x = math.cos(target_angle)
        local direction_y = math.sin(target_angle)
        
        -- Apply directional movement (if the API supports it)
        -- For now, we'll still use forward + turning but with faster turning
        should_move_forward = true
        if angle_diff > 0.1 then
            should_turn_left = true
        elseif angle_diff < -0.1 then
            should_turn_right = true
        end
    end
    
    -- Only change input states when they actually need to change
    -- Forward movement
    if should_move_forward and not is_moving_forward then
        core.input.move_forward_start()
        is_moving_forward = true
    elseif not should_move_forward and is_moving_forward then
        core.input.move_forward_stop()
        is_moving_forward = false
    end
    
    -- Left turning
    if should_turn_left and not is_turning_left then
        if is_turning_right then
            core.input.turn_right_stop()
            is_turning_right = false
        end
        core.input.turn_left_start()
        is_turning_left = true
    elseif not should_turn_left and is_turning_left then
        core.input.turn_left_stop()
        is_turning_left = false
    end
    
    -- Right turning
    if should_turn_right and not is_turning_right then
        if is_turning_left then
            core.input.turn_left_stop()
            is_turning_left = false
        end
        core.input.turn_right_start()
        is_turning_right = true
    elseif not should_turn_right and is_turning_right then
        core.input.turn_right_stop()
        is_turning_right = false
    end
end

-- ==================== MAIN LOOP ====================

local function on_frame()
    if not test_enabled_checkbox_info or not test_enabled_checkbox_info.menu_component:get_state() then return end
    
    -- Process safe spot movement
    process_safe_spot_movement()
    
    -- Add your other frame-based logic here
end

-- ==================== RENDERING ====================

local function on_render()
    if not test_enabled_checkbox_info or not test_enabled_checkbox_info.menu_component:get_state() then return end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end
    local player_pos = player:get_position()

    -- Show navmesh if enabled
    if show_navmesh_checkbox_info and show_navmesh_checkbox_info.menu_component:get_state() then
        -- Scan for new grid points around the player instantly
        local scan_radius = 50 -- Yards
        local grid_step = 1.25 -- Yards, size of each grid cell (Increased density)
        local cells_in_radius = math.floor(scan_radius / grid_step)

        -- Instant scanning - no timer needed since ground doesn't change
        local new_points_this_frame = 0

        for ix = -cells_in_radius, cells_in_radius do
            for iy = -cells_in_radius, cells_in_radius do
                local test_x = player_pos.x + ix * grid_step
                local test_y = player_pos.y + iy * grid_step

                local grid_x = math.floor(test_x / grid_step)
                local grid_y = math.floor(test_y / grid_step)

                -- Only scan if this grid point hasn't been scanned yet
                if not navmesh_points[grid_x] then
                    navmesh_points[grid_x] = {}
                end
                if navmesh_points[grid_x][grid_y] == nil then
                    -- Get the ground height at this position (try higher Z coordinate)
                    local test_z = core.get_height_for_position(vec3.new(test_x, test_y, player_pos.z + 100))
                    
                    if test_z and test_z > 0 then
                        navmesh_points[grid_x][grid_y] = vec3.new(test_x, test_y, test_z)
                        navmesh_grid_size = navmesh_grid_size + 1
                        new_points_this_frame = new_points_this_frame + 1
                    else
                        navmesh_points[grid_x][grid_y] = false
                    end
                end
            end
        end
        
        -- Log only when new points are found
        if new_points_this_frame > 0 then
            core.log("Scanned " .. new_points_this_frame .. " new navmesh points. Total grid size: " .. navmesh_grid_size)
        end
        
        -- Cleanup navmesh data only when changing maps
        local player_map_id = core.get_map_id()
        if current_map_id == nil then
            current_map_id = player_map_id
            core.log("Navmesh initialized for map: " .. tostring(player_map_id))
        elseif current_map_id ~= player_map_id then
            -- Player changed maps - clear all navmesh data
            local points_before = navmesh_grid_size
            navmesh_points = {}
            navmesh_grid_size = 0
            current_map_id = player_map_id
            core.log("Map changed to " .. tostring(player_map_id) .. " - cleared " .. tostring(points_before) .. " navmesh points")
        end

        -- Render all known navmesh points (not limited by distance)
        local max_walkable_slope = 1.0 -- Corresponds to a 45-degree angle. Higher is steeper.
        
        for grid_x, row in pairs(navmesh_points) do
            for grid_y, p1 in pairs(row) do
                if p1 then -- is a vec3, not false or nil
                    -- Raise all points slightly to avoid Z-fighting with the ground
                    local p1_raised = vec3.new(p1.x, p1.y, p1.z + 0.1)
                    core.graphics.circle_3d(p1_raised, 0.25, color.green(200), 2)

                    -- Connect to the point on the "right" (grid_x + 1)
                    if navmesh_points[grid_x + 1] and navmesh_points[grid_x + 1][grid_y] then
                        local p2 = navmesh_points[grid_x + 1][grid_y]
                        if p2 then
                            -- Calculate slope and determine color
                            local slope = math.abs(p2.z - p1.z) / grid_step
                            local line_color = slope > max_walkable_slope and color.red(200) or color.cyan(200)
                            
                            local p2_raised = vec3.new(p2.x, p2.y, p2.z + 0.1)
                            core.graphics.line_3d(p1_raised, p2_raised, line_color, 2)
                        end
                    end

                    -- Connect to the point "below" (grid_y + 1)
                    if navmesh_points[grid_x] and navmesh_points[grid_x][grid_y + 1] then
                        local p3 = navmesh_points[grid_x][grid_y + 1]
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
    end
    
    -- Draw the calculated path if movement is active
    if is_moving_to_safe_spot then
        draw_calculated_path()
    end
end

-- ==================== GUI SETUP ====================
if lx then
    -- Create debug GUI
    demo_gui = lx.Gui.register("LX Debug", 500, 300, "lx_debug_gui")
    
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
        
        -- Safe spot controls
        demo_gui:AddLabel("Safe Spot Movement", 10, 155, color.cyan(255))
        
        -- Button to set the safe spot
        demo_gui:AddButton("Set Safe Spot", 10, 180, 120, 25, function()
            local player = core.object_manager.get_local_player()
            if player and player:is_valid() then
                local pos = player:get_position()
                if pos then
                    -- Create a new vec3 object using the coordinates
                    safe_spot = vec3.new(pos.x, pos.y, pos.z)
                    core.log("Safe spot set to: " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
                    core.graphics.add_notification("safespot", "Safe Spot", "Position saved!", 5, color.green())
                else
                    core.log_warning("Could not get player position.")
                    core.graphics.add_notification("safespot", "Safe Spot", "Failed to save position!", 5, color.red())
                end
            else
                core.log_warning("Could not set safe spot: player not valid.")
                core.graphics.add_notification("safespot", "Safe Spot", "Failed to save position!", 5, color.red())
            end
        end)

        -- Button to move to the safe spot
        demo_gui:AddButton("Move to Safe Spot", 140, 180, 140, 25, function()
            if safe_spot then
                local player = core.object_manager.get_local_player()
                if player and player:is_valid() then
                    is_moving_to_safe_spot = true
                    path_calculation_needed = true  -- Recalculate path
                    current_waypoint_index = 1     -- Reset waypoint index
                    core.log("Starting movement to safe spot...")
                    core.graphics.add_notification("safespot", "Safe Spot", "Moving to saved position!", 5, color.green())
                else
                    core.log_warning("Player not valid, cannot start movement.")
                end
            else
                core.log_warning("No safe spot set.")
                core.graphics.add_notification("safespot", "Safe Spot", "No position saved!", 5, color.red())
            end
        end)
        
        -- Button to stop movement
        demo_gui:AddButton("Stop Movement", 290, 180, 100, 25, function()
            if is_moving_to_safe_spot then
                is_moving_to_safe_spot = false
                -- Stop all movement
                core.input.move_forward_stop()
                core.input.turn_left_stop()
                core.input.turn_right_stop()
                core.log("Movement to safe spot stopped.")
                core.graphics.add_notification("safespot", "Safe Spot", "Movement stopped!", 3, color.yellow())
            end
        end)
        
        -- Button to clear navmesh data
        demo_gui:AddButton("Clear Navmesh", 10, 210, 120, 25, function()
            local points_cleared = navmesh_grid_size
            navmesh_points = {}
            navmesh_grid_size = 0
            core.log("Manually cleared " .. points_cleared .. " navmesh points")
            core.graphics.add_notification("navmesh", "Navmesh", "Cleared all navmesh data!", 3, color.red())
        end)
        
        -- Register callbacks only if GUI was successfully initialized
        core.register_on_update_callback(on_frame)
        core.register_on_render_callback(on_render)
    end
else
    core.log("LxCommon GUI system not found!")
end

core.log("LX Debug environment ready")
